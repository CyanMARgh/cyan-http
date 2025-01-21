TCP_Server :: struct {
    listen_host  : string;
    listen_port  : u16;
    listen_socket: Socket;
}

TCP_Client :: struct {
    socket          : Socket;
    address         : sockaddr_in;
}


HTTP_Server :: struct {
    #as using tcp_server : TCP_Server;

    routes          : [..]HTTP_Route;

    shutdown        : bool;
    #if MULTITHREAD {
        queue_mtx   : Mutex;
        queue_sem   : Semaphore;

        tasks_queue : [..]HTTP_Client; // TODO use actual queue
        workers     : [NUM_THREADS]Thread;
    }

    logs_root       : string;
}

HTTP_Client :: struct {
    #as tcp_client         : TCP_Client;
    
    server                 : *HTTP_Server;
    error                  : TCP_Error; // TODO move to tcp_client
    max_requests_to_handle : int;
}


HTTP_Verb :: enum u16 {
    GET     :: 0x01;
    POST    :: 0x02;
    PUT     :: 0x04;
    DELETE  :: 0x08;
    PATCH   :: 0x10;
    TRACE   :: 0x20;
    OPTIONS :: 0x40;
    CONNECT :: 0x80;
    HEAD    :: 0x100;
    UNKNOWN :: 0;
}

HTTP_Route_Handler_Proc :: #type (request: HTTP_Request, data : *void) -> (HTTP_Response);
HTTP_Route_Handler :: struct {
    proc : HTTP_Route_Handler_Proc;
    data : *void;
}


HTTP_Route :: struct {
    regex           : Regexp;
    accept_verbs    : HTTP_Verb;
    handler         : HTTP_Route_Handler;
}


HTTP_Request :: struct {
    verb                : HTTP_Verb;
    uri_raw             : string;
        uri             : string;
            uri_captures: []string;
        uri_params      : URI_Params;
    protocol            : string;
    // #if USE_CONDITIONAL_HEADERS {
    headers             : HTTP_Headers;
    // }
    body                : string;
}

HTTP_Headers :: struct {
    #as list : [..]HTTP_Header;

    #if USE_CONDITIONAL_HEADERS {
        using conditionals : struct {
            condflags : enum_flags u8 { IF_MATCH; IF_NONE_MATCH; IF_MODIFIED_SINCE; IF_UNMODIFIED_SINCE; IF_RANGE; }
            // if_match : []string;
            if_modified_since : Apollo_Time;
            // TODO implement rest parts        
        };
    }
};

HTTP_Header :: struct { key : string; value : string; }

URI_Params :: Table(string, string);


HTTP_Response :: struct {
    status  : HTTP_Status_Code;
    headers : [..]HTTP_Header;
    body    : string;

    connection_type : enum u8 { NOT_STATED; KEEP_ALIVE; CLOSE; }
    
    using caching_info : struct {
        max_age : int = DEFAULT_MAX_AGE;
        known_mtime : bool;
        mtime : Apollo_Time;
    }
}

TCP_Error :: enum {
    NO_PROBLEM      ::   0; // Not an error!
    SOCKET          :: 601; // Some Socket Error.
    ACCESS          :: 602; // Trying to use privileged resources without permission
    ADDRESS_IN_USE  :: 603; // Address in use.
    ACCEPT          :: 604; // Error accepting connection.
    SOCKET_READ     :: 605; // Error reading from client socket.
    REQUEST_TOO_BIG :: 606; // We have arbitrary restrictions on request size. Sorry!
    NOT_HTTP        :: 607; // Not a correctly formatted HTTP request.
    UNKNOWN_VERB    :: 608; // Request had unknown verb associated.
    SPURIOUS        :: 609; // Spurious request; probably malformed.
    MANUAL_STOP     :: 610; // make /stop request to stop server, for debug only
    RECV_TIMEOUT    :: 611;
    SEND_TIMEOUT    :: 612;
    THREAD          :: 613;
    SOCKET_SETOPT   :: 614;
    SOCKET_BIND     :: 615;
    SOCKET_LISTEN   :: 616;
    SOCKET_SELECT   :: 617;
    SOCKET_SEND     :: 618;
}

is_good_status_code :: (code : HTTP_Status_Code) -> bool { return code > 0 && code <= 399; };
HTTP_Status_Code :: enum u32 {
    // CONTINUE :: 100;
    // SWITCHING_PROTOCOLS :: 101;
    // PROCESSING :: 102;
    // EARLY_HINTS :: 103;

    OK :: 200;
    // CREATED :: 201;
    // ACCEPTED :: 202;
    // NON_AUTHORITATIVE_INFORMATION :: 203;
    // NO_CONTENT :: 204;
    // RESET_CONTENT :: 205;
    PARTIAL_CONTENT :: 206;
    // MULTI_STATUS :: 207;
    // ALREADY_REPORTED :: 208;
    // IM_USED :: 209;

    // MULTIPLE_CHOISES :: 300;
    MOOVED_PERMANENTLY :: 301;
    // FOUND :: 302;
    // SEE_OTHER :: 303;
    NOT_MODIFIED :: 304;
    // USE_PROXY :: 305;
    // SWITCH_PROXY :: 306;
    TEMPORARY_REDIRECT :: 307;
    // PERMANENT_REDIRECT :: 308;

    BAD_REQUEST :: 400;
    UNAUTHORIZED :: 401;
    // PAYMENT_REQUIRED :: 402;
    FORBIDDEN :: 403;
    NOT_FOUND :: 404;
    // METHOD_NOT_ALLOWED :: 405;
    // NOT_ACCEPTABLE :: 406;
    // PROXY_AUTHENTICATION_REQUIRED :: 407;
    // REQUEST_TIMEOUT :: 408;
    // CONFLICT :: 409;
    // GONE :: 410;
    // LENGTH_REQUIRED :: 411;
    // PRECONDITION_FAILED :: 412;
    // PAYLOAD_TOO_LARGE :: 413;
    // URI_TOO_LONG :: 414;
    // UNSUPPORTED_MEDIA_TYPE :: 415;
    RANGE_NOT_SATISFIABLE :: 416;
    // EXPECTATION_FAILED :: 417;
    I_AM_A_TEAPOT :: 418;
    // MISDIRECTED_REQUEST :: 421;
    // UNPROCESSABLE_CONTENT :: 422;
    // LOCKED :: 423;
    // FAILED_DEPENDENCY :: 424;
    // TOO_EARLY :: 425;
    // UPGRADE_REQUIRED :: 426;
    // PRECONDITION_REQUIRED :: 428;
    // TOO_MANY_REQUESTS :: 429;
    // REQUEST_HEADER_FIELDS_TOO_LARGE :: 431;
    // UNAVAILABLE_FOR_LEGAL_REASONS :: 451;

    INTERNAL_SERVER_ERROR :: 500;
    NOT_IMPLEMENTED :: 501;
    // BAD_GATEWAY :: 502;
    // SERVICE_UNAVAILABLE :: 503;
    // GATEWAY_TIMEOUT :: 504;
    // HTTP_VERSION_NOT_SUPPORTED :: 505;
    // VARIANT_ALSO_NEGOTIATES :: 506;
    // INSUFFICIENT_STORAGE :: 507;
    // LOOP_DETECTED :: 508;
    // NOT_EXTENDED :: 510;
    // NETWORK_AUTHENTICATION_REQUIRED :: 511;
}

http_get_status_text :: (status: HTTP_Status_Code) -> string {
    if #complete status == {
    case .OK;                       return "OK";
    case .PARTIAL_CONTENT;          return "Partial Content";

    case .MOOVED_PERMANENTLY;       return "Mooved Permanently";
    case .NOT_MODIFIED;             return "Not modified";
    case .TEMPORARY_REDIRECT;       return "Temporary Redirect";

    case .BAD_REQUEST;              return "Bad Request";
    case .UNAUTHORIZED;             return "Unauthorized";
    case .FORBIDDEN;                return "Forbidden";
    case .NOT_FOUND;                return "Not Found";
    case .RANGE_NOT_SATISFIABLE;    return "Range Not Satisfiable";
    case .I_AM_A_TEAPOT;            return "I'm a teapot";

    case .INTERNAL_SERVER_ERROR;    return "Internal Server Error";
    case .NOT_IMPLEMENTED;          return "Not Implemented";
    }
    assert(false);
    return "";
}