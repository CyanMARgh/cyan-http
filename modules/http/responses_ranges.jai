response_file_ranges_unchecked :: (filepath : string, rangefmt : string, headers : HTTP_Headers) -> HTTP_Response {
    // todo parse rangefmt here
    
    MAX_RANGE_SUM :: 1 * 1024 * 1024;
    // MAX_RANGE_SUM :: 1 * 1024;
    BOUNDARY_SIZE :: 13;
    req :: (cond : bool, err : HTTP_Status_Code) #expand { if !cond `return mk_response(err, "can't generate range request"); } 

    content_type := get_content_type_by_path(filepath);
    req(content_type != "",. FORBIDDEN);

    // if is_directory return mk_redirect()

    mtime, file_size, exists := file_modtime_and_size(filepath);
    req(exists, .NOT_FOUND);

    file, ok_open := file_open(filepath);
    req(ok_open, .INTERNAL_SERVER_ERROR);
    defer file_close(*file);

    ranges := parse_rangefmt(rangefmt, file_size,, temp);
    assert(ranges.count >= 0);
    if ranges.count == 0 {
        if file_size < MAX_RANGE_SUM {
            return response_file_unchecked(filepath, headers);
        }
        ranges = .[.{0, MAX_RANGE_SUM}];
    }
    // req(ranges.count > 0, .RANGE_NOT_SATISFIABLE);

    edited : bool;
    // print("ranges: %\n", ranges);
    ranges, edited = crop_ranges(ranges, file_size, MAX_RANGE_SUM,, temp);

    sb := String_Builder;

    segments : [..]string;
    segments.allocator = temp;

    // for ranges {
    for array_view(ranges, 0, 1) {
        ok := file_set_position(file, it.begin);
        req(ok, .INTERNAL_SERVER_ERROR);
        text := alloc_string(it.count);

        ok2, num_bytes := file_read(file, text.data, text.count);
        req(ok2 && num_bytes == text.count, .INTERNAL_SERVER_ERROR);

        array_add(*segments, text);
    }

    assert(segments.count == 1, "% / %", ranges, segments);
    response := HTTP_Response.{status = .PARTIAL_CONTENT};
    add_response_header(*response, "Content-Range", tprint("bytes %-%/%", ranges[0].begin, ranges[0].begin + ranges[0].count - 1, file_size));
    add_response_header(*response, "Content-Type", content_type);

    response.body = segments[0];
    response.mtime = mtime;
    response.known_mtime = true;

    // TODO multiple segments support
    assert(segments.count == ranges.count);

    return response;
}

#scope_file
File_Range :: struct {
    begin : int;
    count : int;
}

parse_range :: (line : string, file_size : int) -> File_Range, ok:bool {
    req :: (cond : bool) #expand { if !cond `return .{}, false; }
    found, L, R := split_from_left(line, cast(u8)#char"-");

    okL, nL := string_to_uint(trim(L));
    okR, nR := string_to_uint(trim(R));

    if L && R {
        return .{nL, nR - nL + 1}, okL && okR;
    } else if L {
        return .{nL, file_size - nL}, okL;
    } else if R {
        return .{file_size - nR, nR}, okR;
    }
    return .{}, false;
}

// TODO maybe do ranges union
// TODO limit ranges count
crop_ranges :: (ranges : []File_Range, file_size : int, max_range_sum : int) -> []File_Range, edited:bool {
    assert(file_size >= 0 && max_range_sum >= 0);
    result : [..]File_Range;
    sum := 0;
    edited := false;
    for ranges {
        // totally invalid request
        if it.count < 0 || it.begin < 0 || it.begin > file_size {
            edited = true;
            continue;
        }

        range := it;
        if range.count > max_range_sum {
            range.count = max_range_sum;
            edited = true;
        }
        if range.begin + range.count > file_size {
            range.count = file_size - range.begin;
            edited = true;
        }
        if sum + range.count > max_range_sum {
            range.count = max_range_sum - sum;
            edited = true;
        }

        assert(range.count >= 0, "% %", range.count);
        if range.count {
            array_add(*result, range);
        }
        sum += range.count;
    }

    // extra assertions just in case there are some unchecked integer owerflows
    {
        for result assert(it.count > 0);

        sum2 : int;
        for result {
            sum2 += it.count;
            assert(sum2 <= max_range_sum);
            assert(it.begin >= 0);
            assert(it.begin + it.count <= file_size);
        }
    }

    return result, edited;
}

make_valid_boundary :: (parts : []string, length : int) -> string {
    assert(length > 0);
    ATTEMPTS :: 10;
    result := alloc_string(length);
    for 1..ATTEMPTS {
        for 0..length-1 {
            x := cast(int)(random_get() % 16);
            result[it] = xx ifx x < 10 then x + #char"0" else x + (#char"a" - 10);
        }
        ok := true;
        for parts {
            if contains(it, result) {
                ok = false;
                break;
            }
        }
        if ok return result;
    }

    return "";
}

parse_rangefmt :: (rangefmt : string, file_size : int) -> []File_Range {
    found, left, right := split_from_left(rangefmt, cast(u8)#char"=");
    if !found || left != "bytes" then return .[];
    lines := split(right, cast(u8)#char",",, temp);
    ranges := NewArray(lines.count, File_Range);
    for lines {
        ok_parse : bool;
        ranges[it_index], ok_parse = parse_range(it, file_size);
        if !ok_parse {
            array_free(ranges);
            return .[];
        }
    }
    return ranges;
}