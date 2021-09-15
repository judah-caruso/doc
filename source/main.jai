#placeholder NAME;
#placeholder VERSION;

Document :: struct {
    formats: Document.Output_Format;
    current_format: Document.Output_Format;

    dir_root     : string;
    dir_pages    : string;
    dir_output   : string;
    dir_includes : string;

    dir_html      : string;
    dir_markdown  : string;
    dir_plaintext : string;

    post_files: [..]string;
    page_files: [..]string;

    posts: [..]Post;

    current_post     : *Post;
    current_output   : String_Builder;
    current_contents : string;

    Output_Format :: enum_flags {
        Html;
        Markdown;
        Plaintext;
    }
}

Attribute :: enum {
    Invalid;

    // Meta tags
    Meta;
    Title;
    Url;
    Date;
    Kind;
    Edited;

    // Sections
    Dash;
    Break;
    Separator;
    Header;
    Paragraph;
    Code;
    Link;
    Text;
    Quote;

    // Formatting
    Bold;
    Italic;
    Underline;
    Monospace;

    // Sizes
    Small;
    Medium;
    Large;

    // Languages
    C;
    Go;
    Lua;
    Jai;
    Python;
    JavaScript;

    // Formats
    Format;
    Html;
    Markdown;
    Plaintext;
}

to_attribute :: (str: string) -> Attribute {
    if str == {
        case "meta"      ; return .Meta;
        case "title"     ; return .Title;
        case "url"       ; return .Url;
        case "date"      ; return .Date;
        case "kind"      ; return .Kind;
        case "edited"    ; return .Edited;
        
        case "dash"      ; return .Dash;
        case "break"     ; return .Break;
        case "separator" ; return .Separator;
        case "header"    ; return .Header;
        case "paragraph" ; return .Paragraph;
        case "link"      ; return .Link;
        case "code"      ; return .Code;
        case "text"      ; return .Text;
        case "quote"     ; return .Quote;
        
        case "bold"      ; return .Bold;
        case "italic"    ; return .Italic;
        case "underline" ; return .Underline;
        case "monospace" ; return .Monospace;

        case "small"     ; return .Small;
        case "medium"    ; return .Medium;
        case "large"     ; return .Large;

        case "c"          ; return .C;
        case "go"         ; return .Go;
        case "lua"        ; return .Lua;
        case "jai"        ; return .Jai;
        case "python"     ; return .Python;
        case "javascript" ; return .JavaScript;

        case "format"    ; return .Format;
        case "html"      ; return .Html;
        case "markdown"  ; return .Markdown;
        case "plaintext" ; return .Plaintext;
    }

    return .Invalid;
}

Post :: struct {
    filename    : string;
    output_file : string;
    url         : string;

    date     : Date;
    edited   : Date;
    kinds    : [..]string;
    title    : string;

    contents : Table(Document.Output_Format, string);
}

process_tag :: (document: *Document) -> (string, bool) {
    capture := document.current_contents;
    capture.count = 0;

    while has_token(document.current_contents) {
        token, ok, len := next(*document.current_contents);
        if !ok return "", false;
        if token == #char "{" break;
        capture.count += len;
    }

    tags: [..]Attribute;

    string_attrs := split(capture, "-");
    for 0..string_attrs.count - 1 {
        attr := trim(string_attrs[it]);

        tag := to_attribute(attr);
        if tag == .Invalid {
            print("Invalid tag: '%'\n", attr);
            return "", false;
        }

        array_add(*tags, tag);
    }

    str, ok := process_content(document, tags);
    return str, ok;
}

process_content :: (document: *Document, tags: [..]Attribute) -> (string, bool) { 
    content_builder: String_Builder;

    while has_token(document.current_contents) {
        token, ok := next(*document.current_contents);
        if !ok return "", false;

        if token == { 
            case #char "\\";
                next_token, ok := peek(*document.current_contents);
                if !ok return "", false;

                if next_token == {
                    case #char "\\";
                        next(*document.current_contents);
                    case #char "{";
                        append(*content_builder, #char "{");
                        next(*document.current_contents);
                        continue;
                    case #char "}";
                        append(*content_builder, #char "}");
                        next(*document.current_contents);
                        continue;

                    case;
                        str, ok := process_tag(document);
                        if !ok return "", false;
                        append(*content_builder, str);
                        continue;
                }

            case #char "}";
                break;
        }

        append(*content_builder, character_utf32_to_utf8(token));
    }

    content := builder_to_string(*content_builder);
    content = trim(content);

    if tags[0] != .Code {
        splits := split(content, "\n");
        for 0..splits.count - 1 {
            splits[it] = trim_left(splits[it]);
        }

        content = join(..splits, "\n");
    }

    if tags[0] == .Meta {
        assert(tags.count > 1);

        kind := tags[1];
        if kind == {
            case .Title;
                document.current_post.title = content;

            case .Url;
                document.current_post.url = content;

            case .Date; #through;
            case .Edited; 
                date: Date;
                parts := split(content, "/");
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

                if !parse_fail {
                    if kind == .Edited {
                        document.current_post.edited = date;
                    }
                    else {
                        document.current_post.date = date;
                    }
                }
                else {
                    print("Invalid date string: %\n", content);
                }

            case .Kind;
                kinds := split(content, " ");
                for kinds array_add(*document.current_post.kinds, trim(it));
                
            case;
                print("Invalid meta tag: %\n", kind);
                return "", false;
        }

        return "", true;
    }

    prefix: [..]string;
    suffix: [..]string;

    push_pair :: (begin: string, end: string) #expand {
        array_add(*`prefix, begin);
        array_insert_at(*`suffix, end, 0);
    }

    size := Attribute.Large;
    for tag: tags {
        if tag == {
            case .Small  ; #through;
            case .Medium ; #through;
            case .Large  ;
                size = tag;
                array_ordered_remove_by_index(*tags, it_index);
                break;
        }
    }

    for tag: tags {
        if tag == {
            case .Paragraph;
                if document.current_format == {
                    case .Html; push_pair("<p>", "</p>");
                }

            case .Text;
                if document.current_format == {
                    case .Html      ; push_pair("<span>", "</span>");

                    case .Markdown  ; #through;
                    case .Plaintext ; push_pair("\n", "\n");
                }

            case .Quote;
                if document.current_format == {
                    case .Html      ; push_pair("<q>", "</q>");
                    case .Markdown  ; push_pair("&ldquo;", "&rdquo;");
                    case .Plaintext ; push_pair("\"", "\"");
                }

            case .Italic;
                if document.current_format == {
                    case .Html     ; push_pair("<em>", "</em>");
                    case .Markdown ; push_pair("*", "*");
                }

            case .Bold;
                if document.current_format == {
                    case .Html     ; push_pair("<strong>", "</strong>");
                    case .Markdown ; push_pair("**", "**");
                }

            case .Underline;
                if document.current_format == {
                    case .Html     ; push_pair("<span style='text-decoration: underline'>", "</span>");
                    case .Markdown ; push_pair("_", "_");
                }

            case .Monospace;
                if document.current_format == {
                    case .Html     ; push_pair("<code>", "</code>");
                    case .Markdown ; push_pair("`", "`");
                }

            case .Link;
                url := split(content, " ")[0];
                content = replace(content, url, "");
                content = trim(content);

                if document.current_format == {
                    case .Html;
                        push_pair(sprint("<a href='%'>", url), "</a>");

                    case .Markdown;
                        push_pair(sprint("[%](", content), ")");
                        content = url;
                }

            case .Code;
                language: string;

                for tags {
                    if it == {
                        case .C          ; language = "c"      ; break;
                        case .Go         ; language = "go"     ; break;
                        case .Lua        ; language = "lua"    ; break;
                        case .Python     ; language = "python" ; break;
                        case .JavaScript ; language = "js"     ; break;
                    }
                }

                if document.current_format == {
                    case .Html;
                        begin := "<pre>";
                        if language.count begin = sprint("<pre class='block lang-%'>", language);
                        push_pair(begin, "</pre>");

                    case .Markdown;
                        begin := "```";
                        if language.count begin = sprint("```%", language);
                        push_pair(begin, "```");
                }

            case .Separator;
                if document.current_format == {
                    case .Html;
                        array_add(*prefix, "<hr />");

                    case .Markdown  ; #through;
                    case .Plaintext ;
                        array_add(*prefix, "---");
                }

            case .Break;
                if document.current_format == {
                    case .Html;
                        array_add(*prefix, "<br />");

                    case .Markdown  ; #through;
                    case .Plaintext ;
                        array_add(*prefix, "\n");
                }

            case .Dash;
                if size == {
                    case .Small;
                        array_add(*prefix, "-");
                    case .Medium;
                        array_add(*prefix, "&ndash;");
                    case .Large;
                        array_add(*prefix, "&mdash;");
                }

            case .Header;
                if document.current_format == {
                    case .Html;
                        if size == {
                            case .Small  ; push_pair("<h3>", "</h3>");
                            case .Medium ; push_pair("<h2>", "</h2>");
                            case .Large  ; push_pair("<h1>", "</h1>");
                        }

                    case .Markdown;
                        begin: string = ---;
                        if size == {
                            case .Small  ; begin = "### ";
                            case .Medium ; begin = "## ";
                            case .Large  ; begin = "# ";
                        }

                        push_pair(begin, "\n");
                }

            case .Html      ; #through;
            case .Markdown  ; #through;
            case .Plaintext ;
                gross_a := tprint("%", document.current_format);
                gross_b := tprint("%", tag);

                if gross_a == gross_b {
                    return sprint("%", content), true;
                }

                return "", true;

            case .Format;
                continue;

            case;
                if !(tag >= .C && tag <= .JavaScript) && !(tag >= .Small && tag <= .Large) {
                    print("Unimplemented tag: %\n", tag);
                    return "", true;
                }
        }
    }

    return sprint(
        "%+%+%",
        join(..prefix, ""),
        content,
        join(..suffix, ""),
    ), true;
}

process_format_tags :: (document: Document, post: Post, format: Document.Output_Format, template: string, page_table: *Table(string, string)) -> string {
    modified_template := template;
    temp := template;

    while has_token(temp) {
        token, ok := next(*temp);
        if !ok break;

        if token == #char "\\" {
            tag := temp;
            tag.count = 0;

            while ok {
                token, ok = next(*temp);
                if !ok || token == #char "{" break;
                tag.count += 1;
            }

            value := temp;
            value.count = 0;

            while ok {
                token, ok := next(*temp);
                if !ok || token == #char "}" break;
                value.count += 1;
            }

            original_string := tag;
            original_string.data  -= 1;
            original_string.count += value.count + 3;

            if tag == {
                case "title";
                    modified_template = replace(modified_template, original_string, post.title);

                case "date";
                    if post.date.day {
                        modified_template = replace(modified_template, original_string, to_string(post.date, value));
                    }

                case "edited";
                    if post.edited.day {
                        modified_template = replace(modified_template, original_string, to_string(post.edited, value));
                    }
                    else {
                        modified_template = replace(modified_template, original_string, "");
                    }

                case "tags";
                    builder: String_Builder;

                    for kind: post.kinds {
                        format_string := value;

                        while has_token(format_string) {
                            token, ok := next(*format_string);
                            if !ok break;

                            if token == #char "%" {
                                next_token, ok := next(*format_string);
                                if !ok break;

                                if next_token == {
                                    case #char "k";
                                        append(*builder, kind);
                                }

                                continue;
                            }

                            append(*builder, character_utf32_to_utf8(token));
                        }

                        append(*builder, "\n");
                    }

                    modified_template = replace(modified_template, original_string, builder_to_string(*builder));

                case "posts";
                    builder: String_Builder;

                    for post: document.posts {
                        format_string := value;

                        while has_token(format_string) {
                            token, ok := next(*format_string);
                            if !ok break;

                            if token == #char "%" {
                                next_token, ok := next(*format_string);
                                if !ok break;

                                if next_token == {
                                    case #char "t";
                                        append(*builder, post.title);

                                    case #char "u";
                                        append(*builder, post.output_file);

                                    case #char "k";
                                        str := join(..post.kinds, " ");
                                        append(*builder, str);
                                }

                                continue;
                            }

                            append(*builder, character_utf32_to_utf8(token));
                        }

                        append(*builder, "\n");
                    }

                    modified_template = replace(modified_template, original_string, builder_to_string(*builder));

                case "include";
                    include, ok := table_find(<<page_table, value);

                    if !ok {
                        path := join(document.dir_includes, value);
                        contents, ok := read_entire_file(path);
                        if !ok {
                            print("Unable to include file: %\n", path);
                            continue;
                        }

                        table_set(page_table, value, contents);
                        include = contents;
                    }

                    modified_template = replace(modified_template, original_string, include);

                case "contents";
                    contents, found := table_find(post.contents, format);
                    if found modified_template = replace(modified_template, original_string, contents);
            }
        }
    }

    return modified_template;
}

generate_post :: (document: Document, post: Post, format: Document.Output_Format, template: string, output_path: string, page_table: *Table(string, string)) -> bool {
    modified_template := process_format_tags(document, post, format, template, page_table);
    ok := write_entire_file(output_path, modified_template);
    return ok;
}

root_directory: string = ---;
separator: string = ---;

print_help :: (exe_name: string, incorrect_flag := "") {
    error_string: string;
    if incorrect_flag.count {
        error_string = sprint("\nError: unknown flag '%'\n", incorrect_flag);
    }

    print(#string END
%1 (v%2, %3)
%4
Usage
    %1 <flags> [formats]

Formats
    html
    markdown, md
    plaintext, text

Flags
    -d, --directory  Sets the generation directory (should contain _pages/)
    -h, --help       Shows this message
    -v, --version    Shows the current version
    END, exe_name, VERSION, FLAVOR, error_string);
}

main :: () {
    document: Document;

    args := get_command_line_arguments();
    exe_name := path_filename(args[0]);

    args.count -= 1;
    args.data  += 1;

    sep := PATH_SEPARATOR;
    separator.data  = cast(*u8)*sep;
    separator.count = 1;

    cwd := get_working_directory();

    for 0..args.count - 1 {
        arg := args[it];
        is_flag := arg[0] == #char "-";

        if is_flag {
            if arg == {
                case "-h"; #through;
                case "--help";
                    print_help(exe_name);
                    return;

                case "-v"; #through;
                case "--version";
                    print("%1 v% (%)\n", NAME, VERSION, FLAVOR);
                    return;

                case "-d"; #through;
                case "--directory";
                    if it >= args.count - 1 {
                        print("Error: expected directory after '%' flag!\n", arg);
                        return;
                    }

                    cwd = join(cwd, separator, args[it + 1], separator);
                    it += 1;
                    continue;

                case;
                    print_help(exe_name, arg);
                    return;
            }
        }
        else {
            if arg == {
                case "html";
                    document.formats |= .Html;

                case "md"; #through;
                case "markdown";
                    document.formats |= .Markdown;

                case "txt"; #through;
                case "text"; #through;
                case "plaintext";
                    document.formats |= .Plaintext;
            }
        }
    }

    root_directory = cwd;
    root_directory = replace(root_directory, "/", separator);

    set_working_directory(root_directory);

    pages_directory   := join(root_directory, separator, "_pages", separator);
    output_directory  := join(root_directory, separator, "out", separator);
    include_directory := join(pages_directory, separator, "include", separator);

    document.dir_root     = root_directory;
    document.dir_pages    = pages_directory;
    document.dir_includes = include_directory;
    document.dir_output   = output_directory;

    // If no formats were passed, default to html
    if !document.formats {
        document.formats = .Html;
    }

    start_time := get_time();

    // Check passed formats and create each output directory
    ok := make_directory_if_it_does_not_exist(document.dir_output);
    if !ok {
        print("Unable to create output directory: %\n", document.dir_output);
        return;
    }

    if document.formats & .Html {
        document.dir_html = join(document.dir_output, "html", separator);
        ok := make_directory_if_it_does_not_exist(document.dir_html);
        if !ok {
            print("Unable to make directory for Html: %\n", document.dir_html);
            return;
        }
    }
    if document.formats & .Markdown {
        document.dir_markdown = join(document.dir_output, "markdown", separator);
        ok := make_directory_if_it_does_not_exist(document.dir_markdown);
        if !ok {
            print("Unable to make directory for Markdown: %\n", document.dir_markdown);
            return;
        }
    }
    if document.formats & .Plaintext {
        document.dir_plaintext = join(document.dir_output, "plaintext", separator);
        ok := make_directory_if_it_does_not_exist(document.dir_plaintext);
        if !ok {
            print("Unable to make directory for Plaintext: %\n", document.dir_plaintext);
            return;
        }
    }

    // Grab all page files for the formats selected 
    all_files := file_list(document.dir_pages, false, false);
    for 0..all_files.count - 1 {
        file: string = ---;

        #if OS == .WINDOWS {
            all_files[it] = replace(all_files[it], "/", "");
            file = all_files[it];
        }
        else {
            file = all_files[it];
        }

        if !contains(file, ".page") continue;

        extension := path_extension(file);
        if extension == {
            case "html";
                if !(document.formats & .Html) continue;

            case "md"; #through;
            case "markdown";
                if !(document.formats & .Markdown) continue;

            case "txt"; #through;
            case "text";
                if !(document.formats & .Plaintext) continue;
        }

        array_add(*document.page_files, file);
    }

    // Grab all post files
    for file: all_files if path_extension(file) == "post" {
        array_add(*document.post_files, file);
    }

    formats_to_output := enum_flags_set(document.formats);

    // Process every post, generate output for each format
    for post: document.post_files {
        contents, ok := read_entire_file(post);
        if !ok {
            print("Unable to open post: %\n", post);
            continue;
        }

        #if OS == .WINDOWS {
            contents = replace(contents, "\r", "");
        }

        document.current_post          = array_add(*document.posts);
        document.current_post.filename = path_filename(post);

        for current_format: formats_to_output {
            reset(*document.current_output);

            document.current_format   = current_format;
            document.current_contents = contents;

            while has_token(document.current_contents) {
                token, ok := next(*document.current_contents);
                if !ok break;

                if token == #char "\\" {
                    // Line comment
                    next_token, ok := peek(*document.current_contents);
                    if ok && next_token == #char "." {
                        while has_token(document.current_contents) {
                            token, ok := next(*document.current_contents);
                            if !ok || token == #char "\n" break;
                        }

                        continue;
                    }

                    doc_string, process_ok := process_tag(*document);
                    if !process_ok break;

                    if doc_string.count {
                        append(*document.current_output, doc_string);

                        if document.current_format != .Plaintext {
                            append(*document.current_output, "\n");
                        }
                    }
                }
            }

            table_add(
                *document.current_post.contents,
                current_format,
                builder_to_string(*document.current_output)
            );
        }

        { // Convert the post title into something that can be used for directories/urls
            sanitized: String_Builder;

            output_file := document.current_post.title;
            if document.current_post.url.count {
                output_file = document.current_post.url;
            }

            for 0..output_file.count - 1 {
                chr := output_file[it];

                if (chr >= #char "a" && chr <= #char "z") ||
                   (chr >= #char "A" && chr <= #char "Z") ||
                   (chr >= #char "0" && chr <= #char "9") ||
                   (chr == #char "-" || chr == #char "_")
                {
                    append(*sanitized, to_lower(chr));
                }
                else if chr == #char " " || chr == #char "\t" || chr == #char "\n" {
                    append(*sanitized, #char "-");
                }
            }

            document.current_post.output_file = builder_to_string(*sanitized);
        }
    }

    // Sort posts by date before generating any pages
    insertion_sort(document.posts, (l: Post, r: Post) -> int {
        if l.date > r.date return -1;
        if l.date < r.date return 1;
        return 0;
    });

    page_table: Table(string, string);
    pages_generated := 0;
    posts_generated := 0;

    // Generate non-template files
    for path: document.page_files {
        filename  := path_filename(path);
        extension := path_extension(filename);

        if contains(filename, "post") continue;

        format: Document.Output_Format;
        output_dir: string;

        if extension == {
            case "html";
                format = .Html;
                output_dir = document.dir_html;
            case "markdown";
                format = .Markdown;
                output_dir = document.dir_markdown;
            case "text";
                format = .Plaintext;
                output_dir = document.dir_plaintext;

            case;
                print("Unknown format: %\n", extension);
                continue;
        }

        template, ok := table_find(page_table, filename);
        if !ok {
            contents, ok := read_entire_file(path);
            if !ok {
                print("Unable to open page file: %\n", path);
                continue;
            }

            table_set(*page_table, filename, contents);
            template = contents;
        }

        index := find_index_from_left(filename, ".");
        filename.count = index;

        output_path: string;
        if format == .Html && filename != "index" {
            tmp := join(output_dir, filename);
            output_path = join(tmp, separator, "index.html");
            make_directory_if_it_does_not_exist(tmp);
        }
        else {
            output_path = join(output_dir, filename, ".", extension);
        }

        print("Generating Page: %.%\n", filename, extension);

        ok = generate_post(document, .{}, format, template, output_path, *page_table); 
        if !ok {
            print("Unable to generate page: %\n", path);
            continue;
        }

        pages_generated += 1;
    }

    // Output generated posts for each format
    for post: document.posts {
        print("Generating Post (%): % -> %\n", document.formats, post.title, post.output_file);

        for file, format: post.contents {
            sub_dir: string = ---;
            if format == {
                case .Html      ; sub_dir = "html";
                case .Markdown  ; sub_dir = "markdown";
                case .Plaintext ; sub_dir = "plaintext";
            }

            template_filename := tprint("post.page.%", sub_dir);

            post_file_template, ok := table_find(page_table, template_filename);
            if !ok {
                contents, ok := read_entire_file(join(document.dir_pages, template_filename));
                if !ok {
                    print("Unable to open template file: %\n", template_filename);
                    continue;
                }

                table_set(*page_table, template_filename, contents);
                post_file_template = contents;
            }

            path := join(document.dir_output, sub_dir, separator, post.output_file);

            if format == .Html {
                ok = make_directory_if_it_does_not_exist(path);
                if !ok {
                    print("Unable to create directory for post: %\n", post.title);
                    continue;
                }

                path = join(path, separator, "index.html");
            }
            else {
                path = join(path, ".", sub_dir);
            }

            ok = generate_post(document, post, format, post_file_template, path, *page_table); 
            if !ok {
                print("Failed to create post: % (% -> %.%) \n", post.title, post.filename, post.output_file, sub_dir);
                continue;
            }
        }

        posts_generated += 1;
    }

    end_time := get_time();
    duration := end_time - start_time;

    print(
        ":: Generated % page%, % post% in % second%!\n",
        pages_generated,
        ifx pages_generated == 1 then "" else "s",
        posts_generated,
        ifx posts_generated == 1 then "" else "s",
        formatFloat(duration, zero_removal = .NO),
        ifx duration == 1 then "" else "s",
    );
}

#load "util.jai";

#import "Sort";
#import "File";
#import "Basic";
#import "String";
#import "System";
#import "File_Utilities";
#import "Hash_Table";
#import "Unicode";

#import "IntroSort";
