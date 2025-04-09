#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "File";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    print( "Working directory for 'build' metaprogram: '%'\n", get_working_directory() );

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";

    build_release := false;
    args := global_options.compile_time_command_line;

    for arg: args
    {
        if arg ==
        {
            case "--release"; #through;
            case "-release"; #through;
            case "release";
                build_release = true;
                print( "Building release version.\n" );
        }
    }

    if build_release
    {
        set_optimization( *global_options, .VERY_OPTIMIZED, true );
        global_options.backend =.LLVM;
    }
    else
    {
        set_optimization( *global_options, .DEBUG, true );
        global_options.backend =.X64;
    }


    // Application DLL
    {
        w := compiler_create_workspace();
        options := global_options;
        // TODO Actually, for release we wouldn't even want a separate dll
        options.output_type = .DYNAMIC_LIBRARY;
        options.output_executable_name = "replr";
        set_build_options( options, w );

        add_build_file( "src/app.jai", w );
    }

    // Main executable
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "run";
        set_build_options( options, w );

        add_build_file( "src/first.jai", w );
    }

    // Test data
    {
        builder: String_Builder;
        builder.allocator = temp;

        buffer: [64] u8;
        line := string.{ buffer.count, buffer.data };

        for n: 0 .. 65535
        {
            print_to_builder( *builder, "%\n", 65536 - n );
        }

        write_entire_file( "data/lines", *builder );
    }

}
#run build();

