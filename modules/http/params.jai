param_in_query :: (uri_params: *URI_Params, param: string) -> bool {
    val, found := table_find(uri_params, param);
    return found;
}

get_param_string :: (uri_params: *URI_Params, param: string, default: string = "") -> string, bool {
    val, found := table_find(uri_params, param);
    if !found return default, false;
    return val, true;
}

get_param_int :: (uri_params: *URI_Params, param: string, default: int = 0) -> int, bool {
    val, found := table_find(uri_params, param);
    if !found return default, false;
    i, ok, rem := string_to_int(val);
    return i, ok && !rem;
}

get_param_float :: (uri_params: *URI_Params, param: string, default: float = 0.0) -> float, bool {
    val, found := table_find(uri_params, param);
    if !found return default, false;
    return string_to_float(val), true;
}

get_param_array_generic :: (uri_params : *URI_Params, param : string, getter : (string)->($T, bool)) -> []T, bool {
    val, found := table_find(uri_params, param);
    if !found return .[], false;
    str_vals := split(val, ",",, temp);
    vals := NewArray(str_vals.count, T,, temp);
    for str_vals {
        ok : bool;
        vals[it_index], ok = getter(it);
        if !ok {
            array_free(vals);
            return .[], false;
        }
    }
    return vals, true;    
}

get_param_float_array :: #bake_arguments get_param_array_generic(getter = (s : string) -> float, bool {;
    val, ok := string_to_float(s);
    return val, ok;
});
get_param_int_array :: #bake_arguments get_param_array_generic(getter = (s : string) -> int, bool {;
    val, ok := string_to_int(s);
    return val, ok;
});
get_param_hex_int_array :: #bake_arguments get_param_array_generic(getter = (s : string) -> int, bool {;
    val, ok := string_to_int(s, base=16);
    return val, ok;
});

get_param_string_array :: (request: *HTTP_Request, param: string) -> []string, bool {
    val, found := table_find(*request.uri_params, param);
    if !found return string.[], false;
    str_vals := split(val, ",",, temp);
    return str_vals, true;
}