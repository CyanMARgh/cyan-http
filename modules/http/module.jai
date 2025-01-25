#scope_module

#if OS != .WINDOWS {
    // soory, but atm module works only on linux
    POSIX :: #import "POSIX";
}
#import "Socket";
#import "Basic";
#import "String";
#import "Hash_Table";
#import "File";
#import "uniform";
#import "Base64";
#import "File_Utilities";
#if MULTITHREAD #import "Thread";

#load "tcp.jai";
#load "logging.jai";
#load "responses.jai";
#load "responses_ranges.jai";
#load "parse.jai";
#load "params.jai";
#load "config.jai";
#load "types.jai";
#load "utils.jai";
#if MULTITHREAD #load "multithread.jai";
#if SSL #load "ssl.jai";

#if MULTITHREAD {
    http_log_mtx : Mutex;
    #if USE_REQUEST_GENERATOR_LOCK {
        http_request_generator_mtx : Mutex;
    }
}

#scope_export
http_module_use :: () #expand {
    POSIX.signal(POSIX.SIGPIPE, POSIX.SIG_IGN);
    #if SSL {
        ssl_init(certificate="keys/fullchain.pem", privatekey="keys/privkey.pem");
        ssl_print_errors();
    }

    #if MULTITHREAD {
        init(*http_log_mtx);
        #if USE_REQUEST_GENERATOR_LOCK {
            init(*http_request_generator_mtx);
        }
    }

    old_logger := context.logger;
    context.logger = custom_http_logger;

    `defer {
        context.logger = old_logger;

        #if MULTITHREAD {
            destroy(*http_log_mtx);
            #if USE_REQUEST_GENERATOR_LOCK {
                destroy(*http_request_generator_mtx);
            }
        }

        #if SSL {
            ssl_deinit();
        }        
    }
}

register_url :: (server: *HTTP_Server, path: string, accept_verbs: HTTP_Verb, handler: HTTP_Route_Handler_Proc, data : *void = null) {
    array_add(*server.routes, .{
        regex = compile(path),
        accept_verbs = accept_verbs,
        handler = .{proc = handler, data = data}
    });
}

stop_server :: (using server : *HTTP_Server) {
    log_verbose("manual stop\n");
    #if MULTITHREAD {
        lock(*queue_mtx);
        unlock(*queue_mtx);
    }
    shutdown = true;
}

run_and_log :: (server : *HTTP_Server, $in_background := false) #expand {
    #if in_background {
        server_thread : Thread;
        server_thread.data = server;
        redirector_thread_proc :: (thread : *Thread) -> int {
            server := cast(*HTTP_Server)thread.data;
            err := run(server);
            if err != .NO_PROBLEM print("server error: %\n", err);
            return 0;
        }

        ok := thread_init(*server_thread, redirector_thread_proc);
        assert(ok, "failed to start server thread!\n");
        thread_start(*server_thread);
        `defer thread_deinit(*server_thread);
    } else {
        err := run(server);
        if err != .NO_PROBLEM then print("server error: %\n", err);
    }
}

run :: (server: *HTTP_Server) -> TCP_Error #must {
    set_logging_root(server.logs_root);
    log("starting server on %:%\n", server.listen_host, server.listen_port);

    err := start_tcp_server(server);
    if err != .NO_PROBLEM { return err; }
    defer close(server);

    #if MULTITHREAD {
        err = init_handlers_thread_pool(server);
        if err return err;
        defer deinit_handlers_thread_pool(server);        
    }

    requests_count := 0;
    while main_loop:=true {
        log_debug("waiting for connection...\n");
        connection : TCP_Client;
        // TODO temporal workaround for manual server stop
        while waiting_loop:=true {
            if should_shutdown(server) break main_loop;

            connection=, res := accept_tcp_client(server);
            if #complete res == {
            case .OK; break waiting_loop;
            case .ERROR; break main_loop;
            case .TIMEOUT; continue;
            }
        }
        log_debug("connected: [%]\n", to_string(connection.address,, temp));

        task := HTTP_Client.{tcp_client = connection, server = server};
        #if MULTITHREAD {
            task.max_requests_to_handle = MAX_REQUESTS_PER_CONNECTION;
            http_add_task(server, task);
        } else {
            // allow only one request to be processed so that the server does not stand idle waiting
            // for new requests (or N seconds timeout) that it will never receive. Tests have shown
            // that the browser can send some requests through one connection, and then stop sending
            // them and start sending them through another port, never terminating the old connection.
            task.max_requests_to_handle = 1;
            http_handle_connection(*task);
            reset_temporary_storage();
        }

        requests_count += 1;
        #if LIMIT_REQUESTS_BY > 0 if requests_count == LIMIT_REQUESTS_BY {
            stop_server();
            break;
        }
    }
    log_debug("exiting...\n");

    return .NO_PROBLEM;
}

add_response_header :: (response: *HTTP_Response, header: string, content: string) {
    #if USE_TEMPORARY_ALLOCATOR_FOR_HANDLERS {
        array_add(*response.headers, .{key = header, value = content});
    } else {
        array_add(*response.headers, .{key = copy_string(header), value = copy_string(content)});
    }
}

init :: (using server : *HTTP_Server, _listen_host := "0.0.0.0", _listen_port :u16= 80, _logs_root := "logs_main") {
    listen_host = _listen_host;
    listen_port = _listen_port;
    logs_root   = _logs_root;
}

deinit :: (using server: HTTP_Server) {
    array_free(routes);

    for * routes {
        uninit(*it.regex);
        // free(it.handler.data);
    }
}

lock_quard :: (using server : *HTTP_Server) #expand {
    #if MULTITHREAD {
        lock(*server.queue_mtx);
        `defer unlock(*server.queue_mtx);        
    }
}

#scope_module

handle_connection :: (using http_client : *HTTP_Client) {
    log_debug("serving connection: %\n", to_string(tcp_client.address,, temp));

    request_id := 0;
    defer {
        log_debug("closing connection, handled: %\n", request_id);
        close(http_client);
    }

    while request_id < max_requests_to_handle {
        defer reset_temporary_storage();
        log_debug("reading request...\n");
        request : HTTP_Request;
        error, request = read_request_and_parse_on_fly(tcp_client,, temp);
        log_debug("done.\n");
        if error {
            show := error != .RECV_TIMEOUT && error != .SOCKET_READ;
            log("ERROR: %\n", error, flags = ifx show then .ERROR else .VERY_VERBOSE_ONLY);
            log_verbose_error("%\n", request_to_string(request,, temp));
            return;
        }

        parse_common_headers(*request.headers);

        response : HTTP_Response;
        log_debug("generating response...\n");
        // TODO temporally, i do this instead of proper File_Async

        #if USE_TEMPORARY_ALLOCATOR_FOR_HANDLERS {
            response = generate_response(server, *request,, temp);
        } else {
            response = generate_response(server, *request);
            defer free_response(response);
        }

        response.connection_type = ifx request_id < max_requests_to_handle - 1 then .KEEP_ALIVE else .CLOSE;
        log_debug("done.\n");

        log_debug("sending response...\n");
        error = send_response(*tcp_client, response,, temp);
        log_debug("done (%).\n", error);
        {
            lock_quard(server);
            server.handled_requests_counter += 1;
        }
        
        ok := is_good_status_code(response.status);
        response_info := tprint("[%] [%] % %", to_string(tcp_client.address,, temp), ifx cast(int)error then cast(int)error else cast(int)response.status, request.verb, request.uri_raw);
        log("%\n", response_info, flags = ifx ok then .NONE else .ERROR);
        log(
            "%\n%\n\n",
            response_info, request_to_string(request,, temp),
            flags = ifx ok then .VERBOSE_ONLY else .VERBOSE_ONLY | .ERROR
        );

        if error return;
        // this is because clients just can't face the reality and live in world
        // where their request is invalid
        if !is_good_status_code(response.status) break;

        request_id += 1;
    }
}

#scope_file

should_shutdown :: (using server : *HTTP_Server) -> bool {
    lock_quard(server);
    return shutdown;
}

parse_common_headers :: (using request : *HTTP_Headers) {
    for *list {
        #if USE_CONDITIONAL_HEADERS {
            if equal_nocase(it.key, "If-Modified-Since") {
                t, ok := web_time_to_apollo_time(it.value);
                if !ok continue;
                log_verbose("If-Modified-Since: %\n", calendar_to_string(to_calendar(t)));
                condflags |= .IF_MODIFIED_SINCE;
                if_modified_since = t;
            }             
        }
    }
}

