#module_parameters(
    USE_LOGGING     := true,
    MULTITHREAD     := true,
    USE_TEMPORARY_ALLOCATOR_FOR_HANDLERS := true,
    SSL := false, // it is broken, do not turn on!
    STOP_CRANK := "",
    LIMIT_REQUESTS_BY := 0, // amount of requests per run. 0 means no limit
    USE_REQUEST_GENERATOR_LOCK := true, // for debugging purposes, requests 
    DO_DEBUG_LOGGING := false,
    USE_CONDITIONAL_HEADERS := true,
    DEFAULT_MAX_AGE := 15,
    DOUBLE_DOT_BAN := true // for more security, ban all requests, that has .. substring in it.
);

READ_BUFFER_MAX  :: 16 * 1024;
SEND_BUFFER_MAX  :: 1024 * 1024;

REQUEST_MAX_SIZE :: 1024 * 1024 * 64;

NUM_THREADS :: 8;
MAX_REQUESTS_PER_CONNECTION :: 100;
READ_TIMEOUT :: 10;

MAX_LISTEN_QUEUE :: 5;