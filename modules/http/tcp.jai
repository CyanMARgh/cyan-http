#scope_module

close :: (using client : *TCP_Client) {
    close_and_reset(*socket);
}

read_with_timeout :: (client : TCP_Client, buffer : *void, length : int, timeout : int) -> TCP_Error #must, int {
    if length < 0 return .SOCKET_READ, 0;
    read_fds : fd_set;
    tv : POSIX.timeval;

    tv.tv_sec = timeout;
    tv.tv_usec = 0;

    FD_SET(client.socket, *read_fds);

    if FD_ISSET(client.socket, *read_fds) {
        // http_log(.DEBUG, "(0)\n");
        retval := select(client.socket + 1, *read_fds, null, null, *tv);
        // http_log(.DEBUG, "(1)\n");
        if retval == -1 {
            // http_log(.DEBUG, "(2)\n");
            return .SOCKET_SELECT, 0;
        } else if (retval == 0) {
            // http_log(.DEBUG, "(3)\n");
            return .RECV_TIMEOUT, 0;
        }

        n := POSIX.read(client.socket, buffer, xx length);

        // http_log(.DEBUG, "n = %\n", n);
        if n <= 0 return .SOCKET_READ, 0;
        return .NO_PROBLEM, n;
    }

    // log("last\n");
    return .SOCKET_READ, 0;
}

read_string_with_timeout :: (client : TCP_Client, length : int, timeout : int) -> TCP_Error #must, string {
    str := alloc_string(length);
    err, n := read_with_timeout(client, str.data, length, timeout);
    str.count = n;
    return err, str;
}

accept_tcp_client :: (using server : TCP_Server) -> TCP_Client, result:enum u8{OK; ERROR; TIMEOUT;} #must {
    TIMEOUT_SEC :: 10;

    using client : TCP_Client;
    set : fd_set;
    FD_SET(listen_socket, *set);

    timeout := POSIX.timeval.{tv_sec = TIMEOUT_SEC};
    rv := select(listen_socket + 1, *set, null, null, *timeout);

    if rv == -1 return .{}, .ERROR;
    if rv == 0 return .{}, .TIMEOUT;

    socket, address = accept(listen_socket);

    if socket < 0 return .{}, .ERROR;
    return client, .OK;
}

start_tcp_server :: (using tcp_server : *TCP_Server) -> TCP_Error {
    listen_socket = socket(AF_INET, .SOCK_STREAM, 0);
    if listen_socket < 0 {
        return .SOCKET;
    }

    optval : u32 = 1;
    if setsockopt(listen_socket, SOL_SOCKET, SO_REUSEADDR, *optval, 4) < 0 {
        return .SOCKET_SETOPT;
    }

    if bind(listen_socket, listen_host, listen_port) < 0 {
        err := get_last_socket_error();
        #if OS == .WINDOWS {
            if err == {
            case WSAEACCES; return .ACCESS;
            case WSAEADDRINUSE; return .ADDRESS_IN_USE;
            case; return .SOCKET_BIND;
            }
        } else {
            if err == {
            case POSIX.EACCES; return .ACCESS;
            case POSIX.EADDRINUSE; return .ADDRESS_IN_USE;
            case; return .SOCKET_BIND;
            }
        }
    }

    if listen(listen_socket, MAX_LISTEN_QUEUE) < 0 {
        return .SOCKET_LISTEN;
    }

    return .NO_PROBLEM;
}

close :: (using server : TCP_Server) {
    POSIX.close(listen_socket);    
}

send_with_timeout :: (client : TCP_Client, text : string, timeout : int) -> TCP_Error #must, int {
    // TODO this two methods are probably invalid, but i'm still not sure
    data, count := text.data, text.count;

    total_sent : int;
    sent : int;

    tv := POSIX.timeval.{tv_sec = timeout};

    write_fds : fd_set;
    FD_SET(client.socket, *write_fds);
    if setsockopt(client.socket, SOL_SOCKET, SO_SNDTIMEO, *tv, size_of(POSIX.timeval)) < 0 {
        return .SOCKET_SETOPT, 0;
    }

    while total_sent < count {
        // http_log(.DEBUG, "select()...\n");
        result := select(client.socket + 1, null, *write_fds, null, *tv);
        // http_log(.DEBUG, "done: %\n", result);
        if result == -1 {
            return .SOCKET_SELECT, total_sent;
        } else if result == 0 {
            return .SEND_TIMEOUT, total_sent;
        }

        assert(total_sent <= count);
        sent = POSIX.write(client.socket, data + total_sent, xx min(count - total_sent, SEND_BUFFER_MAX));

        if sent < 0 {
            return .SOCKET_SEND, total_sent;
        } else if sent == 0 {
            return .NO_PROBLEM, total_sent;
        }
        total_sent += sent;
    }

    return .NO_PROBLEM, total_sent;
}