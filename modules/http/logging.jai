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

#scope_export
http_log :: (kind : enum u8 {VERBOSE_OK; VERBOSE_FAIL; SHORT_OK; SHORT_FAIL; DEBUG;}, fmt : string, args : ..Any) #expand {
    #if MULTITHREAD {
        lock(*http_log_mtx);
        defer unlock(*http_log_mtx);        
    }

    debug   :: "debug.txt";
    short   :: "short.txt";
    verbose :: "verbose.txt";

    color : Console_Color;
    #if USE_LOGGING {
        dst : string;
        str := tprint(fmt, ..args);
        dublicate_to_stdout := false;
        write_time := true;
        ifx #complete kind == {
        case .VERBOSE_OK;
            dst = verbose;
            color = .GREEN;
        case .VERBOSE_FAIL;
            dst = verbose;
            color = .RED;
        case .SHORT_OK;
            dst = short;
            dublicate_to_stdout = true;
            color = .GREEN;
        case .SHORT_FAIL;
            dst = short;
            dublicate_to_stdout = true;
            color = .RED;
        case .DEBUG;
            dst = debug;
            dublicate_to_stdout = DO_DEBUG_LOGGING;
            write_time = false;
        }

        log_to_file(tprint("%/%", context.http_logging_root, dst), str, write_time = write_time);
        if dublicate_to_stdout {
            set_console_color(color);
            defer reset_console_color();
            write_string(str);
        }
    }
}

set_logging_root :: (root : string) {
    make_directory_if_it_does_not_exist(root, recursive=true);
    context.http_logging_root = root;
}

// free_logging_paths :: () {
// }

#scope_file

#add_context http_logging_root := "logs";

#import "Print_Color";