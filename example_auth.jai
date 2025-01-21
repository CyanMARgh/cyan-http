#import "http"(
    STOP_CRANK="/stop" // sending GET /stop will stop server (may be usefull for debugging, if you want to search for memory leaks)
);
#import "Basic"()(MEMORY_DEBUGGER=true);

main :: () {
    defer report_memory_leaks();

    http_module_init();
    defer http_module_deinit();

    server  : HTTP_Server;
    http_server_init(*server, "0.0.0.0", 8080, "logs/example_auth");
    defer http_server_deinit(*server);

    http_register_url(*server, "/", .GET, (request : HTTP_Request, data : *void) -> HTTP_Response {
        login := get_user_login(request);
        if !login return mk_auth_response();
        response := HTTP_Response.{status = 200, body = copy_string("hi!")};
        http_response_header_add(*response, "Content-Type", "text/txt");
        return response;
    });

    http_server_run_and_log(*server);
}

// parse_authorization() uses Basic maethod, so it is safe only if you serve over TLS
get_user_login :: (request : HTTP_Request) -> login:string {
    ok, login, password := parse_authorization(request);
    if !ok return "";

    // here are may sql or something like it
    if login == "login" return ifx password == "password" login;

    return "";
}
