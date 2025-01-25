#scope_export

log_debug         :: #bake_arguments l(flags = .VERY_VERBOSE_ONLY);
log_debug_error   :: #bake_arguments l(flags = .VERY_VERBOSE_ONLY | .ERROR);
log_verbose       :: #bake_arguments l(flags = .VERBOSE_ONLY);
log_verbose_error :: #bake_arguments l(flags = .VERBOSE_ONLY | .ERROR);

set_logging_root :: (root : string) {
    make_directory_if_it_does_not_exist(root, recursive=true);
    context.http_logging_root = root;
}

#scope_module
file_write_string :: (file : *File, content : string) {
    file_write(file, content.data, content.count);
}
log_to_file :: (dest : string, content : string, write_time := false) {
    file, ok := file_open(dest, for_writing = true, keep_existing_content = true);
    if !ok return;
    if write_time file_write_string(*file, tprint("[%]\n", calendar_to_string(to_calendar(current_time_consensus()))));
    file_write_string(*file, content);
    file_close(*file);
}

custom_http_logger :: (message : string, data : *void, info : Log_Info) {
    #if MULTITHREAD {
        lock(*http_log_mtx);
        defer unlock(*http_log_mtx);        
    }

    debug   :: "debug.txt";
    short   :: "short.txt";
    verbose :: "verbose.txt";

    color : Console_Color = .WHITE;
    dst : string;
    dublicate_to_stdout := false;
    write_time := true;

    if info.common_flags & .VERY_VERBOSE_ONLY {
        dst = "debug.txt";
        write_time = false;
        dublicate_to_stdout = DO_DEBUG_LOGGING;
    } else if info.common_flags & .VERBOSE_ONLY {
        dst = "verbose.txt";
    } else {
        dst = "short.txt";
        dublicate_to_stdout = true;
    }

    if info.common_flags & .ERROR {
        color = .RED;
    } else if info.common_flags & .WARNING {
        color = .YELLOW;
    } else if !(info.common_flags & .VERY_VERBOSE_ONLY) {
        color = .GREEN;
    }

    log_to_file(tprint("%/%", context.http_logging_root, dst), message, write_time = write_time);

    if dublicate_to_stdout {
        set_console_color(color);
        defer reset_console_color();
        write_string(message);
    }
}

#scope_file

l :: (#procedure_of_call log(""));

#add_context http_logging_root := "logs";

#import "Print_Color";




