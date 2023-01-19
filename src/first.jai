#import "Basic";

#scope_file

#import "File";
#import "String";
#import "System";
#import "Window_Creation";
#import "Input";
#import "File_Utilities";
// TODO How to enable this?
#import "GL"; //( DUMP_GL_ERRORS = true );
#import "freetype-2.12.1";

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

#program_export

NvOptimusEnablement : DWORD = 0x01;
AmdPowerXpressRequestHighPerformance : DWORD = 0x01;

#scope_export

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


    ft: FT_Library;

    error := FT_Init_FreeType( *ft );
    if error
    {
        print( "Failed initialising FreeType lib!" );
        exit( 1 );
    }

    fontData, success := read_entire_file( "data/fonts/consolas_nf_regular.ttf" );
    if !success
    {
        print( "Failed loading font 'data/fonts/consolas_nf_regular.ttf'\n" );
        exit( 1 );
    }

    face: FT_Face;
    error = FT_New_Memory_Face( ft, fontData.data, cast(s32) fontData.count, 0, *face );
    if error
    {
        print( "Failed parsing font 'data/fonts/consolas_nf_regular.ttf'\n" );
        exit( 1 );
    }

    error = FT_Set_Pixel_Sizes( face, 0, 58 );
    assert(!error);


    app : HMODULE;
    app_modtime : Apollo_Time;
    app_dll_path := sprint( "bin/%.dll", APP_DLL_NAME );
    temp_dll_ord := 0;

    quit := false;
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
                    windowWidth  = it.width;
                    windowHeight = it.height;

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

        text := test();
        OpenGLDrawFSQTest( *glState, text );

        OpenGLDrawTextWithGlyphs( *glState, "ABCDEFGHJKLMNOPQRSTUVWXYZ", 100, 500, face );
        OpenGLDrawTextWithGlyphs( *glState, "abcdefghjklmnopqrstuvwxyz", 100, 600, face );
        OpenGLDrawTextWithGlyphs( *glState, " !\"#$%&'()*+,-./", 100, 700, face );

        Swap( mainWindow );
    }

    FT_Done_Face( face );
    FT_Done_FreeType( ft );
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


