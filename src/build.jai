#import "Basic";
#import "Compiler";
#import "System";
#import "String";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    path := get_working_directory();
    set_working_directory( join( path, "/.." ) );
    path = get_working_directory();
    print( "Working directory for 'build' metaprogram: '%'\n", path );

    // Right now it seems there's no way to just pass a path string directly
    loc: Source_Code_Location;
    loc.fully_pathed_filename = path;

    global_options := get_build_options();
    global_options.output_path = "bin/";
    global_options.intermediate_path = "bin/";


    // Application DLL
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .DYNAMIC_LIBRARY;
        options.output_executable_name = "replr";
        set_build_options( options, w, loc );

        add_build_file( "app.jai", w );
    }

    // Main executable
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "run";
        set_build_options( options, w, loc );
        // add_build_file appears to not be relative to the CWD
        add_build_file( "first.jai", w );
    }

}
#run build();

