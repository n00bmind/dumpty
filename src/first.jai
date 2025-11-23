
#scope_export

// TODO Disabled for now so we use Intel by default on the laptop
// (we probably don't want to force this anyway?)
//#program_export
//NvOptimusEnablement : DWORD = 0x01;
//#program_export
//AmdPowerXpressRequestHighPerformance : DWORD = 0x01;

main :: ()
{
    // Install faster logger
    context.logger = DeferredLogger;
    // print( "### Context.logger: %\n", context.logger );

    binPath := path_strip_filename( get_path_of_running_executable() );

    runPath := binPath;
    if ends_with( runPath, "/bin/" )
        runPath = slice( runPath, 0, runPath.count - 4 );
    print( "Base directory is '%'\n", runPath );

    #if OS == .WINDOWS
    {
        SetProcessDPIAware();
        // TODO Find and call the newer function for Win10
        //SetProcessDPIAwareContext( .. );

        screenWidth := GetSystemMetrics( SM_CXSCREEN );
        screenHeight := GetSystemMetrics( SM_CYSCREEN );
    }

    dataPath := join( get_path_os_program_data(), "/dumpty/" );
    make_directory_if_it_does_not_exist( dataPath );

    settingsPathPath := join( dataPath, "settings_path" );
    settingsPath, settingsPathOk := read_entire_file( settingsPathPath, zero_terminated = false, log_errors = false );
    if settingsPathOk
    {
        // TODO We need to figure out whether this is the same as the last we launched for settings migration etc.
        print( "Loading settings from '%'\n", settingsPath );
    }
    else
    {
        print( "Initializing default settings path: '%'\n", settingsPath );
        // Write a default path (the data path)
        write_entire_file( settingsPathPath, dataPath );
    }

    // Assume the taskbar is at the bottom and it has "some" height
    mainWindow = create_window( INIT_WINDOW_WIDTH, screenHeight - 100, "dumpty", (screenWidth - INIT_WINDOW_WIDTH) / 2, 0 );
    if( !mainWindow )
        exit( 1 );

    if( !OpenGLInit( *glState, mainWindow ) )
        exit( 1 );
    EnableVSync( false );

    windowX, windowY, windowWidth, windowHeight := get_dimensions( mainWindow, false );
    //print( "Window dimensions: %, % - %, %\n", windowX, windowY, windowWidth, windowHeight );

    app : HMODULE;
    appInput: AppInput;
    appMemory: AppMemory;
    appModtime : Apollo_Time;
    appDLLName := sprint( "%.dll", APP_DLL_NAME );
    appDLLPath := join( binPath, appDLLName );

    ft: FT_Library;
    error := FT_Init_FreeType( *ft );
    if error
    {
        print( "Failed initialising FreeType lib!" );
        exit( 1 );
    }

    // TODO See if Jai provides utils to find out the path of font families
    // TODO Do we want to embed a Nerdfont for the fancy airline-like chars?
    loadedFont, success := OpenGLLoadFont( join( runPath, "data/fonts/consolas_nf_regular.ttf" ), 14, *ft );
    // TODO Expand %WINDIR%
    // loadedFont, success := OpenGLLoadFont( "C:/windows/fonts/consolas.ttf", 15, *ft );
    // TODO Embed a small unicode fallback font as well?
    // https://unifoundry.com/unifont/index.html
    // https://github.com/unicode-org/last-resort-font?tab=readme-ov-file
    // https://juliamono.netlify.app/
    // https://www.reddit.com/r/fonts/comments/t453va/what_is_the_most_unicodecomplete_monospaced_font/
    // (.."DejaVu Sans Mono is a highly practical font with a massive collection of Unicode characters"..)
    // What does refterm do for fallbacks? Does DWrite handle it automatically?
    if !success
    {
        print( "Failed loading font!\n" );
        exit( 1 );
    }

    renderer : RendererState;
    InitRendererState( *renderer, mainWindow, windowWidth, windowHeight, *loadedFont, glState.gridShader.maxCellCount );
    
    quit := false;
    frameCount := 0;
    lastTitleUpdateTimestamp: float64 = 0;
    while !quit
    {
        // Check whether we need to load app entry points from the DLL
        modtime, size, modtimeOk := file_modtime_and_size( appDLLPath );
        if modtimeOk && modtime > appModtime
        {
            if LoadAppCode( *app, binPath, appDLLName, *appMemory )
            {
                appModtime = modtime;
                AppInit( *appMemory, *renderer );
            }
        }
        if !app
        {
            print( "FATAL :: Couldn't load app code!\n" );
            exit( 1 );
        }


        AppWaitForInput( *appMemory );

        // TODO Do something akin to https://github.com/cmuratori/dtc to allow normal redrawing while resizing etc.
        update_window_events();

        for get_window_resizes()
        {
            if it.window == mainWindow
            {
                sizeChanged := (it.width != windowWidth) || (it.height != windowHeight);

                if sizeChanged
                {
                    // TODO Only allow size increments that are coherent with the cell size & borders
                    // TODO Keep drawing contents (and updating) while resizing
                    windowWidth  = it.width;
                    windowHeight = it.height;

                    InitRendererState( *renderer, mainWindow, windowWidth, windowHeight, *loadedFont, glState.gridShader.maxCellCount );
                    print( "New window dimensions: %, %\n", windowWidth, windowHeight );
                }
            }
        }

        array_clear :: array_reset_keeping_memory;
        array_clear( *appInput.events );
        for events_this_frame
        {
            if it.type ==
            {
                case .QUIT;
                quit = true;

                case .KEYBOARD;
                {
                    if it.key_pressed == 0
                        continue;

                    if it.key_code ==
                    {
                        case .F4;
                        if it.alt_pressed
                            quit = true;
                    }
                }

                case .TEXT_INPUT;
                // Send everything through

                case;
                    continue;
            }
            array_add( *appInput.events, it );
        }

        glState.windowWidth = cast(float)windowWidth;  
        glState.windowHeight = cast(float)windowHeight;

        // TODO Check out the Remap_Context module and see if we need to do something like that
        // or maybe simply pass along our own prepared Context perhaps?
        // https://discord.com/channels/661732390355337246/1057205060876128278/1381758854236475459
        AppUpdateAndRender( appInput, *appMemory, *renderer );

        // OpenGLDrawTextWithFace( *glState, "H3llo w0rld!", 100, 100, loadedFont );
        OpenGLRender( *glState, loadedFont, renderer );

        Swap( mainWindow );

        reset_temporary_storage();

        frameCount += 1;

        #if BUILD_CONFIG != .Release
        {
            now := seconds_since_init();
            if now > lastTitleUpdateTimestamp + 0.5
            {
                elapsedSecs := (now - lastTitleUpdateTimestamp);
                avgPerFrame := elapsedSecs / frameCount;
                text, success, lenBytes :=
                    utf8_to_wide( tprint( "dumpty - % frames in %s. Avg. %ms. (% fps)\0", frameCount, elapsedSecs,
                                          formatFloat( avgPerFrame * 1000, -1, 3 ), formatFloat( 1 / avgPerFrame, -1, 2 ) ) );
                SetWindowTextW( mainWindow, text );

                lastTitleUpdateTimestamp = now;
                frameCount = 0;
            }
        }
    }

    OpenGLShutdown( *glState );
    AppShutdown( *appMemory );

    FT_Done_Face( cast(FT_Face) renderer.loadedFont.face );
    FT_Done_FreeType( ft );

    // exit( 0 );
}


#scope_file

#import "Basic";
#import "System";
#import "String";
#import "Window_Creation";
#import "File_Utilities";
#import "Windows_Utf8";

#if OS == .WINDOWS {
    #import "Windows";
}

#load "platform/win32.jai";
#load "interface.jai";
#load "opengl.jai";
#load "util.jai";


// TODO Add to autosaved state & configuration
INIT_WINDOW_WIDTH  :: 1000;
//WINDOW_HEIGHT :: 720;

mainWindow: Window_Type;
glState: OpenGLState;


// TODO Move to app?
InitRendererState :: ( state: *RendererState, window: Window_Type, windowWidth: s32, windowHeight: s32, font: *LoadedFont,
                       maxCellCount: s32 )
{
    state.window       = window;
    state.loadedFont   = font;
    state.windowDim    = .{ windowWidth, windowHeight };
    state.cellSize     = .{ font.advance, font.lineHeight };
    state.borderDim    = .{ 10, 6 };
    state.borderColor  = PackColor( .{ 0.15, 0.15, 0.2 } );

    windowContentDim := state.windowDim - 2 * state.borderDim;
    state.cellCount.x  = (windowContentDim.x + state.cellSize.x - 1) / state.cellSize.x;
    state.cellCount.y  = (windowContentDim.y + state.cellSize.y - 1) / state.cellSize.y;

    totalCellCount := state.cellCount.x * state.cellCount.y;
    print( "Allocated cell count: %\n", totalCellCount );
    assert( totalCellCount < maxCellCount, "Need % cells, but the maximum is %", totalCellCount, maxCellCount );

    // Ensure we can call this on already initialised data
    free( state.cells.data );
    base: *void;
    state.cells, base = NewArray( totalCellCount, RendererCell );
    assert( base == state.cells.data );
}


// App API
AppInit: AppInitFunc;
AppShutdown: AppShutdownFunc;
AppWaitForInput: AppWaitForInputFunc;
AppUpdateAndRender: AppUpdateAndRenderFunc;
loadNoticeShown := false;
tempDLLOrdinal := 0;
oldApp: HMODULE;

LoadAppCode :: ( app: *HMODULE, binPath: string, srcPath: string, appMemory: *AppMemory ) -> bool
{
    tempSrcPath := join( binPath, srcPath );
    // Make a copy of the DLL first so we don't lock it when loading it
    tempDLLName := tprint( "%.temp.%.dll", APP_DLL_NAME, tempDLLOrdinal );
    // The docs explicitly mention using '\', although it appears to work with '/' too..
    tempDLLPath := join( binPath, tempDLLName );

    if !loadNoticeShown
    {
        print( "Trying to load app code from '%'..\n", tempDLLPath );
        loadNoticeShown = true;
    }

    if copy_file( tempSrcPath, tempDLLPath, silent = true )
    {
        if <<app
            oldApp = <<app;

        <<app = LoadLibraryA( to_c_string( tempDLLPath ) );
        if <<app
        {
            AppInit = cast(type_of(AppInit)) GetProcAddress( <<app, "AppInit" );
            assert( AppInit != null );

            AppShutdown = cast(type_of(AppShutdown)) GetProcAddress( <<app, "AppShutdown" );
            assert( AppShutdown != null );

            AppUpdateAndRender = cast(type_of(AppUpdateAndRender)) GetProcAddress( <<app, "AppUpdateAndRender" );
            //print( "Found 'AppUpdateAndRender' func at %\n", AppUpdateAndRender );
            assert( AppUpdateAndRender != null );

            AppWaitForInput = cast(type_of(AppWaitForInput)) GetProcAddress( <<app, "AppWaitForInput" );
            assert( AppWaitForInput != null );

            FreeLibrary( oldApp );
            tempDLLOrdinal = 1 - tempDLLOrdinal;

            print( "App code loaded OK\n" );
            loadNoticeShown = false;
            return true;
        }
        else
        {
            error, desc := get_error_value_and_string();
            print( "App code loading FAILED (%)!\n", desc );
        }
    }

    return false;
}

EnableVSync :: ( enabled: bool )
{
    #if OS == .WINDOWS
        wglSwapIntervalEXT( xx ifx enabled then 1 else 0 );
    // TODO Untested from here
    else #if OS == .LINUX
    {
        info := find_window_info( window );
        assert( info && info.specific.glx_window, "Attempt to swap_buffers on a previously unseen window!" );
        
        glXSwapIntervalEXT( x_global_display, info.specific.glx_window );
    }
    else #if OS == .MACOS
    {
        assert( window == state.current_window_info.window );

        value: GLint = ifx enable then 1 else 0;
        NSOpenGLContext.setValues( the_gl_context, *value, NSOpenGLContextParameterSwapInterval );
    }
    else
    {
        assert( false );
    }
}

// Taken from the Simp OpenGL backend
Swap :: ( window: Window_Type, vsync := true )
{
    #if OS == .WINDOWS
    {
        dc := GetDC( window );
        SwapBuffers( dc );
    }
    else #if OS == .LINUX
    {
        info := find_window_info( window );
        assert( info && info.specific.glx_window, "Attempt to swap_buffers on a previously unseen window!" );
        
        glXSwapBuffers( x_global_display, info.specific.glx_window );
    }
    else #if OS == .MACOS
    {
        // On macOS, OpenGL buffer swapping is done on the context, not on the view.
        // So we can only swap for the active window. (And you need to swap before switching to another view).
        assert( window == state.current_window_info.window );
        NSOpenGLContext.flushBuffer( the_gl_context );
    }
    else
    {
        assert( false );
    }
}


ole32    :: #system_library "ole32";
shell32  :: #system_library "shell32";

KNOWNFOLDERID :: GUID;
REFKNOWNFOLDERID :: *KNOWNFOLDERID;

SHGetKnownFolderPath :: ( rfid: REFKNOWNFOLDERID, dwFlags: DWORD, hToken: HANDLE, ppszPath: *PWSTR ) -> HRESULT #foreign shell32;
CoTaskMemFree :: ( pv: *void ) #foreign ole32;

GetWritableStoragePath :: () -> string
{
    FOLDERID_LocalAppData: GUID = string_to_guid( "F1B32785-6FBA-4FCF-9D55-7B8E7F157091" );

    path: PWSTR = null;
    hr := SHGetKnownFolderPath( *FOLDERID_LocalAppData, 0, null, *path );

    result: string;
    if hr == S_OK
    {
        //result = alloc_string( path, c_style_strlen( buffer.data ) );
    }
    CoTaskMemFree( path );

    return result;
}

