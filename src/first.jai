#import "Basic";
#import "System";

#scope_file

#import "File";
#import "String";
#import "Window_Creation";
#import "Input";
#import "File_Utilities";
#import "Windows_Utf8";

#if OS == .WINDOWS {
    #import "Windows";
}

#load "opengl.jai";

// TODO Add to autosaved state & configuration
INIT_WINDOW_WIDTH  :: 900;
//WINDOW_HEIGHT :: 720;
APP_DLL_NAME :: "replr";

mainWindow: Window_Type;
glState: OpenGLState;

test : () -> string = null;

//#program_export

//NvOptimusEnablement : DWORD = 0x01;
//AmdPowerXpressRequestHighPerformance : DWORD = 0x01;

#scope_export

PackColor :: ( color: v3 ) -> u32
{
    result: u32 = (((cast(u32)(color.z * 255)) & 0xFF) << 16)
                | (((cast(u32)(color.y * 255)) & 0xFF) << 8)
                |  ((cast(u32)(color.x * 255)) & 0xFF);
    return result;
}

main :: ()
{
    path := path_strip_filename( get_path_of_running_executable() );
    set_working_directory( join( path, "/.." ) );
    path = get_working_directory();
    print( "Working directory is '%'\n", path );

    #if OS == .WINDOWS
    {
        SetProcessDPIAware();

        timeBeginPeriod(1);

        screenWidth := GetSystemMetrics( SM_CXSCREEN );
        screenHeight := GetSystemMetrics( SM_CYSCREEN );
    }

    // TODO May want to get more platform specific at some point for events etc? idk
    // Assume the taskbar is at the bottom and it has "some" height
    mainWindow = create_window( INIT_WINDOW_WIDTH, screenHeight - 100, "r.e.p.l.r.", (screenWidth - INIT_WINDOW_WIDTH) / 2, 0 );
    if( !mainWindow )
        exit( 1 );

    if( !OpenGLInit( *glState, mainWindow ) )
        exit( 1 );

    windowX, windowY, windowWidth, windowHeight := get_dimensions( mainWindow, false );
    //print( "Window dimensions: %, % - %, %\n", windowX, windowY, windowWidth, windowHeight );

    loadedFace, success := OpenGLLoadFont( "data/fonts/consolas_nf_regular.ttf", 10 );
    if !success
    {
        print( "Failed loading font 'data/fonts/consolas_nf_regular.ttf'\n" );
        exit( 1 );
    }

    lipsumData, success2 := read_entire_file( "data/lipsum.txt" );
    assert( success2 );


    app : HMODULE;
    app_modtime : Apollo_Time;
    app_dll_path := sprint( "bin/%.dll", APP_DLL_NAME );
    temp_dll_ord := 0;

    ResetRenderer :: ( state: *RendererState, windowWidth: s32, windowHeight: s32, face: LoadedFace, maxCellCount: s32 )
    {
        state.windowDim = .{ windowWidth, windowHeight };
        state.borderDim = .{ 10, 6 };
        state.borderColor = PackColor( .{ 0.15, 0.15, 0.2 } );
        state.cellSize = .{ face.advance, face.lineHeight };
        state.cellCount.x = (windowWidth - 2 * state.borderDim.x) / state.cellSize.x;
        state.cellCount.y = (windowHeight - 2 * state.borderDim.y) / state.cellSize.y;

        totalCellCount := state.cellCount.x * state.cellCount.y;
        print( "Allocated cell count: %\n", totalCellCount );
        assert( totalCellCount < maxCellCount, "Need % cells, but the maximum is %", totalCellCount, maxCellCount );

        free( state.cells.data );
        base: *void;
        state.cells, base = NewArray( state.cellCount.x * state.cellCount.y, RendererCell );
    }

    UpdateRendererCells :: ( state: *RendererState, face: LoadedFace, contents: string )
    {
        fg := PackColor( .{ 1, 1, 1 } );
        bg := PackColor( .{ 0.15, 0.15, 0.2 } );

        c := 0;
        for row: 0..state.cellCount.y - 1
        {
            inLineBreak := false;
            for col: 0..state.cellCount.x - 1
            {
                cell := *state.cells[ row * state.cellCount.x + col ];
                cell.foregroundColor = fg;
                cell.backgroundColor = bg;

                if c >= contents.count
                    continue;

                char := contents[c];
                if char == #char "\r"
                {
                    c += 1;
                    continue;
                }
                else if char == #char "\n"
                {
                    c += 1;
                    inLineBreak = true;
                }

                glyph := ifx inLineBreak face.glyphs[0] else face.glyphs[ char - 32 ];
                cell.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);

                if !inLineBreak
                    c += 1;
            }
        }
    }

    renderer : RendererState;
    ResetRenderer( *renderer, windowWidth, windowHeight, loadedFace, glState.gridShader.maxCellCount );

    quit := false;
    frameCount := 0;
    lastTitleUpdateTimestamp: float64 = 0;
    while !quit
    {
        // Check whether we need to load app entry points from the DLL
        modtime, size, modtime_ok := file_modtime_and_size( app_dll_path );
        if modtime_ok && modtime > app_modtime
        {
            // Make a copy of the DLL first so we don't lock it when loading it
            temp_dll_name := tprint( "%.temp.%.dll", APP_DLL_NAME, temp_dll_ord );
            temp_dll_path := tprint( "bin/%", temp_dll_name );

            if copy_file( app_dll_path, temp_dll_path, silent = true )
            {
                old_app := app;
                print( "Found new app dll with modtime %\n", modtime );
                print( "Loading app code from '%'..\n", temp_dll_path );
                app = LoadLibraryA( temp_dll_path.data );
                if app
                {
                    test = cast(type_of(test))GetProcAddress( app, "Test" );
                    //print( "Found 'Test' func at %\n", test );

                    FreeLibrary( old_app );
                    app_modtime = modtime;
                    temp_dll_ord = 1 - temp_dll_ord;
                }
                else
                {
                    error, desc := get_error_value_and_string();
                    print( "App code loading FAILED (%)!\n", desc );
                }
            }
        }

        update_window_events();

        for get_window_resizes()
        {
            if it.window == mainWindow
            {
                sizeChanged := (it.width != windowWidth) || (it.height != windowHeight);

                if sizeChanged
                {
                    // TODO Only allow size increments that are coherent with the cell size & borders
                    windowWidth  = it.width;
                    windowHeight = it.height;

                    ResetRenderer( *renderer, windowWidth, windowHeight, loadedFace, glState.gridShader.maxCellCount );
                    //print( "New window dimensions: %, %\n", windowWidth, windowHeight );
                }
                //if sizeChanged my_init_fonts();  // Resize the font for the new window size.
            }
        }
        for events_this_frame
        {
            if it.type == .QUIT
                quit = true;
            else if it.type == .KEYBOARD
            {
                if it.key_pressed == 0
                    continue;

                if it.key_code == .F4 && it.alt_pressed
                    quit = true;
                //if it.key_code == .ESCAPE
                    //quit = true;
            }
        }

        glState.windowWidth = cast(float)windowWidth;  
        glState.windowHeight = cast(float)windowHeight;

        //text := test();
        OpenGLDrawFSQTest( *glState );

        //OpenGLDrawTextWithFace( *glState, "ABCDEFGHJKLMNOPQRSTUVWXYZ", 100, 500, loadedFace );
        //OpenGLDrawTextWithFace( *glState, "abcdefghjklmnopqrstuvwxyz", 100, 600, loadedFace );
        //OpenGLDrawTextWithFace( *glState, " !\"#$%&'()*+,-./", 100, 700, loadedFace );

        //OpenGLDrawAtlas( *glState, loadedFace );

        UpdateRendererCells( *renderer, loadedFace, lipsumData );
        OpenGLRender( *glState, loadedFace, renderer );

        Swap( mainWindow );

        frameCount += 1;
        // TODO Non-release
        now := get_time();
        if now > lastTitleUpdateTimestamp + 0.5
        {
            elapsedSecs := (now - lastTitleUpdateTimestamp);
            avgPerFrame := elapsedSecs / frameCount;
            text, success, lenBytes :=
                utf8_to_wide( tprint( "% frames in %s. Avg. %ms. (% fps)\0", frameCount, elapsedSecs,
                                      formatFloat( avgPerFrame * 1000, -1, 3 ), formatFloat( 1 / avgPerFrame, -1, 2 ) ) );
            SetWindowTextW( mainWindow, text );

            lastTitleUpdateTimestamp = now;
            frameCount = 0;
        }
    }

    exit( 0 );
}

// Taken from the Simp OpenGL backend
Swap :: ( window: Window_Type, vsync := true )
{
    #if OS == .WINDOWS {
        dc := GetDC(window);
        SwapBuffers(dc);
    } else #if OS == .LINUX {
        info := find_window_info(window);
        if (!info) || !info.specific.glx_window {
            log_error("Simp: Attempt to swap_buffers on a previously unseen window!\n");
            return;
        }
        
        glXSwapBuffers(x_global_display, info.specific.glx_window);
    } else #if OS == .MACOS {
        // On macOS, OpenGL buffer swapping is done on the context, not on the view.
        // So we can only swap for the active window. (And you need to swap before switching to another view).
        assert(window == state.current_window_info.window);
        NSOpenGLContext.flushBuffer(the_gl_context);
    } else {
        assert(false);
    }
}


