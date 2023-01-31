#import "Basic";
#import "Compiler";
#import "System";
#import "String";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    path := get_working_directory();
    // NOTE Something broke in the last beta update, and now the bin/ dir is created un folder up relative to what we pass here..
    //set_working_directory( join( path, "/.." ) );
    //path = get_working_directory();
    print( "Working directory for 'build' metaprogram: '%'\n", path );

    // Right now it seems there's no way to just pass a path string directly
    loc: Source_Code_Location;
    loc.fully_pathed_filename = path;

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";


    build_release := false;
    args := global_options.compile_time_command_line;

    for arg: args
    {
        if arg ==
        {
          case "release";
            build_release = true;
            print( "Building release version.\n" );
        }
    }


    // Application DLL
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .DYNAMIC_LIBRARY;
        options.output_executable_name = "replr";
        // TODO Actually, for release we wouldn't even want a separate dll
        if build_release
            options.optimization_level = .RELEASE;
        //else
            //options.backend = .X64;
        set_build_options( options, w, loc );

        // NOTE add_build_file appears to not be relative to the CWD
        add_build_file( "app.jai", w );
    }

    // Main executable
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "run";
        if build_release
            options.optimization_level = .RELEASE;
        //else
            //options.backend = .X64;
        set_build_options( options, w, loc );

        add_build_file( "first.jai", w );
    }

}
#run build();

