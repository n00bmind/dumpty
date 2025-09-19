#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "File";
#import "File_Utilities";

#load "src/interface.jai";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    basePath := get_working_directory();
    print( "Working directory for 'build' metaprogram: '%'\n", basePath );

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";

    do_dist := false;
    build_release := false;
    config := BuildConfig.Debug;

    args := global_options.compile_time_command_line;
    for arg: args
    {
        if arg ==
        {
            case "--release"; #through;
            case "-release"; #through;
            case "release";
                build_release = true;
                config = .Release;
                print( "Building release version.\n" );

            case "dist";
                // TODO Support specifying a custom target path
                do_dist = true;
        }
    }

    configStr := tprint( "BUILD_CONFIG :: BuildConfig.%;\n", config );

    shaderStr := "";
    if build_release
    {
        set_optimization( *global_options, .VERY_OPTIMIZED, true );
        global_options.backend =.LLVM;

        // Build string for embedding the grid shader
        // TODO Doesnt look like we really care about zero terminating this does it
        gridShader := read_entire_file( tprint( "src/%", GRID_SHADER_FILENAME ),
                                        zero_terminated = true );
        shaderStr = tprint( "GRID_SHADER :: #string END\n%\nEND;", gridShader );
    }
    else
    {
        set_optimization( *global_options, .DEBUG, true );
        global_options.backend =.X64;
    }


    distWorkspaces: [..] Workspace;

    // Application DLL
    {
        w := compiler_create_workspace();
        options := global_options;
        // TODO Actually, for release we wouldn't even want a separate dll
        options.output_type = .DYNAMIC_LIBRARY;
        options.output_executable_name = APP_DLL_NAME;
        set_build_options( options, w );

        compiler_begin_intercept( w );

        add_build_file( "src/app.jai", w );
        add_build_string( configStr, w );

        array_add( *distWorkspaces, w );
    }

    // Main executable
    {
        w := compiler_create_workspace();
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "dumpty";
        set_build_options( options, w );

        compiler_begin_intercept( w );

        add_build_file( "src/first.jai", w );
        add_build_string( configStr, w );

        array_add( *distWorkspaces, w );
    }

    // Test programs
    {
        VisitorContext :: struct
        {
            buildOptions: *Build_Options;
            // workspaces: *[..] Workspace;
        }
        ctx: VisitorContext = .{ *global_options };

        visitor :: ( info: *File_Visit_Info, user_data: *VisitorContext )
        {
            w := compiler_create_workspace();
            options := user_data.buildOptions.*;
            options.output_type = .EXECUTABLE;
            options.output_executable_name = path_strip_extension( info.short_name );
            set_build_options( options, w );

            add_build_file( tprint( "src/tests/%", info.short_name ), w );
            // add_build_string( configStr, w );
        }
        visit_files( "src/tests", recursive = false, *ctx, visitor, follow_directory_symlinks = false );
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


    distPath := "";
    if do_dist
    {
        // Figure out where we'd copy files of interest
        distPath = join( to_string( getenv( "DEV_HOME" ) ), "bin/dumpty/", separator = "/" );
        if !make_directory_if_it_does_not_exist( distPath )
        {
            log( "> dist: Failed creating target dir: '%'. 'dist' action aborted.\n", distPath );
            // Don't continue 'dist' action if we cannot create the output dir
            do_dist = false;
        }

        if do_dist
        {
            // Copy 'tools' & 'data'
            blacklist := string.[
                "huge",
            ];
            log( "> dist: Copying 'tools' to %..\n", distPath );
            copy_files_recursively( join( basePath, "tools", separator = "/" ), join( distPath, "tools/" ), blacklist );
            log( "> dist: Copying 'data' to %..\n", distPath );
            copy_files_recursively( join( basePath, "data", separator = "/" ), join( distPath, "data/" ), blacklist );
        }
    }


    // Main msg loop for all workspaces
    completed := 0;
    while true
    {
        message := compiler_wait_for_message();
        if message.kind ==
        {
            case .PHASE;
                phase := cast(*Message_Phase) message;
                // Wait for compilation to finish before attempting 'dist' action
                if phase.phase == .POST_WRITE_EXECUTABLE && do_dist
                {
                    if !phase.executable_write_failed && array_find( distWorkspaces, phase.workspace )
                    {
                        srcPath := phase.compiler_generated_object_files[0];
                        srcPath = join( path_strip_filename( srcPath ), phase.executable_name );
                        tgtPath := join( distPath, phase.executable_name );

                        log( "> dist: Copying % to %..\n", srcPath, distPath );
                        copy_file( srcPath, tgtPath );
                    }
                }

            case .FILE;
                file := cast(*Message_File) message;
                if build_release && ends_with( file.fully_pathed_filename, "opengl.jai" )
                    add_build_string( shaderStr, message.workspace, file );

            // NOTE Atm we only care about adding strings precisely to the workspaces
            // in 'distWorkspaces', which we wait for here, but in the future that
            // may no longer be the case, so we may need to wait for all of them instead..
            case .COMPLETE;
                completed += 1;
                if completed >= distWorkspaces.count
                    break;
        }
    }
}
#run build();


// Adapted from modules/Mac_Os_Bundler
copy_files_recursively :: ( source: string, dest: string, blacklist: []string )
{
    VisitorContext :: struct
    {
        srcPath: string;
        tgtPath: string;
        blacklist: [] string;
    }
    ctx := VisitorContext.{ source, dest, blacklist };

    visitor :: ( info: *File_Visit_Info, ctx: VisitorContext )
    {
        if array_find( ctx.blacklist, path_filename( info.full_name ) )
            return;

        relative_path := info.full_name;
        advance( *relative_path, ctx.srcPath.count );
        out_path := join( ctx.tgtPath, "/", relative_path );

        make_directory_if_it_does_not_exist( path_strip_filename(out_path), recursive = true );
        copy_file( info.full_name, out_path );
    }

    res := visit_files( ctx.srcPath, true, ctx, visitor );
    assert(res);
}

