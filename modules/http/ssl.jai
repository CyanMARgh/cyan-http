ssl_init :: (certificate: string, privatekey: string) {
    SSL_load_error_strings();
    OpenSSL_add_all_algorithms();

    ssl_ctx = SSL_CTX_new(TLS_server_method());
    init(*table, 1024+3); // idk man

    // SSL_CTX_set_options(ssl_ctx, SSL_OP_SINGLE_DH_USE); // idk what this does or if it's even necessary
    SSL_CTX_set_options(ssl_ctx, SSL_OP_NO_COMPRESSION | SSL_MODE_RELEASE_BUFFERS); // reduces memory usage. doesn't seem to actually work
    success_crt := SSL_CTX_use_certificate_file(ssl_ctx, temp_c_string(certificate) , SSL_FILETYPE_PEM);
    success_key := SSL_CTX_use_PrivateKey_file(ssl_ctx, temp_c_string(privatekey), SSL_FILETYPE_PEM);

    if !success_crt { print("failed to find certificate file: %\n", certificate); exit(1); }
    if !success_key { print("failed to find privatekey file: %\n", privatekey); exit(1); }
}

ssl_make_socket_ssl :: (socket: s32) {
    ssl := ssl_new();
    SSL_set_fd(ssl, socket);
    ssl_accept(ssl);
    table_add(*table, socket, ssl);
}

ssl_read :: (socket: s32, buffer: *u8, bufferlen: s32) -> s32 {
    ssl := table_find_pointer(*table, socket);
    if ssl == null {
        print("attempting to read from non-ssl socket: %", socket);
        exit(1);
    }
    return SSL_read(ssl.*, buffer, bufferlen);
}

ssl_write :: (socket: s32, buffer: *u8, bufferlen: s32) -> s32 {
    ssl := table_find_pointer(*table, socket);
    if ssl == null {
        print("attempting to write to non-ssl socket: %", socket);
        exit(1);
    }
    return SSL_write(ssl.*, buffer, bufferlen);
}

ssl_deinit :: () {
    // not yet implemented
}

ssl_delete :: (socket: s32) {
    ssl := table_find_pointer(*table, socket);
    if ssl != null {
        // SSL_shutdown(<<ssl);
        SSL_free(<<ssl);
    }
    table_remove(*table, socket);
}

ssl_print_errors :: () {
    while 1 {
        err := ERR_get_error();
        if err <= 0 break;

        print("ssl_error: %\n", to_string(ERR_error_string(err, null)));
    }
}

#scope_file

#import "Basic";
#import "Hash_Table";

table   : Table(s32, *SSL);
ssl_ctx : *SSL_CTX;

ssl_new :: () -> *SSL {
    return SSL_new(ssl_ctx);
}


ssl_is_socket_ssl :: (socket: s32) -> bool {
    return table_find_pointer(*table, socket) != null;
}

ssl_accept :: (ssl: *SSL) {
    accept_err := SSL_accept(ssl);
    if accept_err <= 0 then ssl_print_errors();
}

SSL_load_error_strings :: () -> s32 {
    return OPENSSL_init_ssl(OPENSSL_INIT_LOAD_CRYPTO_STRINGS | OPENSSL_INIT_LOAD_SSL_STRINGS, null);
}
OpenSSL_add_all_algorithms :: () -> s32 {
    return OPENSSL_init_crypto(OPENSSL_INIT_ADD_ALL_CIPHERS | OPENSSL_INIT_ADD_ALL_DIGESTS, null);
}


OPENSSL_INIT_LOAD_CRYPTO_STRINGS    :: 0x00000002;
OPENSSL_INIT_LOAD_SSL_STRINGS       :: 0x00200000;
OPENSSL_INIT_ADD_ALL_CIPHERS        :: 0x00000004;
OPENSSL_INIT_ADD_ALL_DIGESTS        :: 0x00000008;
SSL_OP_SINGLE_DH_USE                :: 0x00100000;
SSL_FILETYPE_PEM                    :: 1;
SSL_MODE_RELEASE_BUFFERS            :: 0x00000010;
SSL_OP_NO_COMPRESSION               :: 0x00020000;

// only pointers used, so it is what it is
OPENSSL_INIT_SETTINGS :: struct {};
SSL_METHOD :: struct {};
SSL_CTX :: struct {};
SSL :: struct {};


OPENSSL_init_ssl :: (opts: u64, settings: *OPENSSL_INIT_SETTINGS) -> s32 #foreign libssl;
OPENSSL_init_crypto :: (opts: u64, settings: *OPENSSL_INIT_SETTINGS) -> s32 #foreign libssl;
SSL_CTX_new :: (meth: *SSL_METHOD) -> *SSL_CTX #foreign libssl;
TLS_server_method :: () -> *SSL_METHOD #foreign libssl;
SSL_new :: (ctx: *SSL_CTX) -> *SSL #foreign libssl;
SSL_free :: (ssl: *SSL) #foreign libssl;
SSL_shutdown :: (ssl: *SSL) -> s32 #foreign libssl;
SSL_set_fd :: (s: *SSL, fd: s32) -> s32 #foreign libssl;
SSL_accept :: (s: *SSL) -> s32 #foreign libssl;
SSL_CTX_set_options :: (ctx: *SSL_CTX, op: u64) -> u64 #foreign libssl;
SSL_CTX_use_PrivateKey_file :: (ctx: *SSL_CTX, file_cstr: *u8, type: s32) -> s32 #foreign libssl;
SSL_CTX_use_certificate_file :: (ctx: *SSL_CTX, file_cstr: *u8, type: s32) -> s32 #foreign libssl;
SSL_read    :: (ssl: *SSL, buf: *u8, num: s32) -> s32 #foreign libssl;
SSL_write :: (ssl: *SSL, buf: *u8, num: s32) -> s32 #foreign libssl;
SSL_get_error :: (s: *SSL, ret_code: s32) -> s32 #foreign libssl;
ERR_get_error :: () -> u64 #foreign libssl;
ERR_error_string :: (e: u64, buf: *u8) -> *u8 #foreign libssl;

libssl :: #system_library "libssl";
libcrypto :: #system_library,link_always "libcrypto";
