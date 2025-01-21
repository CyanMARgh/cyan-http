// here is an example of how i do svg generation for my website.
// i do similar thing for entire pages, but it dependent on pandoc.

#import "http"(STOP_CRANK="/stop");
#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Thread";
#import "File";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Hash_Table";

database_mtx : Mutex;

HIDDEN_RESOURCES_PATH :: "res/hidden";

BUILD_TIME :: #run current_time_consensus();

main :: () {
    defer report_memory_leaks();

    http_module_init();
    defer http_module_deinit();

    server  : HTTP_Server;
    http_server_init(*server, "0.0.0.0", 8080, "logs/example_page_generation");
    defer http_server_deinit(*server);

    init(*database_mtx);
    defer destroy(*database_mtx);

    http_register_url(*server, "/", .GET, (r, d) => mk_redirect("/chessdiag/big_board"));

    http_register_url(*server, "/chessdiag/(.+)", .GET, (using request : HTTP_Request, data : *void) -> HTTP_Response {
        //                (.+)
        diagname := uri_captures[1];
        if path_escapes_document_root(diagname) return mk_response(.FORBIDDEN);

        make_directory_if_it_does_not_exist(tprint("%/chess/boards_svg", HIDDEN_RESOURCES_PATH));

        txt_path := tprint("%/chess/boards/%.txt", HIDDEN_RESOURCES_PATH, diagname);
        svg_path := tprint("%/chess/boards_svg/%.svg", HIDDEN_RESOURCES_PATH, diagname);
        ok, svg_dir_path, _ := split_from_right(svg_path, cast(u8)#char"/");
        if !ok return mk_response(.INTERNAL_SERVER_ERROR, "HOW????");

        mt_txt, _, exists_txt := file_modtime_and_size(txt_path);
        mt_svg, _, exists_svg := file_modtime_and_size(svg_path);

        if !exists_txt return mk_response(.FORBIDDEN, "no diagram source");

        if !exists_svg || mt_svg < mt_txt || mt_svg < BUILD_TIME {
            lock_guard(*database_mtx);
            board, ok := read_entire_file(txt_path);
            if !ok || !board return mk_response(.INTERNAL_SERVER_ERROR, "can't open diagram source");

            image := copy_string(scheme_to_svg(board,, temp));

            make_directory_if_it_does_not_exist(svg_dir_path);
            write_entire_file(svg_path, image);

            if !image return mk_response(.INTERNAL_SERVER_ERROR, "invalid diagram");
        }

        return response_file_unchecked(svg_path, headers);
    });

    http_server_run_and_log(*server);
}

#scope_file

scheme_to_svg :: (src : string) -> string {
    _sb : String_Builder;
    sb := *_sb;

    req :: (cond : bool, loc := #caller_location) #expand {
        if !cond {
            // print("invalid syntax, %\n", loc);
            `return "";
        }
    }

    ok, board, directives := split_from_left(src, cast(u8)#char".");
    req(ok);

    lines := filter(map(split(board, cast(u8)#char"\n"), l=>trim(l)), l => !!l);
    req(lines.count > 0);

    split_cells :: (line : string) -> []string {
        result : [..]string;
        i := 0;
        for j : 0..line.count-1 {
            if line[j] == #char"|" {
                array_add(*result, string.{data = line.data + i, count = j - i});
                i = j + 1;
            }
        }
        return result;
    }
    split_cell :: (str : string) -> []string {
        return filter(split(xx filter(cast([]u8)str, c=>c!=#char"_"), cast(u8)#char";"), l => !!l);
    }

    cells := map(lines, split_cells);
    // for cells print("%\n", it);

    for i : 1..cells.count - 1 {
        // print("% / %: [%]\n", cells[0].count, cells[i].count, cells[i]);
        req(cells[0].count == cells[i].count);
    }

    W, H := cells[0].count, cells.count;
    req(W > 0 && H > 0);

    piece_code_to_svg :: (code : string) -> string {
        if code.count != 2 return "";
        ok, template_id := array_find(PIECE_CODES, code[0]);
        if !ok return "";
        ok2, color_id := array_find(COLOR_CODES, code[1]);
        if !ok2 return "";
        scheme := COLOR_SCHEMES[color_id];
        template := TEMPLATES[template_id];
        return tprint(template, scheme[0], scheme[1]);
    }

    Element :: struct { 
        // type : enum u8 { PIECE; TEXT; }
        x, y : int;
        name : string;
    }
    VOID : void;

    deleted_cells := NewArray(W * H, bool);
    unique_elements : Table(string, string);
    elements : [..]Element;
    arrows : [..]Arrow;

    for l, y : cells {
        for g, x : l {
            for e : split_cell(g) {
                assert(e.count > 0);
                if e[0] == #char"x" {
                    deleted_cells[x + y * W] = true;
                } else  if e[0] == #char"t" {
                    // skip
                } else {
                    eptr, new := find_or_add(*unique_elements, e);
                    if new {
                        eptr.* = piece_code_to_svg(e);
                    }                    
                }
                array_add(*elements, .{x, y, e});
            }
        }
    }

    for line : split(directives, cast(u8)#char"\n") {
        if !trim(line) continue;
        ok, key, args := split_from_left(line, cast(u8)#char" ");
        if key == {
        // case ""; // nothing;
        case "a"; #through;
        case "arrow";
            ok, coords := scan("%d%d%d%d", args);
            req(ok);
            array_add(*arrows, .{
                a = .{xx cast_any(int, coords[0]), xx cast_any(int, coords[1])},
                b = .{xx cast_any(int, coords[2]), xx cast_any(int, coords[3])}
            });
        case; req(false);
        }
    }


    print(sb, MAIN, 1000, 1000. * H / W, W, H);

    for v, k : unique_elements {
        print(sb, "<g id=\"piece-%\">\n", k);
        append(sb, v);
        append(sb, "</g>\n");
    }

    print(sb, "</defs>\n");

    for yi : 0..H-1 {
        for xi : 0..W-1 {
            i := yi * W + xi;
            if deleted_cells[i] continue;
            j := yi + xi;
            name := ifx j % 2 then "light" else "dark";
            print(sb, "<use xlink:href=\"#cell-%\" x=\"%\" y=\"%\"/>\n", name, xi, yi);
        }
    }

    for elements {
        assert(it.name.count > 0);
        if it.name[0] == #char"x" {
            // print("!!!!\n");
        } else if it.name[0] == #char"t" {
            text := string.{data = it.name.data + 1, count = it.name.count - 1};
            N := 12 * max(4, text.count);
            print(sb, TEXT_BLOCK, it.x, it.y, N, N, text);
        } else if array_find(PIECE_CODES, it.name[0]) {
            print(sb, "<use xlink:href=\"#piece-%1\" x=\"%2\" y=\"%3\"/>\n", it.name, it.x, it.y);
        }
    }

    mk_arrow :: (sb : *String_Builder, using arrow : Arrow) {
        h := 0.3;

        add_vec2 :: (v : Vector2) #expand {
            print(sb, "%,% ", v.x + .5, v.y + .5);
        }

        append(sb, "<polygon points=\"");

        forward := normalize(b - a);
        right   := Vector2.{forward.y, -forward.x};

        add_vec2(a + right * h);
        add_vec2(a - right * h);
        add_vec2(b - forward * h - right * h);
        add_vec2(b - forward * h - right * 2 * h);
        add_vec2(b + forward * h);
        add_vec2(b - forward * h + right * 2 * h);
        add_vec2(b - forward * h + right * h);

        append(sb, "\" style=\"fill:lime;fill-opacity:0.5;stroke-opacity:0.5;stroke:black;stroke-width:0.06\" />\n");
    }

    for arrows {
        mk_arrow(sb, it);
    }

    append(sb, "</svg>\n");

    return builder_to_string(sb);
}

Color_Scheme :: [2]string;
COLOR_CODES :: #run cast([]u8)"wbBrgmyc";
COLOR_SCHEMES :: Color_Scheme.[
    .["white", "black"],
    .["black", "white"],
    .["blue", "black"],
    .["red", "black"],
    .["green", "black"],
    .["magenta", "black"],
    .["yellow", "black"],
    .["cyan", "black"]
];

Arrow :: struct { a : Vector2; b : Vector2; }

TEMPLATES :: string.[PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING, JOKER, ZONE];
PIECE_CODES :: #run cast([]u8)"pnbrqkjz";

TEXT_BLOCK :: #string SVG
<svg height="1" width="1" x="%1" y="%2" viewBox="0 0 %3 %4">
    <text x="50%%" y="50%%" dominant-baseline="middle" text-anchor="middle" font-family="Sans,Arial">%5</text>
</svg>
SVG

BISHOP :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <g style="opacity:1; fill:none; fill-rule:evenodd; fill-opacity:1; stroke:%2; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; stroke-miterlimit:4; stroke-dasharray:none; stroke-opacity:1;" transform="translate(0,0.6)">
        <g style="fill:%1; stroke:%2; stroke-linecap:butt;">
            <path d="M 9,36 C 12.39,35.03 19.11,36.43 22.5,34 C 25.89,36.43 32.61,35.03 36,36 C 36,36 37.65,36.54 39,38 C 38.32,38.97 37.35,38.99 36,38.5 C 32.61,37.53 25.89,38.96 22.5,37.5 C 19.11,38.96 12.39,37.53 9,38.5 C 7.65,38.99 6.68,38.97 6,38 C 7.35,36.54 9,36 9,36 z"/>
            <path d="M 15,32 C 17.5,34.5 27.5,34.5 30,32 C 30.5,30.5 30,30 30,30 C 30,27.5 27.5,26 27.5,26 C 33,24.5 33.5,14.5 22.5,10.5 C 11.5,14.5 12,24.5 17.5,26 C 17.5,26 15,27.5 15,30 C 15,30 14.5,30.5 15,32 z"/>
            <path d="M 25 8 A 2.5 2.5 0 1 1  20,8 A 2.5 2.5 0 1 1  25 8 z"/>
        </g>
        <path d="M 17.5,26 L 27.5,26 M 15,30 L 30,30 M 22.5,15.5 L 22.5,20.5 M 20,18 L 25,18" style="fill:none; stroke:%2; stroke-linejoin:miter;"/>
    </g>
</svg>
SVG;

ROOK :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <g style="opacity:1; fill:%1; fill-opacity:1; fill-rule:evenodd; stroke:%2; stroke-width:1.5; stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:4; stroke-dasharray:none; stroke-opacity:1;" transform="translate(0,0.3)">
        <path d="M 9,39 L 36,39 L 36,36 L 9,36 L 9,39 z " style="stroke-linecap:butt;" />
        <path d="M 12,36 L 12,32 L 33,32 L 33,36 L 12,36 z " style="stroke-linecap:butt;" />
        <path d="M 11,14 L 11,9 L 15,9 L 15,11 L 20,11 L 20,9 L 25,9 L 25,11 L 30,11 L 30,9 L 34,9 L 34,14" style="stroke-linecap:butt;" />
        <path d="M 34,14 L 31,17 L 14,17 L 11,14" />
        <path d="M 31,17 L 31,29.5 L 14,29.5 L 14,17" style="stroke-linecap:butt; stroke-linejoin:miter;" />
        <path d="M 31,29.5 L 32.5,32 L 12.5,32 L 14,29.5" />
        <path d="M 11,14 L 34,14" style="fill:none; stroke:%2; stroke-linejoin:miter;" />
    </g>
</svg>
SVG;

KING :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <g fill="none" fill-rule="evenodd" stroke="%2" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5">
        <path stroke-linejoin="miter" d="M22.5 11.63V6M20 8h5"/>
        <path fill="%1" stroke-linecap="butt" stroke-linejoin="miter" d="M22.5 25s4.5-7.5 3-10.5c0 0-1-2.5-3-2.5s-3 2.5-3 2.5c-1.5 3 3 10.5 3 10.5"/>
        <path fill="%1" d="M12.5 37c5.5 3.5 14.5 3.5 20 0v-7s9-4.5 6-10.5c-4-6.5-13.5-3.5-16 4V27v-3.5c-2.5-7.5-12-10.5-16-4-3 6 6 10.5 6 10.5v7"/>
        <path d="M12.5 30c5.5-3 14.5-3 20 0m-20 3.5c5.5-3 14.5-3 20 0m-20 3.5c5.5-3 14.5-3 20 0"/>
    </g>
</svg>
SVG;

JOKER :: #string SVG
<svg xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://www.w3.org/2000/svg" width="1" height="1" viewBox="0 0 26 26" version="1.1" xmlns:cc="http://creativecommons.org/ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <path stroke-linejoin="miter" style="enable-background:accumulate;color:%2;" d="m13,6.5c3.8079,0,4.5,11,4.5,11-3.5,1.5-5.5,1.5-9,0,0,0,0.69211-11,4.5-11z" stroke-dashoffset="0" stroke="%2" stroke-linecap="butt" stroke-miterlimit="4" stroke-dasharray="none" stroke-width="1" fill="%1"/>
    <path stroke-linejoin="miter" style="enable-background:accumulate;color:%2;" d="m7.5,21c-0.59238,1.9746,1.5234,2.5,5.5,2.5s6.0924-0.52539,5.5-2.5c-1.5-5-2.543-3.5-5.5-3.5s-4-1.5-5.5,3.5z" stroke-dashoffset="0" stroke="%2" stroke-linecap="butt" stroke-miterlimit="4" stroke-dasharray="none" stroke-width="1" fill="%1"/>
    <use xlink:href="#path5381" transform="matrix(-1,0,0,1,26,0)" height="26" width="26" y="0" x="0"/>
    <use xlink:href="#path4871" transform="matrix(-1,0,0,1,26,0)" height="26" width="26" y="0" x="0"/>
    <path id="path5381" stroke-linejoin="miter" style="enable-background:accumulate;color:%2;" d="M3.5,19.5c-6.5-11.5,0.5-23.5,9.5-13-0.96489,4.1612-1.1124,7.8988-4.5,11,0-10-6.5-13.5-5,2z" stroke-dashoffset="0" stroke="%2" stroke-linecap="butt" stroke-miterlimit="4" stroke-dasharray="none" stroke-width="1" fill="%1"/>
    <path id="path4871" stroke-linejoin="miter" d="m6.5407,20.564a2.4749,3.0494,0,1,1,-4.9497,0,2.4749,3.0494,0,1,1,4.9497,0z" transform="matrix(1.0101525,0,0,0.81983397,-0.60714285,3.640838)" stroke-dashoffset="0" stroke="%2" stroke-linecap="square" stroke-miterlimit="4" stroke-dasharray="none" stroke-width="1.09886306000000" fill="%1"/>
</svg>
SVG;

QUEEN :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <g style="fill:%1;stroke:%2;stroke-width:1.5;stroke-linejoin:round">
        <path d="M 9,26 C 17.5,24.5 30,24.5 36,26 L 38.5,13.5 L 31,25 L 30.7,10.9 L 25.5,24.5 L 22.5,10 L 19.5,24.5 L 14.3,10.9 L 14,25 L 6.5,13.5 L 9,26 z"/>
        <path d="M 9,26 C 9,28 10.5,28 11.5,30 C 12.5,31.5 12.5,31 12,33.5 C 10.5,34.5 11,36 11,36 C 9.5,37.5 11,38.5 11,38.5 C 17.5,39.5 27.5,39.5 34,38.5 C 34,38.5 35.5,37.5 34,36 C 34,36 34.5,34.5 33,33.5 C 32.5,31 32.5,31.5 33.5,30 C 34.5,28 36,28 36,26 C 27.5,24.5 17.5,24.5 9,26 z"/>
        <path d="M 11.5,30 C 15,29 30,29 33.5,30" style="fill:none"/>
        <path d="M 12,33.5 C 18,32.5 27,32.5 33,33.5" style="fill:none"/>
        <circle cx="6" cy="12" r="2" />
        <circle cx="14" cy="9" r="2" />
        <circle cx="22.5" cy="8" r="2" />
        <circle cx="31" cy="9" r="2" />
        <circle cx="39" cy="12" r="2" />
    </g>
</svg>
SVG;

PAWN :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <path d="m 22.5,9 c -2.21,0 -4,1.79 -4,4 0,0.89 0.29,1.71 0.78,2.38 C 17.33,16.5 16,18.59 16,21 c 0,2.03 0.94,3.84 2.41,5.03 C 15.41,27.09 11,31.58 11,39.5 H 34 C 34,31.58 29.59,27.09 26.59,26.03 28.06,24.84 29,23.03 29,21 29,18.59 27.67,16.5 25.72,15.38 26.21,14.71 26.5,13.89 26.5,13 c 0,-2.21 -1.79,-4 -4,-4 z" style="opacity:1; fill:%1; fill-opacity:1; fill-rule:nonzero; stroke:%2; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:miter; stroke-miterlimit:4; stroke-dasharray:none; stroke-opacity:1;"/>
</svg>
SVG;

KNIGHT :: #string SVG
<svg width="1" height="1" viewBox="0 0 45 45">
    <g style="opacity:1; fill:none; fill-opacity:1; fill-rule:evenodd; stroke:%2; stroke-width:1.5; stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:4; stroke-dasharray:none; stroke-opacity:1;" transform="translate(0,0.3)">
        <path d="M 22,10 C 32.5,11 38.5,18 38,39 L 15,39 C 15,30 25,32.5 23,18" style="fill:%1; stroke:%2;" />
        <path d="M 24,18 C 24.38,20.91 18.45,25.37 16,27 C 13,29 13.18,31.34 11,31 C 9.958,30.06 12.41,27.96 11,28 C 10,28 11.19,29.23 10,30 C 9,30 5.997,31 6,26 C 6,24 12,14 12,14 C 12,14 13.89,12.1 14,10.5 C 13.27,9.506 13.5,8.5 13.5,7.5 C 14.5,6.5 16.5,10 16.5,10 L 18.5,10 C 18.5,10 19.28,8.008 21,7 C 22,7 22,10 22,10" style="fill:%1; stroke:%2;" />
        <path d="M 9.5 25.5 A 0.5 0.5 0 1 1 8.5,25.5 A 0.5 0.5 0 1 1 9.5 25.5 z" style="fill:%2; stroke:%2;" />
        <path d="M 15 15.5 A 0.5 1.5 0 1 1  14,15.5 A 0.5 1.5 0 1 1  15 15.5 z" transform="matrix(0.866,0.5,-0.5,0.866,9.693,-5.173)" style="fill:%2; stroke:%2;" />
    </g>
</svg>
SVG

ZONE :: #string SVG
<rect width="1" height="1" fill="%1" opacity="0.7" />
SVG;

MAIN :: #string SVG
<?xml version="1.0"?>
<svg width="%1" height="%2" viewBox="0 0 %3 %4" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">

<defs>

<rect id="cell-light" width="1" height="1" fill="#eeeed2"/>
<rect id="cell-dark"  width="1" height="1" fill="#769655"/>
SVG;

lock_guard :: (mutex : *Mutex) #expand {
    lock(mutex);
    `defer unlock(mutex);
}

cast_any :: ($T : Type, value : Any) -> T {
    assert(cast(*Type_Info)type_info(T) == value.type);
    return (.*)cast(*T)value.value_pointer;
}

filter :: (src : []$T, $$cond : (T)->(bool)) -> []T {
    result : [..]T;
    for src if cond(it) array_add(*result, it);
    return result;
}
map :: (src : []$T1, $$proc : (T1)->($T2)) -> []T2 {
    result := NewArray(src.count, T2);
    for * result it.* = proc(src[it_index]);
    return result;
}
