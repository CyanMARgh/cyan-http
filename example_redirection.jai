#import "http"(STOP_CRANK="/stop");
#import "Basic"()(MEMORY_DEBUGGER=true);

// if you want to run multiple servers at the same time, here is how:
main :: () {
    defer report_memory_leaks();
    http_module_use();

    server  : HTTP_Server;
    init(*server, "0.0.0.0", 8080, "logs/example_redirect/main");
    defer deinit(*server);

    register_url(*server, "/", .GET, (r : HTTP_Request, data : *void) -> HTTP_Response {
        response := HTTP_Response.{status = 200, body = copy_string("hi!")};
        add_content_type_header(*response, "txt");
        return response;
    });

    server_alt  : HTTP_Server;
    // log paths should not collide if you wont mix all of logs
    init(*server_alt, "0.0.0.0", 8081, "logs/example_redirect/alt");
    defer deinit(*server);

    register_url(*server_alt, ".*", .GET | .POST, (using request : HTTP_Request, data : *void) -> HTTP_Response {
        return mk_redirect(tprint("%1%2", "http://localhost:8080", uri));
    });

    // for now it will create 2 main + 8*2 worker threads, which is seems too much
    // but because they all most of the time will be in sleep state, i guess it's ok
    run_and_log(*server_alt, in_background = true);
    run_and_log(*server);
}


// (WTF MICROSERVICES MENTIONED???)