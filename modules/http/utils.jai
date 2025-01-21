safe_replace :: (dst : *string, src : string) {
    free(dst.*);
    dst.* = src;
}

string_to_uint :: (t : string) -> ok:bool, result:int {
    if !t return false, 0;
    num :int= t[0] - #char"0";
    if !num && t.count > 1 return false, 0;
    for 1..t.count-1 {
        num = num * 10 + (t[it] - #char"0");
    }
    return true, num;
}

apollo_time_to_web_time :: (t : Apollo_Time) -> string {
    using c := to_calendar(t);
    return tprint("%, % % % %:%:% GMT",
        WEEK_DAYS_NAMES[day_of_week_starting_at_0],
        formatInt(day_of_month_starting_at_0 + 1, minimum_digits = 2),
        MONTH_NAMES[month_starting_at_0],
        formatInt(year, minimum_digits = 4),
        formatInt(hour, minimum_digits = 2),
        formatInt(minute, minimum_digits = 2),
        formatInt(second, minimum_digits = 2)
    );
}

web_time_to_apollo_time :: (str : string) -> Apollo_Time, ok:bool {
    date, ok := parse_http_date(str);
    if !ok return .{}, false;
    return calendar_to_apollo(date), true;
}

parse_http_date :: parse_http_imf_fixdate;

#scope_file

// uuuuuh why they just can't use ISO time or unix timestamp?
// https://www.rfc-editor.org/rfc/rfc7231#section-7.1.1.1
parse_http_imf_fixdate :: (str : string) -> Calendar_Time, ok:bool {
    req :: (cond : bool) #expand {
        if !cond `return .{}, false;
    }
    view :: inline (start : int, length : int) -> string #expand {
        return .{data = str.data + start, count = length};
    }
    req(str.count == 29);

    using result : Calendar_Time;
    ok : bool;

    ok=, _day_of_week_starting_at_0 := array_find(WEEK_DAYS_NAMES, view(0, 3));
    req(ok);
    day_of_week_starting_at_0 = xx _day_of_week_starting_at_0;
    req(view(3, 2) == ", ");
    ok=, day_of_month_starting_at_1 := parse_digit2(view(5, 2));
    day_of_month_starting_at_0 = xx,trunc(day_of_month_starting_at_1 - 1);
    req(ok);
    req(str[7] == #char" ");
    ok=, _month_starting_at_0 := array_find(MONTH_NAMES, view(8, 3));
    month_starting_at_0 = xx _month_starting_at_0;
    req(ok);
    req(str[11] == #char" ");
    ok=, _year := parse_digit4(view(12, 4));
    year = xx _year;
    req(str[16] == #char" ");
    ok=, _hour := parse_digit2(view(17, 2));
    hour = xx _hour;
    req(ok);
    req(str[19] == #char":");
    ok=, _minute := parse_digit2(view(20, 2));
    minute = xx _minute;
    req(ok);
    req(str[22] == #char":");
    ok=, _second := parse_digit2(view(23, 2));
    second = xx _second;
    req(ok);
    req(view(25, 4) == " GMT");

    return result, true;
}

WEEK_DAYS_NAMES :: string.["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
MONTH_NAMES :: string.["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

parse_digit2 :: inline (str : string) -> ok:bool, int {
    assert(str.count == 2);
    n0 :int= str[0] - #char"0";
    n1 :int= str[1] - #char"0";
    if n0 < 0 || n0 > 9 return false, 0;
    if n1 < 0 || n1 > 9 return false, 0;
    return true, n0 * 10 + n1;
}
parse_digit4 :: inline (str : string) -> ok:bool, int {
    assert(str.count == 4);
    n0 :int= str[0] - #char"0";
    n1 :int= str[1] - #char"0";
    n2 :int= str[2] - #char"0";
    n3 :int= str[3] - #char"0";
    if n0 < 0 || n0 > 9 return false, 0;
    if n1 < 0 || n1 > 9 return false, 0;
    if n2 < 0 || n2 > 9 return false, 0;
    if n3 < 0 || n3 > 9 return false, 0;
    return true, n0 * 1000 + n1 * 100 + n2 * 10 + n3;
}
