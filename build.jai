PROJECT_NAME    :: "doc";
PROJECT_VERSION :: "2.0.0a";
PROJECT_COMPILATION_DATE: string;

FAST         := false;
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

    set_build_options_dc(.{ do_output = false });

    target := get_build_options();

    import_path: [..]string;
    array_add(*import_path, ..target.import_path);
    array_add(*import_path, tprint("%1/vendor/", #filepath));

    target.import_path            = import_path;
    target.output_type            = .EXECUTABLE;
    target.output_path            = build_directory;
    target.output_executable_name = PROJECT_NAME;

    workspace := compiler_create_workspace();
    set_build_options(target, workspace);

    // Configurable flags
    add_build_string(tprint("FAST         :: %;", FAST), workspace);
    add_build_string(tprint("DEVELOPER    :: %;", DEVELOPER), workspace);
    add_build_string(tprint("RUN_TESTS    :: %;", RUN_TESTS), workspace);
    add_build_string(tprint("RUN_PROFILER :: %;", RUN_PROFILER), workspace);

    add_build_string(tprint("PROJECT_NAME    :: \"%\";", PROJECT_NAME), workspace);
    add_build_string(tprint("PROJECT_VERSION :: \"%\";", PROJECT_VERSION), workspace);

    {
        time := get_system_time();
        PROJECT_COMPILATION_DATE = sprint("%/%/%", time.year, time.month, time.day);
        add_build_string(tprint("PROJECT_COMPILATION_DATE :: \"%\";", PROJECT_COMPILATION_DATE), workspace);
    }

    add_build_file("source/main.jai", workspace);
}

#import "File";
#import "Basic";
#import "String";
#import "Compiler";
