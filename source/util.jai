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

        append(*date_builder, token);
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

next :: (str: *string) -> u8, bool {
    if !str.count return 0, false;

    chr := str.data[0];
    str.data  += 1;
    str.count -= 1;

    return chr, true;
}

peek :: (str: *string) -> u8, bool {
    n, ok := inline next(str);
    if !ok return 0, false;

    str.data  -= 1;
    str.count += 1;

    return n, true;
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
