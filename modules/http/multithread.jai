http_add_task :: (using server : *HTTP_Server, task : HTTP_Client) {
    lock(*queue_mtx);
        array_add(*tasks_queue, task);
    unlock(*queue_mtx);
    signal(*queue_sem);
}
http_wait_task :: (using server : *HTTP_Server) -> enum u8 { NEW_TASK; SHUTDOWN; }, HTTP_Client {
    wait_for(*queue_sem);
    lock(*queue_mtx);
    defer unlock(*queue_mtx);

    if shutdown {
        http_log(.DEBUG, "worker down\n");
        return .SHUTDOWN, .{};
    }
    
    assert(tasks_queue.count > 0);
    task := tasks_queue[0];
    array_ordered_remove_by_index(*tasks_queue, 0);
    return .NEW_TASK, task;
}

http_handle_connection_loop_thread_proc :: (thread : *Thread) -> s64 {
    server := cast(*HTTP_Server)thread.data;

    while 1 {
        result, task := http_wait_task(server);
        if #complete result == {
        case .SHUTDOWN; break;
        case .NEW_TASK; // do main part of iteration
        }

        http_handle_connection(*task);
    }

    reset_temporary_storage();
    return 0;
}

init_handlers_thread_pool :: (server : *HTTP_Server) -> TCP_Error {
    failed_at := 0;
    for * server.workers {
        it.data = server;
        it.starting_context = context;
        ok := thread_init(it, http_handle_connection_loop_thread_proc);
        if !ok {
            failed_at = it_index; break;
        }
    }
    if failed_at {
        for 0..failed_at-1 {
            thread_deinit(*server.workers[it]);
        }
        return .THREAD;
    }

    init(*server.queue_mtx);
    init(*server.queue_sem);

    for * server.workers thread_start(it);
    return .NO_PROBLEM;
}
deinit_handlers_thread_pool :: (server : *HTTP_Server) {
    for 1..NUM_THREADS signal(*server.queue_sem);

    array_free(server.tasks_queue);

    destroy(*server.queue_sem);
    destroy(*server.queue_mtx);

    for * server.workers {
        thread_deinit(it);
    }
}
