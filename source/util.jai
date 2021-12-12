Date :: struct {
   month : Date.Month;
   day   : int;
   year  : int;

   Month :: enum {
      January   :: 1;
      February  :: 2;
      March     :: 3;
      April     :: 4;
      May       :: 5;
      June      :: 6;
      July      :: 7;
      August    :: 8;
      September :: 9;
      October   :: 10;
      November  :: 11;
      December  :: 12;
   }
}

get_system_date :: () -> Date {
   time := get_system_time(local = false);

   date: Date = ---;
   date.month = cast(Date.Month)time.month;
   date.day   = xx time.day;
   date.year  = xx time.year;

   return date;
}

get_local_date :: () -> Date {
   time := get_system_time(local = true);

   date: Date = ---;
   date.month = cast(Date.Month)time.month;
   date.day   = xx time.day;
   date.year  = xx time.year;

   return date;
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
to_string :: (date: Date, format_string := "%Y/%M/%D", allocator := context.allocator) -> string {
   date_builder: String_Builder;
   date_builder.allocator = allocator;

   while format_string.count {
      ok, token := next(*format_string);
      if !ok break;

      if token == #char "%" {
         ok, next_token := next(*format_string);
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

to_titlecase :: (value: string) -> string {
   excluded :: string.[
      // Articles
      "the", "a", "an",
      
      // Prepositions
      "in", "at", "on", "of", "to",

      "as", "and",
      "but", "for", "or", "nor",
   ];

   splits := split(value, " "); // @Leak
   for s: splits {
      s_lower := s;
      to_lower(s_lower);

      should_skip := false;
      for excluded if it == s_lower {
         should_skip = true;
         break;
      }

      if it_index != 0 && should_skip continue;
      splits[it_index][0] = to_upper(splits[it_index][0]);
   }

   return join(..splits, " "); // @Leak
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

parse_date :: (date_string: string) -> Date, bool {
   date: Date;
   parts := split(date_string, "/");
   parse_fail := false;

   // Janky date parsing
   for parts {
      part := it;
      parsed, ok := parse_int(*part);

      if !ok || parsed <= 0 {
         parse_fail = true;
         break;
      }

      // Month
      if !date.month && parsed <= 12 {
         date.month = cast(Date.Month)parsed;
      }
      // Day
      else if !date.day && parsed <= 31 {
         date.day = parsed;
      }
      // Year
      else if !date.year {
         date.year = parsed;
      }
   }

   if parse_fail return .{}, false;
   return date, true;
}

is_whitespace :: (chr: rune) -> bool {
    return chr == #char " "  ||
           chr == #char "\t" ||
           chr == #char "\n" ||
           chr == #char "\r";
}

is_alpha :: (chr: rune) -> bool {
   return (chr >= #char "a" && chr <= #char "z") ||
          (chr >= #char "A" && chr <= #char "Z");
}

is_digit :: (chr: rune) -> bool {
   return chr >= #char "0" &&
          chr <= #char "9";
}

is_valid_identifier :: (chr: rune) -> bool {
   return is_alpha(chr)    ||
          is_digit(chr)    ||
          chr == #char "_" ||
          chr == #char "-" ||
          chr == #char "/";
}

string_from_byte :: (chr: u8) -> string {
   str := alloc_string(1);
   str.data[0] = chr;
   return str;
}

// @Note(Judah): These are values we don't expect in the input text.
// They do have special meanings which could break -show-macros' output in
// some terminals.
ESCAPE_TAB         :: #run string_from_byte(1);
ESCAPE_NEWLINE     :: #run string_from_byte(2);
ESCAPE_SPACE       :: #run string_from_byte(3);
ESCAPE_OPEN_PAREN  :: #run string_from_byte(4);
ESCAPE_CLOSE_PAREN :: #run string_from_byte(5);

is_valid_escape :: (chr: rune) -> bool, string {
   if chr == {
      case #char "(" ; return true, ESCAPE_OPEN_PAREN;
      case #char ")" ; return true, ESCAPE_CLOSE_PAREN;
      case #char "t" ; return true, ESCAPE_TAB;
      case #char "n" ; return true, ESCAPE_NEWLINE;
      case #char "s" ; return true, ESCAPE_SPACE;
      case #char "\\"; return true, "\\"; // @FIXME
   }

   return false, "";
}

get_next_character :: (s: *string) -> code: rune, bytes: s64, success: Unicode_Result {
   if !s.count || !s.data return 0, 0, .SOURCE_EXHAUSTED;

   code, bytes, success := character_utf8_to_utf32(s.data, s.count);

   s.data  += bytes;
   s.count -= bytes;
   assert(s.count >= 0);

   return cast(rune)code, bytes, success;
}

next :: (str: *string) -> ok: bool, code: rune, length: s64 {
    if !str.count || !str.data return false, 0, 0;

    chr, bytes, status := get_next_character(str);
    if status != .CONVERSION_OK return false, 0, 0;

    return true, chr, bytes;
}

peek :: (str: *string) -> ok: bool, code: rune, length: s64 {
    ok, n, bytes := inline next(str);
    if !ok return false, 0, 0;

    str.data  -= bytes;
    str.count += bytes;

    return true, n, bytes;
}

consume_whitespace :: (str: *string) {
   while str.count {
      ok, value, width := next(str);
      if !ok return;

      if !is_whitespace(value) {
         str.count += width;
         str.data  -= width;
         break;
      }
   }
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
        array_add_if_unique(*set_values, cast(T)it);
    }

    return set_values;
}

is_upper         :: inline (chr: u8) -> bool { return chr >= #char "A" && chr <= #char "Z"; }
is_lower         :: inline (chr: u8) -> bool { return chr >= #char "a" && chr <= #char "z"; }
is_word_boundary :: inline (chr: u8) -> bool { return chr == #char "_" || chr == #char " " || chr == #char "." || chr == #char "-"; }

to_casey_case :: (convert: string, separate_words_with_underscores := false) -> string {
   builder: String_Builder;
   defer free_buffers(*builder);

   next_should_be_upper := false;
   for i: 0..convert.count - 1 {
      chr := convert.data[i];

      if i == 0 {
         append(*builder, to_upper(chr));
         continue;
      }

      if is_word_boundary(chr) {
         next_should_be_upper = true;
         if separate_words_with_underscores append(*builder, "_");
         continue;
      }

      if next_should_be_upper {
         append(*builder, to_upper(chr));
         next_should_be_upper = false;
         continue;
      }

      append(*builder, to_lower(chr));
   }

   return builder_to_string(*builder);
}

#if OS == .WINDOWS {
   #import "Windows";
   #import "Windows_Utf8";

   directory_exists :: (directory: Directory, allocator := context.allocator) -> bool {
      wide_dir := utf8_to_wide(directory, allocator);
      attributes := GetFileAttributesW(xx wide_dir);
      free(wide_dir, allocator);
      return (attributes != INVALID_FILE_ATTRIBUTES &&
             attributes & FILE_ATTRIBUTE_DIRECTORY);
   }
}
else #if OS == .LINUX {
   directory_exists :: (directory: Directory, allocator := context.allocator) -> bool {
      push_allocator(allocator);
      dir_name_c := to_c_string(directory); // @Note(Judah): Should actually be 'to_c_string' but it doesn't take an allocator yet.
      defer free(dir_name_c);
      stats: stat_t;
      return stat(dir_name_c, *stats) == 0 && S_ISDIR(stats.st_mode);
   }
}
