#import "Basic";

#scope_file

#import "String";
#import "System";
#import "Window_Creation";
#import "Input";
#import "Windows";
// TODO How to enable this?
#import "GL"; //( DUMP_GL_ERRORS = true );
Simp  :: #import "Simp";

#load "opengl.jai";

// TODO Add to autosaved state & configuration
WINDOW_WIDTH  :: 900;
//WINDOW_HEIGHT :: 720;

mainWindow: Window_Type;

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

    // TODO Do this in a cross-platform way
    screenWidth := GetSystemMetrics( SM_CXSCREEN );
    screenHeight := GetSystemMetrics( SM_CYSCREEN );

    // TODO May want to get more platform specific at some point for events etc? idk
    mainWindow = create_window( WINDOW_WIDTH, screenHeight, "r.e.p.l.r.", (screenWidth - WINDOW_WIDTH) / 2, 0 );
    if( !mainWindow )
        exit( 1 );

    if( !OpenGLInit( mainWindow ) )
        exit( 1 );

    pixelHeight := screenHeight / 24;
    mainFont := Simp.get_font_at_size("data/fonts", "consolas_nf_regular.ttf", pixelHeight );
    if( mainFont == null )
    {
        print( "Failed loading font 'data/fonts/consolas_nf_regular.ttf'\n" );
        exit( 1 );
    }

    quit := false;
    while !quit
    {
        update_window_events();

        for events_this_frame
        {
            if it.type == .QUIT
                quit = true;
            else if it.type == .KEYBOARD
            {
                if it.key_pressed == 0
                    continue;

                //if it.key_code == .ESCAPE
                    //quit = true;
            }
        }

        OpenGLDrawTest( WINDOW_WIDTH, screenHeight );

        swap_buffers( mainWindow );
    }
    
    exit( 0 );
}

// Taken from the Simp OpenGL backend
swap_buffers :: ( window: Window_Type, vsync := true )
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

