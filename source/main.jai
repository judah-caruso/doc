rune      :: #type,isa u32;
File_Path :: #type,isa string;
Directory :: #type,isa string;

// @Todo(Judah): Fix macros within multi-format macros not resolving properly.
// i.e: (macro jp (paragraph (edit-modify justify \ $1))) only outputs html
// macro, regardless of the format. For now this is fixed by defining the macro
// (with the same content) for each format individually.

Output_Format :: enum_flags {
   None;
   Html;
   Markdown;
   Text;
   Xml;
}

Macro :: struct {
   kind    : Macro.Kind;
   formats : Output_Format;

   name      : string;
   contents  : Table(Output_Format, string);
   arguments : u64;

   action: (post: *Post, args: ..string) -> bool;
   modify: (post: *Post, args: ..string) -> string, bool;

   Kind :: enum {
      Text;
      Action;
      Modify;
   };
}

Post :: struct {
   kind         : Post.Kind = .Post;
   title        : string;
   url          : string;
   author       : string;
   introduction : string;
   published    : Date;
   updated      : Date;
   tags         : [..]string;
   // footnotes : [..]string;

   current_format : Output_Format;
   contents       : Table(Output_Format, string);

   Kind :: enum {
      None;
      Post;
      Page;
   };
}

process_macro_definition :: (formats: Output_Format, source: *string, post: *Post) -> bool {
   consume_whitespace(source);

   name := <<source;
   name.count = 0;

   while source.count {
      ok, chr, width := next(source);
      if !ok || !is_valid_identifier(chr) break;
      name.count += width;
   }

   consume_whitespace(source);

   builder: String_Builder; // @Leak

   while source.count {
      ok, chr, width := next(source);
      if !ok || chr == #char ")" {
         source.data  -= width;
         source.count += width;
         break;
      }

      if chr == #char "\\" {
         ok, chr := peek(source);
         if !ok break;

         // Escape sequence
         escape_ok, sequence := is_valid_escape(chr);
         if escape_ok {
            append(*builder, sequence);
            next(source);
         }
         else {
            value := to_string(cast(u8)chr);
            print("ERROR: Invalid escape sequence '\\%'\n", value);
            return false;
         }

         continue;
      }

      if chr == #char "(" {
         macro_is_unknown := true;

         for fmt: enum_flags_set(formats) {
            src := source;
            ok, output := process_macro(fmt, src, post, .Pre_Pass);
            if !ok continue;

            append(*builder, output);
            macro_is_unknown = false;
            break;
         }

         if macro_is_unknown {
            print("ERROR: Unknown macro '%'\n", name); // @Errors
            return false;
         }

         continue;
      }

      append(*builder, character_utf32_to_utf8(chr)); // @Leak
   }

   body := builder_to_string(*builder);
   body = trim(body, " \t\n\r");

   found, macro := find_macro(name);
   if !found {
      macro         = table_set(*all_macros, name, .{});
      macro.name    = name;
      macro.formats = formats;

      // Get arguments from macro body
      scanner := body;
      while scanner.count {
         ok, value := next(*scanner);
         if !ok break;

         if value == #char "$" {
            argument := scanner;
            argument.count = 0;

            while scanner.count {
               ok, value, width := next(*scanner);
               if !ok || !is_digit(value) {
                  scanner.data  -= width;
                  scanner.count += width;
                  break;
               }

               argument.count += width;
            }

            to_parse := argument;
            parsed_value, ok := parse_int(*to_parse, u64);

            if !ok {
               print("Invalid argument in macro: '$%'\n", argument);
               return false;
            }

            if parsed_value > macro.arguments {
               macro.arguments = parsed_value;
            }
         }
      }
   }
   else {
      macro.formats |= formats;
   }

   for format: enum_flags_set(formats) {
      table_set(*macro.contents, format, body);
   }

   return true;
}

process_macro_invocation :: (format: Output_Format, name: string, source: *string, post: *Post, flags: Macro_Flag) -> bool, string {
   if !name.count return false, "";

   macro := table_find_pointer(all_macros, name);
   if !macro {
      print("ERROR: Unknown macro '%'\n", name);
      return false, "";
   }

   consume_whitespace(source);

   builder   : String_Builder; // @Leak
   arguments : [..]string; // @Leak

   capture := <<source;
   capture.count = 0;

   while source.count {
      ok, value, width := next(source);
      if !ok || value == #char ")" {
         str := trim(builder_to_string(*builder), " \t\n\r");
         if str.count array_add(*arguments, str);
         reset(*builder);
         source.data  -= width;
         source.count += width;
         break;
      }

      if value == #char "(" {
         ok, output := process_macro(format, source, post, flags);
         if !ok break;
         append(*builder, output);
         continue;
      }

      if value == #char "\\" {
         ok, next_value := next(source);
         if !ok break;

         // Argument
         if is_whitespace(next_value) {
            array_add(*arguments, trim_right(builder_to_string(*builder)));
            reset(*builder);
            continue;
         }

         // Escape sequence
         escape_ok, sequence := is_valid_escape(next_value);
         if escape_ok {
            append(*builder, sequence);
         }
         else {
            value := to_string(cast(u8)next_value);
            print("ERROR: Invalid escape sequence '\\%'\n", value);
            return false, "";
         }

         continue;
      }

      append(*builder, character_utf32_to_utf8(value)); // @Leak
   }

   if xx arguments.count != macro.arguments {
      print("ERROR: Macro '%' accepts % argument(s), instead given %!\n", macro.name, macro.arguments, arguments.count);
      return false, "";
   }

   if macro.kind == .Action {
      ok := macro.action(post, ..arguments);
      return ok, "";
   }

   if macro.kind == .Modify {
      ok    : bool = false;
      value : string = ---;

      if flags & .Pre_Pass {
         value = sprint("(% %)", name, join(..arguments, " \\ ")); // @Leak
         ok = true;
      }
      else {
         value, ok = macro.modify(post, ..arguments);
      }

      return ok, value;
   }

   if !(format & macro.formats) {
      print("ERROR: Macro '%' is not defined for %\n", macro.name, format);
      return false, "";
   }

   body := <<table_find_pointer(macro.contents, format);
   for 1..macro.arguments {
      rep := sprint("$%", it);
      body = replace(body, rep, arguments[it - 1]); // @Leak
   }

   return true, body;
}

Macro_Flag :: enum_flags {
   Pre_Pass;
   Secondary_Pass;
   Raw_Output;
};

process_macro :: (format: Output_Format, source: *string, post: *Post, flags: Macro_Flag) -> bool, string {
   consume_whitespace(source);

   macro_name := <<source;
   macro_name.count = 0;

   while source.count {
      ok, value, width := next(source);
      if !ok || !is_valid_identifier(value) {
         source.data  -= width;
         source.count += width;
         break;
      }

      macro_name.count += width;
   }

   ok     : bool   = ---;
   output : string = ---;

   if contains(macro_name, "macro") {
      formats: Output_Format;

      if contains(macro_name, "-") {
         parts := split(macro_name, "-"); // @Leak
         parts.data  += 1;
         parts.count -= 1;

         // @Todo(Judah): Split is weird and returns [""] when it didn't find any splits. 
         if parts.count <= 0 || parts[0] == "" {
            print("ERROR: Invalid macro definition '%'", macro_name);
            return false, "";
         }

         for parts {
            if it == {
               case      "xml"; formats |= .Xml;
               case     "text"; formats |= .Text;
               case     "html"; formats |= .Html;
               case "markdown"; formats |= .Markdown;
               case;
                  print("ERROR: Macro '%' has an unknown format: '%'", macro_name, it);
                  return false, "";
            }
         }
      }
      else {
         formats = Output_Format.Html | .Markdown | .Text | .Xml;
      }

      ok = process_macro_definition(formats, source, post);
   }
   else {
      ok, output = process_macro_invocation(format, macro_name, source, post, flags);
   }

   if !(flags & .Raw_Output) && !ok {
      return false, "";
   }

   {
      ok, chr := next(source);
      if !ok || chr != #char ")" {
         invalid_character := character_utf32_to_utf8(chr); // @Leak
         log("Expected ')' but found '%'\n", invalid_character, flags = .ERROR);
         return false, "";
      }
   }

   return true, output;
}

process_file :: (format: Output_Format, source: *string, post: *Post) -> bool {
   file: String_Builder; // @Leak

   while source.count {
      ok, chr := next(source);
      if !ok return false;

      // Line comments
      if chr == #char "\\" {
         ok, chr = peek(source);
         if !ok return false;

         if chr == #char "." {
            while source.count {
               ok, chr = next(source);
               if !ok || chr == #char "\n" break;
            }
         }

         continue;
      }

      if chr == #char "(" {
         ok, output := process_macro(format, source, post, .Pre_Pass);
         if !ok return false;

         if output.count {
            replaced: String_Builder; // @Leak
            output_copy := output;

            // Do a non-macro filling pass over the processed output.
            while output_copy.count {
               ok, chr := next(*output_copy);
               if !ok break;

               if chr == #char "(" {
                  ok, output = process_macro(format, *output_copy, post, .Secondary_Pass);
                  if !ok return false;
                  append(*replaced, output);
               }
               else {
                  append(*replaced, character_utf32_to_utf8(chr)); // @Leak
               }
            }

            output = builder_to_string(*replaced);

            // Replace any special sequences
            output = replace(output, ESCAPE_TAB, "\t"); // @Leak
            output = replace(output, ESCAPE_SPACE, " "); // @Leak
            output = replace(output, ESCAPE_NEWLINE, "\n"); // @Leak
            output = replace(output, ESCAPE_OPEN_PAREN, "("); // @Leak
            output = replace(output, ESCAPE_CLOSE_PAREN, ")"); // @Leak

            append(*file, output);
         }

         consume_whitespace(source);
         continue;
      }

      append(*file, character_utf32_to_utf8(chr)); // @Leak
   }

   if post table_set(*post.contents, format, trim_left(builder_to_string(*file), "\r\n"));
   return true;
}

find_macro :: (name: string) -> ok: bool, *Macro {
   macro := table_find_pointer(all_macros, name);
   if !macro return false, null;
   return true, macro;
}

Format_And_Path :: struct {
   format : Output_Format;
   path   : File_Path;
};

all_macros            : Table(string, Macro); // @Leak
all_posts             : [..]Post; // @Leak
all_doc_files         : [..]File_Path; // @Leak
all_template_files    : [..]Format_And_Path; // @Leak
format_specific_files : [..]Format_And_Path;
custom_macro_files    : [..]File_Path; // @Leak

root_directory   : Directory;
page_directory   : Directory;
output_directory : Directory;

formats_to_output : Output_Format;

process_default_macros := true;
show_parsed_macros     := false;

main :: () {
   arguments := get_command_line_arguments(); // @Leak
   arguments.data  += 1;
   arguments.count -= 1;

   print_help :: (error_string := "") {
      print(HELP, PROJECT_NAME, PROJECT_VERSION, PROJECT_COMPILATION_DATE, join("ERROR: ", error_string)); // @Leak
   }

   for arg, i: arguments {
      if arg == {
         case    "-h"; #through;
         case "-help";
            print_help();
            return;

         case       "-v"; #through;
         case "-version";
            print("% v%\n", PROJECT_NAME, PROJECT_VERSION);
            return;

         case         "-d"; #through;
         case "-directory";
            if i + 1 >= arguments.count {
               print("ERROR: Flag '%' expects an argument!\n", arg);
               return;
            }

            i += 1;
            directory := arguments[i];
            root_directory = xx directory;

         case "-show-macros";
            show_parsed_macros = true;

         case "-no-default-macros";
            process_default_macros = false;

         // @Note(Judah): Collect all macro files in an array then bulk process
         // them. This allows the user to just overwrite default macros they
         // want rather than having to replace all of them.
         case      "-m"; #through;
         case "-macros";
            if i + 1 >= arguments.count {
               print("ERROR: Flag '%' expects an argument!\n", arg);
               return;
            }

            i += 1;
            macro_file := arguments[i];
            array_add(*custom_macro_files, cast(File_Path)macro_file);

         case;
            lower := arg;
            to_lower(lower);

            if lower == {
               case "html";
                  formats_to_output |= .Html;

               case "xml";
                  formats_to_output |= .Xml;

               case  "txt"; #through;
               case "text";
                  formats_to_output |= .Text;

               case       "md"; #through;
               case "markdown";
                  formats_to_output |= .Markdown;

               case;
                  print("Unknown format or flag '%'\n", arg);
                  return;
            }
      }
   }

   // If format flags weren't passed through, set the default format to HTML.
   if !formats_to_output {
      formats_to_output = .Html;
   }

   // If a generation directory wasn't passed through, set it to the current one.
   if !root_directory.count {
      root_directory = xx get_working_directory(); // @Leak?
   }

   // Verify important directories exist
   verify_directory_exists_or_exit :: (dir: Directory) #expand {
      if !directory_exists(dir) {
         print_help(sprint("Expected directory '%' to exist!", dir));
         `return;
      }
   }

   #if OS == .WINDOWS {
      root_directory = xx replace(root_directory, "\\", "/"); // @Leak
   }

   // @Leak
   page_directory   = xx join(root_directory, "_pages", separator = "/");
   page_directory   = xx replace(page_directory, "//", "/"); // @Temp: Just something to clean up paths
   output_directory = xx join(root_directory, "output", separator = "/");
   output_directory = xx replace(output_directory, "//", "/"); // @Temp: Same as above

   verify_directory_exists_or_exit(page_directory);
   make_directory_if_it_does_not_exist(output_directory);

   new_macro :: (name: string, kind: Macro.Kind, arguments: u64) -> *Macro {
      macro := table_add(*all_macros, name, .{});
      macro.name      = name;
      macro.kind      = kind;
      macro.arguments = arguments;
      return macro;
   }

   // Register built-in macros
   {
      macro := new_macro("meta-title", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         post.title = args[0];
         title := post.title;

         sanitized: String_Builder; // @Leak
         for 0..title.count - 1 {
            chr := title[it];

            if (chr >= #char "a" && chr <= #char "z") ||
               (chr >= #char "A" && chr <= #char "Z") ||
               (chr >= #char "0" && chr <= #char "9") ||
               (chr == #char "-" || chr == #char "_")
            {
               append(*sanitized, to_lower(chr));
            }
            else if chr == #char " "  ||
                    chr == #char "\t" ||
                    chr == #char "\n"
            {
               append(*sanitized, #char "-");
            }
         }

         post.url = builder_to_string(*sanitized);
         return true;
      };
   }
   {
      macro := new_macro("meta-url", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         if !post return false;
         post.url = args[0];
         return true;
      };
   }
   {
      macro := new_macro("meta-introduction", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         if !post return false;
         post.introduction = args[0];
         return true;
      };
   }
   {
      macro := new_macro("meta-published", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         date, ok := parse_date(args[0]);
         if !ok {
            print("Unable to set publishing date for post!\n");
            return false;
         }

         post.published = date;
         return true;
      };
   }
   {
      macro := new_macro("meta-updated", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         date, ok := parse_date(args[0]);
         if !ok {
            print("Unable to set update date for post!\n");
            return false;
         }

         post.updated = date;
         return true;
      };
   }
   {
      macro := new_macro("meta-author", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         author := args[0];
         post.author = author;
         return true;
      };
   }
   {
      macro := new_macro("meta-tags", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         if post.tags.count return true; // Early exit if we've already done this

         tags := split(args[0], " ");
         for tags {
            tags[it_index] = trim(it);
            to_lower(it);
            array_add(*post.tags, it);
         }

         return true;
      };
   }
   {
      macro := new_macro("meta-kind", .Action, 1);
      macro.action = (post: *Post, args: ..string) -> bool {
         kind := trim(args[0]);
         to_lower(kind);

         if kind == {
            case "post";
               post.kind = .Post;
            case "page";
               post.kind = .Page;
            case;
               print("Unknown post kind %\n", args[0]);
               return false;
         }

         return true;
      };
   }
   {
      macro := new_macro("edit-repeat", .Modify, 2);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         raw_amount := args[0];
         amount     := parse_int(*raw_amount);
         value      := args[1];

         builder: String_Builder;
         for 0..amount - 1 append(*builder, value);
         return builder_to_string(*builder), true;
      };
   }
   {
      macro := new_macro("edit-modify", .Modify, 2);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         kind  := args[0];
         value := args[1];

         if kind == {
            case "titlecase";
               return to_titlecase(value), true; // @Leak

            case "lowercase";
               to_lower(value);
               return value, true;

            case "uppercase";
               to_upper(value);
               return value, true;

            // @Todo(Judah): Not shite justification
            case "justify";
               max_length :: 58;
               builder: String_Builder; // @Leak

               words: [..]string; // @Leak

               lines       := split(value, "\n"); // @Leak
               skipped     := 0;
               line_length := 0;

               for line: lines {
                  line_words := split(line, " "); // @Leak
                  for line_words if it.count array_add(*words, trim(it, " \t\n\r"));
               }

               current_line: [..]string; // @Leak, @Temp(Judah): Not necessary

               for 0..words.count - 1 {
                  word := words[it];

                  if line_length + word.count >= max_length {
                     spaces_needed := max_length - line_length;

                     for w: current_line {
                        append(*builder, w);

                        if it_index < current_line.count - 1 {
                           append(*builder, #char " ");
                        }

                        if spaces_needed > 0 {
                           append(*builder, #char " ");
                           spaces_needed -= 1;
                        }
                     }

                     append(*builder, #char "\n");

                     line_length = 0;
                     array_reset(*current_line);
                  }

                  line_length += word.count + 1;
                  array_add(*current_line, word);
               }

               if current_line.count {
                  spaces_needed := max_length - line_length;

                  for w: current_line {
                     append(*builder, w);
                     if it_index < current_line.count - 1 {
                        append(*builder, #char " ");
                     }
                  }
               }

               return builder_to_string(*builder), true; // @Leak

            case "dedent";
               splits := split(value, "\n"); // @Leak
               for splits splits[it_index] = trim(it, " \t\n\r");
               return join(..splits, "\n"), true; // @Leak
         }

         print("ERROR: Invalid conversion kind for edit-modify: %\n", kind);
         return "", false;
      };
   }
   {
      macro := new_macro("insert-file", .Modify, 1);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         filename  := args[0];
         file_path := join(page_directory, filename, separator = "/");

         contents, ok := read_entire_file(file_path); // @Leak
         if !ok {
            print("ERROR: Unable to insert file: %\n", file_path);
            return "", false;
         }

         return contents, true;
      };
   }
   {
      macro := new_macro("insert-field", .Modify, 1);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         if !post return "", false;

         field_name := args[0];
         if field_name == {
            case "meta-title";
               return post.title, true;

            case "meta-published";
               return to_string(post.published), true;

            case "meta-introduction";
               return post.introduction, true;

            case "meta-updated";
               return to_string(post.updated), true;

            case "meta-author";
               return post.author, true;
         }

         print("ERROR: Invalid field given to insert-field: '%'\n", field_name); // @Errors
         return "", false;
      };
   }
   {
      macro := new_macro("insert-content", .Modify, 0);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         content, found := table_find(post.contents, post.current_format);
         if !found return "", false;
         return content, true;
      };
   }
   {
      macro := new_macro("insert-posts", .Modify, 1);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (_: *Post, args: ..string) -> string, bool {
         builder: String_Builder;

         for post: all_posts if post.kind == .Post {
            format_string := args[0];

            while format_string.count {
               ok, token := next(*format_string);
               if !ok break;

               if token == #char "$" {
                  specifier := format_string;
                  specifier.count = 0;

                  ok    : bool = ---;
                  token : rune = ---;
                  width : s64  = ---;
                  while format_string.count {
                     ok, token, width = next(*format_string);
                     if !ok || !is_alpha(token) break;
                     specifier.count += width;
                  }

                  if specifier == {
                     case "url";
                        append(*builder, post.url);
                     case "title";
                        append(*builder, post.title);
                     case "introduction";
                        append(*builder, post.introduction);
                     case "tags";
                        append(*builder, join(..post.tags, " ")); // @Leak
                     case "updated";
                        append(*builder, to_string(post.updated));
                     case "published";
                        append(*builder, to_string(post.published));
                     case;
                        print("WARN: Unknown specifier in format string: '$%'\n", specifier); // @Logging
                        continue;
                  }

                  append(*builder, character_utf32_to_utf8(token));
                  continue;
               }

               append(*builder, character_utf32_to_utf8(token));
            }
         }

         return builder_to_string(*builder), true;
      };
   }
   {
      macro := new_macro("insert-tags", .Modify, 1);
      macro.formats = Output_Format.Html | .Markdown | .Text | .Xml;
      macro.modify  = (post: *Post, args: ..string) -> string, bool {
         builder: String_Builder;

         for post.tags {
            format_string := args[0];

            while format_string.count {
               ok, token := next(*format_string);
               if !ok break;

               if token == #char "$" {
                  specifier := format_string;
                  specifier.count = 0;

                  ok    : bool = ---;
                  token : rune = ---;
                  width : s64  = ---;
                  while format_string.count {
                     ok, token, width = next(*format_string);
                     if !ok || !is_alpha(token) break;
                     specifier.count += width;
                  }

                  if specifier == {
                     case "tag";
                        append(*builder, it);
                     case;
                        print("WARN: Unknown specifier in format string: '$%'\n", specifier); // @Logging
                        continue;
                  }

                  append(*builder, character_utf32_to_utf8(token));
                  continue;
               }

               append(*builder, character_utf32_to_utf8(token));
            }
         }

         return builder_to_string(*builder), true;
      };
   }

   // Process the default macro file (if allowed)
   if process_default_macros {
      default_macro_file := DEFAULT_MACROS;
      process_file(0, *default_macro_file, null);
   }

   // Process custom macro files (if any)
   for macro_file: custom_macro_files {
      file, ok := read_entire_file(macro_file);
      if !ok {
         print("ERROR: Unable to open macro file '%'! Does it exist?\n", macro_file); // @Errors
         return;
      }

      ok = process_file(0, *file, null);
      if !ok {
         print("ERROR: Unable to process macro file '%'\n", macro_file); // @Errors
         return;
      }
   }

   // Print parsed macros
   if show_parsed_macros {
      Temp :: struct {
         name   : string;
         output : string;
      };

      parsed: [..]Temp;

      for macro: all_macros {
         builder: String_Builder; // @Leak

         p := array_add(*parsed);
         p.name = macro.name;

         for body, format: macro.contents {
            name := sprint("%", format);
            append(*builder, "    ");
            for 0..(8 - name.count) append(*builder, " ");
            print_to_builder(*builder, "% :: %\n", format, body);
         }

         p.output = builder_to_string(*builder);
      }

      insertion_sort(parsed, (l: Temp, r: Temp) -> int {
         if l.name[0] > r.name[0] return 1;
         if l.name[0] < r.name[0] return -1;
         return 0;
      });

      for parsed {
         print("- %\n%", it.name, it.output);
      }

      return;
   }

   all_files      := file_list(page_directory, false, false); // @Leak
   output_formats := enum_flags_set(formats_to_output);

   for path: all_files {
      filename  := path_filename(path);
      extension := path_extension(filename);


      // If the file is a special templating one
      if starts_with(filename, "post")  ||
         starts_with(filename, "page")  ||
         starts_with(filename, "index")
      {
         format: Output_Format;

         if extension == {
            case "xml";
               format = .Xml;

            case "html";
               format = .Html;

            case       "md"; #through;
            case "markdown";
               format = .Markdown;

            case  "txt"; #through;
            case "text"; 
               format = .Text;

            case;
               continue path;
         }

         template := array_add(*all_template_files);
         template.path   = xx path;
         template.format = format;
      }
      // If the file is a post
      else if extension ==  "doc" ||
              extension == "post"
      {
         array_add(*all_doc_files, xx path);
      }
      // Otherwise the file is one we should process and push (if the correct format)
      else {
         for output_formats {
            should_be_included := false;

            if it == {
               case .Html;
                  should_be_included = (extension == "html");
               case .Markdown;
                  should_be_included = (extension == "md"  || extension == "markdown");
               case .Text;
                  should_be_included = (extension == "txt" || extension == "text");
               case .Xml;
                  should_be_included = (extension == "xml");
            }

            if should_be_included {
               f := array_add(*format_specific_files);
               f.path   = xx path;
               f.format = it;
               break;
            }
         }
      }
   }

   time_start      := get_time();
   pages_generated := 0;

   // Generate posts by processing document files
   for doc_file: all_doc_files {
      contents, ok := read_entire_file(doc_file); // @Leak
      if !ok {
         print("Unable to open file: %\n", doc_file); // @Errors
         continue;
      }

      post := array_add(*all_posts);

      for format: output_formats {
         if format == .Xml continue; // Skip page creation for XML

         contents_copy := contents;

         ok = process_file(format, *contents_copy, post);
         if !ok {
            print("ERROR: Unable to process file: % (%)\n", doc_file, format); // @Errors
            array_ordered_remove_by_index(*all_posts, all_posts.count - 1);
            continue doc_file;
         }
      }

      // @Todo(Judah): meta-published + meta-title should probably be required fields.

      // If the user hasn't set any date fields
      if post.published.day <= 0 then post.published = get_system_date();
      if post.updated  .day <= 0 then post.updated   = get_system_date();

      print(
         "Generated file: % => '%' (%) [%]\n",
         path_filename(doc_file),
         post.title,
         post.url,
         formats_to_output
      ); // @Logging

      pages_generated += 1;
   }

   // Sort posts by date
   insertion_sort(all_posts, (l: Post, r: Post) -> int {
       if l.published > r.published return -1;
       if l.published < r.published return  1;
       return 0;
   });

   page_table: Table(File_Path, string); // @Leak

   for template: all_template_files if (template.format & formats_to_output) {
      template_file := table_find_pointer(page_table, template.path);
      if !template_file {
         contents, ok := read_entire_file(template.path);
         if !ok {
            print("ERROR: Unable to open template file: %\n", template);
            continue;
         }

         template_file = table_set(*page_table, template.path, contents);
      }

      // Generate each final post file
      filename := path_filename(template.path);

      fmt := sprint("%", template.format); to_lower(fmt);
      format_directory := join(output_directory, fmt, separator = "/");

      make_directory_if_it_does_not_exist(format_directory);

      if contains(filename, "post") ||
         contains(filename, "page")
      {
         filter_kind := Post.Kind.Post;

         // Temp
         if contains(filename, "page") {
            filter_kind = .Page;
         }

         for * post: all_posts if post.kind == filter_kind {
            builder: String_Builder; // @Leak
            template_copy := <<template_file;
            post.current_format = template.format;

            while template_copy.count {
               ok, token := next(*template_copy);
               if !ok break;

               if token == #char "$" {
                  ok, next_token := next(*template_copy);
                  if !ok break;

                  if next_token == #char "(" {
                     ok, output := process_macro(template.format, *template_copy, post, .Raw_Output);
                     if !ok {
                        print("ERROR: Unable to process file: %\n", filename);
                        break;
                     }

                     append(*builder, output);
                  }
                  else {
                     append(*builder, character_utf32_to_utf8(next_token)); // @Leak
                  }

                  continue;
               }

               append(*builder, character_utf32_to_utf8(token)); // @Leak
            }

            extension: string = ---;
            if post.current_format == {
               case .Html    ; extension = ".html";
               case .Markdown; extension = ".md";
               case .Text    ; extension = ".txt";
               case .Xml     ; extension = ".xml";
            }

            if template.format == .Html {
               directory := join(format_directory, post.url, separator = "/");
               ok := make_directory_if_it_does_not_exist(directory);
               if !ok {
                  print("ERROR: Unable to make directory for post '%' (%)!\n", post.title, post.url);
                  continue post;
               }

               filename := join(directory, "index.html", separator = "/");
               ok = write_entire_file(filename, builder_to_string(*builder));
               if !ok {
                  print("ERROR: Unable to create file for post '%' (%)!\n", post.title, post.url);
                  continue post;
               }
            }
            else {
               filename := sprint("%/%+%", format_directory, post.url, extension);
               ok := write_entire_file(filename, builder_to_string(*builder));
               if !ok {
                  print("ERROR: Unable to create file for post '%' (%)!\n", post.title, post.url);
                  continue post;
               }
            }
         }
      }
      else if contains(filename, "index") {
         builder: String_Builder;
         filename      := join(format_directory, sprint("index.%", fmt), separator = "/"); // @Leak
         template_copy := <<template_file;

         while template_copy.count {
            ok, token := next(*template_copy);
            if !ok break;

            if token == #char "$" {
               ok, next_token, width := next(*template_copy);
               if !ok break;

               if next_token == #char "(" {
                  ok, output := process_macro(template.format, *template_copy, null, .Raw_Output);
                  if !ok {
                     print("ERROR: Unable to process file: %\n", filename);
                     break;
                  }

                  append(*builder, output);
               }
               else {
                  append(*builder, character_utf32_to_utf8(token)); // @Leak
               }

               continue;
            }

            append(*builder, character_utf32_to_utf8(token)); // @Leak
         }

         ok := make_directory_if_it_does_not_exist(format_directory);
         if !ok {
            print("ERROR: Unable to create directory for post: %\n", format_directory);
            continue;
         }

         ok = write_entire_file(filename, builder_to_string(*builder));
         if !ok {
            print("ERROR: Unable to create file for post: %\n", filename);
            continue;
         }
      }

      pages_generated += 1;
   }

   // Process and push any 'pass-through' files
   for page: format_specific_files {
      builder: String_Builder;

      filename := path_strip_extension(path_filename(page.path));
      fmt := sprint("%", page.format); to_lower(fmt);
      format_directory := join(output_directory, fmt, separator = "/");

      output_path: string = ---;
      if page.format == .Html {
         output_path = join(format_directory, filename, "index.html", separator = "/");

         new_folder_for_file := path_strip_filename(output_path);
         ok := make_directory_if_it_does_not_exist(new_folder_for_file);
         if !ok {
            print("ERROR: Unable to create directory for file: %\n", new_folder_for_file);
            continue;
         }
      }
      else {
         output_path = join(format_directory, sprint("%.%", filename, fmt), separator = "/");
      }

      contents, ok := read_entire_file(page.path);
      if !ok {
         print("ERROR: Unable to open file: %\n", page.path);
         continue;
      }

      while contents.count {
         ok, token := next(*contents);
         if !ok break;

         if token == #char "$" {
            ok, next_token, width := next(*contents);
            if !ok break;

            if next_token == #char "(" {
               ok, output := process_macro(page.format, *contents, null, .Raw_Output);
               if !ok {
                  print("ERROR: Unable to process file: %.%\n", filename, fmt);
                  break;
               }

               append(*builder, output);
            }
            else {
               append(*builder, character_utf32_to_utf8(token)); // @Leak
            }

            continue;
         }

         append(*builder, character_utf32_to_utf8(token)); // @Leak
      }

      ok = write_entire_file(output_path, builder_to_string(*builder));
      if !ok {
         print("ERROR: Unable to create file for post: %\n", output_path);
         continue;
      }

      print("Processed file: %.%\n", filename, fmt);
      pages_generated += 1;
   }

   time_end := get_time();

   print(
      ">> Generated % page% after %s\n",
      pages_generated,
      ifx pages_generated == 1 then "" else "s",
      time_end - time_start,
   ); // @Logging
}

DEFAULT_MACROS :: #string XXX
(macro          p \($1\)) \. Surrounds the argument in (parentheses)
(macro          / (p $1)) \. Useful for code blocks: func_call(/ x, y)
(macro      break \n)
(macro-html break \n<br/>\n)

(macro   dedent (edit-modify dedent \ $1))
(macro  justify (edit-modify justify \ $1))
(macro to-title (edit-modify titlecase \ $1))
(macro to-upper (edit-modify uppercase \ $1))
(macro to-lower (edit-modify lowercase \ $1))

\. HTML macros
(macro-html         q <q>$1</q>)
(macro-html      bold <strong>$1</strong>)
(macro-html      code <pre class="lang-$1">\n$2\n</pre>)
(macro-html      link <a href="$1">$2</a>)
(macro-html     image <img src="$1">$2</img>)
(macro-html    italic <em>$1</em>)
(macro-html monospace <code>$1</code>)
(macro-html underline <u>$1</u>)
(macro-html paragraph \n<p>$1</p>\n)

(macro-html        flow \n<p style="text-align:justify;">$1</p>)
(macro-html  flow-large (flow (edit-repeat 8 \ &nbsp;)$1))
(macro-html flow-medium (flow (edit-repeat 4 \ &nbsp;)$1))
(macro-html  flow-small (flow (edit-repeat 2 \ &nbsp;)$1))

\. Markdown macros
(macro-markdown      bold **$1**)
(macro-markdown      code (break)```$1\n$2```(break))
(macro-markdown      link [$1]\($2\))
(macro-markdown     image [$1]\($2\))
(macro-markdown    italic *$1*)
(macro-markdown monospace `$1`)
(macro-markdown underline __$1__)
(macro-markdown paragraph (break)$1(break))

(macro-markdown        flow (break)$1)
(macro-markdown  flow-large (flow $1))
(macro-markdown flow-medium (flow $1))
(macro-markdown  flow-small (flow $1))

\. Text macros
(macro-text      bold $1)
(macro-text      code (break)(break)$2(break)(break))
(macro-text      link $2 [$1])
(macro-text     image $2 \($1\))
(macro-text    italic $1)
(macro-text monospace [ $1 ])
(macro-text underline _$1_)
(macro-text paragraph (break)$1(break))

\. @Todo(Judah): Replace these dumbass dots when whitespace is fixed
(macro-text        flow (break)(justify $1))
(macro-text  flow-large (flow (edit-repeat 8 \ \s)$1))
(macro-text flow-medium (flow (edit-repeat 4 \ \s)$1))
(macro-text  flow-small (flow (edit-repeat 2 \ \s)$1))

\. Standard macros (way more verbose than necessary for now)
(macro-text-markdown q "$1")

(macro-html     bold-italic (bold (italic $1)))
(macro-text     bold-italic (bold (italic $1)))
(macro-markdown bold-italic (bold (italic $1)))

(macro-html     italic-bold (italic (bold $1)))
(macro-text     italic-bold (italic (bold $1)))
(macro-markdown italic-bold (italic (bold $1)))

(macro-html     code-c (code c \ $1))
(macro-text     code-c (code c \ $1))
(macro-markdown code-c (code c \ $1))

(macro-html     code-go (code go \ $1))
(macro-text     code-go (code go \ $1))
(macro-markdown code-go (code go \ $1))

(macro-html     code-jai (code jai \ $1))
(macro-text     code-jai (code jai \ $1))
(macro-markdown code-jai (code jai \ $1))

(macro-html     code-cpp (code cpp  \ $1))
(macro-text     code-cpp (code cpp  \ $1))
(macro-markdown code-cpp (code cpp  \ $1))
XXX;

#placeholder PROJECT_NAME;
#placeholder PROJECT_VERSION;
#placeholder PROJECT_COMPILATION_DATE;

HELP :: #string XXX
%1 version %2 (compiled on %3)

%4

Usage
    %1 <flags> [formats (default: html)]

Formats
    xml
    html
    markdown, md
    text, txt

Flags
    -no-default-macros Disables all default macros
    -show-macros       Show parsed macros and exit
    -m, -macros        Parses a given macro file
    -d, -directory     Sets the directory to generate from
    -h, -help          Shows this message
    -v, -version       Shows the current version
XXX;

#load "util.jai";

#import "File";
#import "Basic";
#import "String";
#import "Unicode";
#import "IntroSort";
#import "Hash_Table"; 
#import "File_Utilities";