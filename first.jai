PROJECT_NAME :: "doc";
VERSION      :: "0.0.3";
FLAVOR       :: "fly";

FAST         := true;
DEVELOPER    := true;
RUN_TESTS    := false;
RUN_PROFILER := false;

#run {
    args := compiler_get_command_line_arguments();

    for args {
        if it == {
            case "dev"; #through;
            case "!dev"; DEVELOPER = it[0] != #char "!";

            case "test"; #through;
            case "!test"; RUN_TESTS = it[0] != #char "!";

            case "profile"; #through;
            case "!profile"; RUN_PROFILER = it[0] != #char "!";

            case "fast"; #through;
            case "!fast"; FAST = it[0] != #char "!";
        }
    }

    print(#string END
Flags:
    DEVELOPER    :: %
    FAST         :: %
    RUN_TESTS    :: %
    RUN_PROFILER :: %

END, DEVELOPER, FAST, RUN_TESTS, RUN_PROFILER);

    build_directory :: "output/";
    make_directory_if_it_does_not_exist(build_directory);

    // Metaprogram specific options
    set_build_options_dc(.{ do_output = false });

    target := get_build_options();

    import_path: [..]string;
    array_add(*import_path, ..target.import_path);
    array_add(*import_path, tprint("%1/vendor/", #filepath));

    target.import_path            = import_path;
    target.output_type            = .EXECUTABLE;
    target.output_path            = build_directory;
    target.output_executable_name = PROJECT_NAME;

    target.text_output_flags &= ~.OUTPUT_LINK_LINE;

    if FAST {
        target.optimization_level    = .RELEASE;
        target.dead_code_elimination = .ALL;
        // target.emit_debug_info       = .NONE;
    }

    workspace := compiler_create_workspace();
    set_build_options(target, workspace);

    // Platform category defines
    add_build_string(tprint("PLATFORM_MOBILE  :: %;", OS == .IOS || OS == .ANDROID), workspace);
    add_build_string(tprint("PLATFORM_CONSOLE :: %;", OS == .PS4 || OS == .PS5 || OS == .XBOX || OS == .NN_SWITCH), workspace);
    add_build_string(tprint("PLATFORM_DESKTOP :: %;", OS == .WINDOWS || OS == .MACOS || OS == .LINUX), workspace);

    // Configurable flags
    add_build_string(tprint("FAST         :: %;", FAST), workspace);
    add_build_string(tprint("DEVELOPER    :: %;", DEVELOPER), workspace);
    add_build_string(tprint("RUN_TESTS    :: %;", RUN_TESTS), workspace);
    add_build_string(tprint("RUN_PROFILER :: %;", RUN_PROFILER), workspace);

    add_build_string(tprint("NAME    :: \"%\";", PROJECT_NAME), workspace);
    add_build_string(tprint("FLAVOR  :: \"%\";", FLAVOR), workspace);
    add_build_string(tprint("VERSION :: \"%\";", VERSION), workspace);

    add_build_file("source/main.jai", workspace);
}

#import "File";
#import "Basic";
#import "String";
#import "Compiler";
