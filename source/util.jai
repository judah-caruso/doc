Date :: struct {
    month : Date.Month;
    day   : int;
    year  : int;

    Month :: enum {
        January :: 1;
        February;
        March;
        April;
        May;
        June;
        July;
        August;
        September;
        October;
        November;
        December;
    }
}

/*
Format guide:
    [Y] Year  : 2099 
    [y] Year  : 99
    [M] Month : 09 
    [m] Month : September
    [D] Day   : 01
    [d] Day   : 1
*/
to_string :: (date: Date, format_string := "%Y/%M/%D", allocator := context.allocator, allocator_data := context.allocator_data) -> string {
    date_builder: String_Builder;
    date_builder.allocator = allocator;
    date_builder.allocator_data = allocator_data;

    while has_token(format_string) {
        token, ok := next(*format_string);
        if !ok break;

        if token == #char "%" {
            next_token, ok := next(*format_string);
            if !ok break;

            if next_token == {
                case #char "y";
                    bad := tprint("%", date.year);
                    bad.count = 2;
                    bad.data += 2;
                    append(*date_builder, bad);
                case #char "Y";
                    print_to_builder(*date_builder, "%", formatInt(date.year, minimum_digits = 4));

                case #char "M";
                    print_to_builder(*date_builder, "%", formatInt(cast(int)date.month, minimum_digits = 2));
                case #char "m";
                    print_to_builder(*date_builder, "%", date.month);

                case #char "d"; 
                    print_to_builder(*date_builder, "%", date.day);
                case #char "D";
                    print_to_builder(*date_builder, "%", formatInt(date.day, minimum_digits = 2));
            }

            continue;
        }

        append(*date_builder, character_utf32_to_utf8(token));
    }

    return builder_to_string(*date_builder);
}

operator < :: (lhs: Date, rhs: Date) -> bool {
    if lhs == rhs return false;

    year := lhs.year - rhs.year;
    if year < 0 return true;
    if year > 0 return false;

    month := lhs.month - rhs.month;
    if month < 0 return true;
    if month > 0 return false;

    return lhs.day < rhs.day;
}

operator > :: (lhs: Date, rhs: Date) -> bool {
    if lhs == rhs return false;
    return !(lhs < rhs);
}

operator == :: (lhs: Date, rhs: Date) -> bool {
    return (lhs.year == rhs.year) && (lhs.month == rhs.month) && (lhs.day == rhs.day);
}

has_token :: (str: string) -> bool {
    return str.count > 0;
}

get_next_character :: (s: *string) -> code: u32, bytes: s64, success: Unicode_Result {
    code, bytes, success := character_utf8_to_utf32(s.data, s.count);

    s.data  += bytes;
    s.count -= bytes;
    assert(s.count >= 0);

    return code, bytes, success;
}

next :: (str: *string) -> code: u32, ok: bool, length: s64 {
    if !str.count return 0, false, 0;

    chr, bytes, status := get_next_character(str);
    if status != .CONVERSION_OK return 0, false, 0;

    return chr, true, bytes;
}

peek :: (str: *string) -> code: u32, ok: bool, length: s64 {
    n, ok, bytes := inline next(str);
    if !ok return 0, false, 0;

    str.data  -= bytes;
    str.count += bytes;

    return n, true, bytes;
}

to_string :: (chr: u8) -> string #expand {
    str: string = ---;
    str.data  = *chr;
    str.count = 1;
    return str;
}

enum_flags_set :: (values: $T) -> []T #modify {
    if T.type != .ENUM then T = null;
} {
    set_values: [..]T;

    info := type_info(T);
    for info.values if (cast(T)it) & values {
        array_add(*set_values, cast(T)it);
    }

    return set_values;
}

#if OS == .WINDOWS {
    directory_exists :: (directory: string, allocator := context.allocator) -> bool {
        wide_dir := utf8_to_wide(directory, allocator);
        attributes := GetFileAttributesW(xx wide_dir);
        free(wide_dir, allocator);
        return (attributes != INVALID_FILE_ATTRIBUTES &&
                attributes & FILE_ATTRIBUTE_DIRECTORY);
    }
}
else #if OS == .LINUX {
    directory_exists :: (directory: string, allocator := context.allocator) -> bool {
        dir_name_c := temp_c_string(directory); // @Note(Judah): Should actually be 'to_c_string' but it doesn't take an allocator yet.
        stats: stat_t;
        return stat(dir_name_c, *stats) == 0 && S_ISDIR(stats.st_mode);
    }
}
