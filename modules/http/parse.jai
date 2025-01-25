#scope_export

// Most of this parsing routines do not fully satisfies RFC's specipifactions
// But as long as they work in 100% of the cases i encounter, i don't see the point in changing anything.
// If you have a counterexample, let me know.

// i'm implementing only IMF-fixdate for now

parse_authorization :: (request : HTTP_Request) -> bool, login:string, password:string {
    valid_login_character :: (c : u8) -> bool {
        return
            (c >= #char"A" && c <= #char"Z") ||
            (c >= #char"a" && c <= #char"z") ||
            (c >= #char"0" && c <= #char"9") ||
            c == #char"_";
    } 

    valid_password_character :: (c : u8) -> bool {
        return
            (c >= #char"!" && c <= #char"~") &&
            c != #char":";
    }

    req :: (cond : bool) #expand {
        if !cond `return false, "", "";
    }

    authstr := pick_header(request, "authorization");
    req(authstr != "");
    ok, method, value := split_from_left(authstr, cast(u8)#char" ");
    req(ok);

    // TODO not sure is it case-sensitive
    if method == {
    case "Basic";
        decoded := base64_decode(value,, temp);
        num_of_colons := 0;
        ok, login, password := split_from_left(decoded, cast(u8)#char":");
        req(ok && login.count > 0 && password.count > 0);
        for login req(valid_login_character(it));
        for password req(valid_password_character(it));
        print("got login:password:   %:%\n", login, password);
        return true, login, password;
    }

    return false, "", "";
}

pick_header :: (request : HTTP_Request, key : string) -> string {
    for request.headers.list {
        if equal_nocase(it.key, key) return it.value;
    }
    return "";
}
parse_uri_params :: (params: string) -> URI_Params {
    result : URI_Params;
    // TODO: Decode URI components correctly.
    paramset := split(params, "&");
    for paramset {
        found, key, value := split_from_left(it, "=");
        if found {
            key   = decode_uri_component(key);
            value = decode_uri_component(value);
            table_add(*result, key, value);
        } else {
            log_error("Problematic parameter '%'\n", it);
        }
    }
    return result;
}

get_range_fmt :: (request : HTTP_Request) -> string {
    rangefmt := pick_header(request, "range");
    return ifx rangefmt else "0-0";
}

html_string_escape :: (s : string) -> string {
    result : [..]u8;
    add :: (c : u8) #expand { array_add(*result, c); }
    for c : s {
        if c == {
        case #char"\"";
            for "$quot;" add(it);
        case #char"&";
            for "$amp;" add(it);
        case #char"'";
            for "&#039;" add(it);
        case #char"<";
            for "&lt;" add(it);
        case #char">";
            for "&gt;" add(it);
        case #char" ";
            for "&nbsp;" add(it);
        case;
            add(c);
        }
    }
    return xx result;
}

path_escapes_document_root :: (s : string) -> bool {
    is_slash :: inline c => c == #char"/" || c == #char"\\";
    is_dot :: inline c => c == #char".";

    depth := 0;
    state := enum u8 {
        NORMAL; SEP; DOT;
    }.NORMAL;

    for c, i : s {
        if state == {
        case .NORMAL;
            if is_slash(c) {
                state = .SEP;
            } else if i == 0 && is_dot(c) {
                state = .DOT;
            } else if i == 0 {
                depth += 1;
            }
        case .SEP;
            if is_dot(c) {
                state = .DOT;
            } else if !is_slash(c) {
                depth += 1;
                state = .NORMAL;
            }
        case .DOT;
            if c == #char"/" {
                state = .SEP;
            } else if is_dot(c) {
                depth -= 1;
                state = .NORMAL;
            } else {
                state = .NORMAL;
            }
        }
        if depth < 0 return true;
    }

    return false;
}

#scope_module

HTTP_Parsing_State :: enum u8 { METHOD :: 0; URI; VERSION; FIRST_LINE_R; HEADER; HEADER_R; BODY; }
HTTP_Parsing_Full_State :: struct {
    state : HTTP_Parsing_State;
    body_length_remained : int;
}

request_to_string :: (using request : HTTP_Request) -> string {
    sb := String_Builder.{allocator = temp};
    print_to_builder(*sb, "% % %\r\n", verb, uri_raw, protocol);
    for headers.list print_to_builder(*sb, "% : %\n", it.key, it.value);
    append(*sb, "\r\n");
    append(*sb, body);
    append(*sb, "\n");
    return builder_to_string(*sb);
}

read_request_and_parse_on_fly :: (using tcp_client : TCP_Client) -> TCP_Error #must, HTTP_Request {
    request_buffer : [..]u8;
    result : HTTP_Request;
    state : HTTP_Parsing_Full_State;
    total_scanned : int;

    for _main : 1..1 while true {
        log_debug("recv...\n");
        new_data : [READ_BUFFER_MAX]u8 = ---;
        err, n := read_with_timeout(tcp_client, *new_data, READ_BUFFER_MAX, READ_TIMEOUT);
        log_debug("% / %\n", err, n);
        if err return err, .{};
        total_scanned += n;
        if total_scanned > REQUEST_MAX_SIZE return .REQUEST_TOO_BIG, .{};

        ok, err2 := http_partial_request_parse(*result, *request_buffer, *state, ([]u8).{data = new_data.data, count = n});
        if err2 return err, .{};
        if ok break;
    }

    return .NO_PROBLEM, result;
}

http_partial_request_parse :: (request_parsed : *HTTP_Request, request_buffer : *[..]u8, state : *HTTP_Parsing_Full_State, new_data : []u8) -> finished:bool, TCP_Error #must {
    require :: (cond : bool, fmt : string, args : ..Any) #expand {
        if cond return;
        log_debug(fmt, ..args);
        `return false, .NOT_HTTP;
    }
    chop_parsed :: (request : *[..]u8) -> string {
        str := copy_string(xx request.*);
        request.count = 0;
        return str;
    }
    accept :: (cond : (u8)->(bool)) #expand {
        if cond(`c) {
            array_add(`request_buffer, `c);
            continue;
        }
    }
    switch :: (next : HTTP_Parsing_State) #expand {
        state.state = next;
        continue;
    }

    latin_capital :: c => c >= #char"A" && c <= #char"Z";
    plain :: c => c >= #char"!" && c <= #char"~";
    plain_or_space :: c => c >= #char" " && c <= #char"~";
    CR, LF, SP :: cast(u8)#char"\r", cast(u8)#char"\n", cast(u8)#char" ";

    for c : new_data {
        if #complete state.state == {
        case .METHOD;
            accept(latin_capital);
            if c == SP {
                request_parsed.verb = string_to_http_verb(chop_parsed(request_buffer));
                require(request_parsed.verb != .UNKNOWN, "unknown verb\n");
                switch(.URI);
            }
        case .URI;
            accept(plain);
            if c == SP {
                request_parsed.uri_raw = chop_parsed(request_buffer);
                request_parsed.uri, request_parsed.uri_params = parse_uri(request_parsed.uri_raw);
                switch(.VERSION);
            }
        case .VERSION;
            accept(plain);
            if c == CR switch(.FIRST_LINE_R);
        case .FIRST_LINE_R;
            if c == LF {
                request_parsed.protocol = chop_parsed(request_buffer);
                switch(.HEADER);
            }
        case .HEADER;
            accept(plain_or_space);
            if c == CR switch(.HEADER_R);
        case .HEADER_R;
            if c == LF {
                header_str := chop_parsed(request_buffer);
                if header_str {
                    ok, header := parse_http_first_line(header_str);
                    // log_debug("header: %\n", header);
                    if header.key == "Content-Length" {
                        num, ok := string_to_int(header.value);
                        // log_debug("num: %\n", num);
                        if !ok return false, .NOT_HTTP;
                        if num > REQUEST_MAX_SIZE return false, .REQUEST_TOO_BIG;
                        log_debug("C-L: [%]\n", num);
                        state.body_length_remained = num;
                    }
                    require(ok, "invalid header\n");
                    array_add(*request_parsed.headers.list, header);
                    switch(.HEADER);
                }
                // log_debug("rem: %\n", state.body_length_remained);
                if state.body_length_remained > 0 switch(.BODY);
                return true, .NO_PROBLEM;
            }
        case .BODY;
            array_add(request_buffer, c);
            state.body_length_remained -= 1;
            // log_debug("remained: %\n", state.body_length_remained);
            assert(state.body_length_remained >= 0);
            if state.body_length_remained == 0 {
                request_parsed.body = chop_parsed(request_buffer);
                // log_debug("BODY: %\n", request_parsed.body);
                return true, .NO_PROBLEM;
            }
            continue;
        }
        require(false, "UNEXPECTED: % / %\n", c, state.*);
    }

    return false, .NO_PROBLEM;
}

#scope_file

decode_uri_component :: (s: string) -> string {
    in := s;
    out : string;
    out.data = alloc(in.count,, temp);
    out.count = 1;

    char_to_hex :: (c : u8) -> u8 {
        if c >= #char "a" {            
            c -= #char "a" - #char "A";
        }
        if c >= #char "A" {
            c -= #char "A" - 10;
        } else {
            c -= #char "0";
        }
        return c;
    }
    is_hex_digit :: (c: u8) -> bool {
        return (c >= #char "0" && c <= #char "9")
            || (c >= #char "a" && c <= #char "f")
            || (c >= #char "A" && c <= #char "F");
    }

   while in.count > 0 {
        if (in[0] == #char "%" && in.count >= 2 
         && is_hex_digit(in[1]) && is_hex_digit(in[2])
        ) {
            out[out.count-1] = char_to_hex(in[1]) * 16 + char_to_hex(in[2]);
            out.count += 1;
            advance(*in, 3);
        } else if in[0] == #char "+" {
            out[out.count-1] = #char " ";
            out.count += 1;
            advance(*in);
        } else {
            out[out.count-1] = in[0];
            out.count += 1;
            advance(*in);
        }
    }
    out.count -= 1;
    return out;
}

parse_uri :: (uri : string) -> path:string, params:URI_Params {
    ok, path, _params := split_from_left(uri, cast(u8)#char"?");
    params : URI_Params;

    if ok {
        params = parse_uri_params(_params);
    }
    return path_to_string(parse_path(decode_uri_component(path))), params;
}

parse_http_first_line :: (line : string) -> bool, HTTP_Header {
    ok, left, right := split_from_left(line, cast(u8)#char":");
    if !ok return false, .{};
    return true, .{key = trim(left), value = trim(right)};
}

string_to_http_verb :: (str : string) -> HTTP_Verb {
    if str == {
    case "GET";     return .GET;
    case "POST";    return .POST;
    case "PUT";     return .PUT;
    case "DELETE";  return .DELETE;
    case "PATCH";   return .PATCH;
    case "TRACE";   return .TRACE;
    case "OPTIONS"; return .OPTIONS;
    case "CONNECT"; return .CONNECT;
    case "HEAD";    return .HEAD;
    case; 
        return .UNKNOWN;
    }    
}
