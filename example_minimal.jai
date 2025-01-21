#import "http"(STOP_CRANK="/stop");
#import "Basic"()(MEMORY_DEBUGGER=true);

main :: () {
    defer report_memory_leaks();

    http_module_init();
    defer http_module_deinit();

    server  : HTTP_Server;
    http_server_init(*server, "0.0.0.0", 8080, "logs/example_minimal");
    defer http_server_deinit(*server);

    http_register_url(*server, "/", .GET, (r : HTTP_Request, data : *void) -> HTTP_Response {
        // you can construct body any way you want, here it's just copies the text.
        // if you run server with option USE_TEMPORARY_ALLOCATOR_FOR_HANDLERS = true (on by default)
        // then you can just pass value as it is, but i prefer copy anyway for now for debugging purposes.
        response := HTTP_Response.{status = 200, body = copy_string(RESPONSE)};
        http_response_header_add(*response, "Content-Type", "text/html");
        return response;
    });

    // there are few common response procedures in responses.jai, that you can use.
    // response_file_unchecked and response_file_ranges_unchecked do cache control
    // second one limits response body size by 1MB
    // they are called _unchecked, because they do not check root escaping
    http_register_url(*server, "/favicon-32x32.png", .GET, (r, d) => response_file_unchecked("./res/public/favicon/favicon-32x32.png", r.headers));

    http_server_run_and_log(*server);
}

RESPONSE :: #string HTML
<html>
    <head>
    </head>
<body>
    <h1>Hello sailor</h1>
</body>
</html>
HTML