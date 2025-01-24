mk_auth_response :: () -> HTTP_Response {
    response := HTTP_Response.{ status = .UNAUTHORIZED };
    add_response_header(*response, "WWW-Authenticate", "Basic realm=\"R\"");
    return response;
}

mk_response :: (status : HTTP_Status_Code, info : $T = "") -> HTTP_Response {
    response := HTTP_Response.{status = xx status, body = sprint("<html><head><meta charset=\"UTF-8\"></head><body><p>%\n%</body></html>", status, info)};
    add_response_header(*response, "Content-Type", "text/html; charset=utf-8'");
    return response;
}

mk_redirect :: (to : string, status := HTTP_Status_Code.TEMPORARY_REDIRECT) -> HTTP_Response {
    response := HTTP_Response.{ status = status };
    add_response_header(*response, "Location", to);
    return response;
}

mk_response_404 :: (id : Any = "---") -> HTTP_Response {
    response := HTTP_Response.{status = 404, body = sprint("<html><head><meta charset=\"UTF-8\"></head><body><p>чувак, ты думал что-то здесь будет?</p><p>о, нет...</p><p>404: %</p></body></html>", id)};
    add_response_header(*response, "Content-Type", "text/html; charset=utf-8'");
    return response;
}

add_content_type_header :: (response : *HTTP_Response, str : string, $by_path := false) -> ok:bool {
    #if by_path {
        content_type := get_content_type_by_path(str);
    } else {        
        content_type := get_content_type_by_ext(str);
    }
    if !content_type return false;
    add_response_header(response, "Content-Type", content_type);
    return true;
}

response_file_unchecked :: (path : string, using headers : HTTP_Headers, max_age := 0, ignore_filetype := false) -> HTTP_Response {
    response := HTTP_Response.{status = 200, max_age = max_age};
    
    if !ignore_filetype {
        add_content_type_header(*response, path, by_path=true);
    }

    mtime, _, exists := file_modtime_and_size(path);
    if !exists return mk_response(.FORBIDDEN, "can't open file");

    #if USE_CONDITIONAL_HEADERS {
        if condflags & .IF_MODIFIED_SINCE {
            if mtime <= if_modified_since {
                return mk_response(.NOT_MODIFIED);
            }
        }
    }

    content, ok2 := read_entire_file(path);
    if !ok2 return mk_response(.INTERNAL_SERVER_ERROR);

    response.body = content;
    response.mtime = mtime;
    response.known_mtime = true;


    return response;
}

#scope_module
generate_response :: (server : *HTTP_Server, request : *HTTP_Request) -> HTTP_Response {
    #if MULTITHREAD {
        lock(*http_request_generator_mtx);
        defer unlock(*http_request_generator_mtx);
    }
    #if STOP_CRANK if request.uri == STOP_CRANK {
        stop_server(server);
        return .{status = .I_AM_A_TEAPOT};
    }

    #if WEIRD_PATH_BAN {
        path := request.uri;
        banned_keywords := string.["..", "/bin/", "/dev/"];

        if !path || contains(path, "//") || contains(path, "..") || contains(path, "/bin/") || contains(path, "/dev/") {
            return mk_response(.BAD_REQUEST, "я вижу, что ты пытаешься сделать 😉");
        }            
    }

    for route : server.routes {
        matched, captures := match(request.uri, route.regex,, temp);
        if !matched || !(request.verb & route.accept_verbs) continue;
        assert(captures.count > 0);
        assert(captures[0].count <= request.uri.count);
        if captures[0].count != request.uri.count continue; //skip partial match

        request.uri_captures = captures;
        response := route.handler.proc(request, route.handler.data);
    
        add_extra_response_headers(*response);
        return response;
    }

    return mk_response_404("no handlers found");
}

free_response :: (response: HTTP_Response) {
    free(response.body);
    for response.headers {
        free(it.key);
        free(it.value);
    }    
    array_free(response.headers);
}

get_content_type_by_ext :: (_ext : string) -> string {
    ext := _ext;
    category : string;
    if ext == {
    case "png"; #through;
    case "jpg"; #through;
    case "gif"; #through;
    case "webp";
        category = "image";
    case "mp4";
        category = "video";
    case "txt"; #through;
    case "css"; #through;
    case "html";
        category = "text";
    case "ico";
        ext = "x-icon";
        category = "image"; 
    case "svg";
        ext = "svg+xml";
        category = "image";
    case;
        return "";
    }
    return tprint("%/%", category, ext);    
}
get_content_type_by_path :: (filepath : string) -> string {
    ok, _, ext := split_from_right(filepath, cast(u8)#char".");
    if !ok return "";
    return get_content_type_by_ext(ext);
}

add_extra_response_headers :: (using response : *HTTP_Response) {
    add_response_header(response, "Content-Length", tprint("%", body.count));
    if max_age >= 0 {
        add_response_header(response, "Cache-Control", tprint("public, max-age=%", max_age));
    }
    if known_mtime {
        add_response_header(response, "Last-Modified", apollo_time_to_web_time(mtime));
    }
    if #complete connection_type == {
    case .NOT_STATED;
    case .KEEP_ALIVE;
        add_response_header(response, "Connection", "keep-alive");
    case .CLOSE;
        add_response_header(response, "Connection", "close");
    } 
}

send_response :: (client: *TCP_Client, response: HTTP_Response) -> TCP_Error #must {
    http_log(.DEBUG, "building request string...\n");
    sb : String_Builder;

    print_to_builder(*sb, "HTTP/1.1 % %\r\n", cast(int)response.status, http_get_status_text(response.status));

    for h:response.headers {
        print_to_builder(*sb, "%: %\r\n", h.key, h.value);
    }
    append(*sb, "\r\n");
    append(*sb, response.body);

    all_data := builder_to_string(*sb);
    http_log(.DEBUG, "done. writing...\n");

    err, count := send_with_timeout(client, all_data, 15);

    http_log(.DEBUG, "done.\n");
    return err;
}