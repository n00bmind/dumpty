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
INIT_WINDOW_WIDTH  :: 1000;
//WINDOW_HEIGHT :: 720;
APP_DLL_NAME :: "replr";

mainWindow: Window_Type;
glState: OpenGLState;

test : () -> string = null;

Line :: struct
{
    absStartPos: s64;
    absOnePastEndPos: s64;
    flags: u32;
}
SourceBuffer :: struct
{
    MAX_SIZE :: 16 * 1024;
    SIZE_MASK :: MAX_SIZE - 1;
    MAX_LINES :: 1024;
    LINES_MASK :: MAX_LINES - 1;
    
    bytes: [] u8;
    lines: [] Line;
    // Points to the next character to write. Absolute, so needs to be masked
    absoluteHeadPos: u64;
    // Same as above, but for the *current* (open) line in the lines buffer
    absoluteLineIdx: u64;
    bytesFilled: bool;
    linesFilled: bool;
}
#assert( IsPowerOfTwo( SourceBuffer.MAX_SIZE ) );
#assert( IsPowerOfTwo( SourceBuffer.MAX_LINES ) );


InitSourceBuffer :: ( buffer: *SourceBuffer )
{
    base: *void;
    // Ensure we can call this on already initialised data
    free( buffer.bytes.data );
    buffer.bytes, base = NewArray( SourceBuffer.MAX_SIZE, u8 );
    assert( base == buffer.bytes.data );

    free( buffer.lines.data );
    buffer.lines, base = NewArray( SourceBuffer.MAX_LINES, Line );
    assert( base == buffer.lines.data );
}

// TODO For the general case we'll actually want to be able to get a range in the buffer to copy straight into
AppendToSourceBuffer :: ( buffer: *SourceBuffer, data: string )
{
    assert( data.count < buffer.bytes.count );

    relPos := cast(s64)(buffer.absoluteHeadPos & SourceBuffer.SIZE_MASK);
    available := buffer.bytes.count - relPos;

    // Do we need to split the copy? (if we're approaching the end of the buffer)
    if( data.count < available )
    {
        memcpy( buffer.bytes.data + relPos, data.data, data.count );
        ParseNewLines( buffer, relPos, data.count );
    }
    else
    {
        memcpy( buffer.bytes.data + relPos, data.data, available );
        memcpy( buffer.bytes.data, data.data + available, data.count - available );

        ParseNewLines( buffer, relPos, available );
        ParseNewLines( buffer, 0, data.count - available );
    }
    buffer.absoluteHeadPos += xx data.count;
    if buffer.absoluteHeadPos >= xx buffer.bytes.count
        buffer.bytesFilled = true;
}

GetLineLength :: ( line: Line ) -> s64
{
    // TODO Test lines that span back to expired buffer positions
    // TODO What about lines that span the whole buffer?
    result := line.absOnePastEndPos - line.absStartPos;
    return result;
}

GetCharAt :: ( buffer: SourceBuffer, line: Line, col: int ) -> u8
{
    relPos := (line.absStartPos + col) & SourceBuffer.SIZE_MASK;
    return buffer.bytes[ relPos ];
}

ParseNewLines :: ( buffer: *SourceBuffer, absStartPos: s64, sizeBytes: s64 )
{
    srcChar := *buffer.bytes[ absStartPos & SourceBuffer.SIZE_MASK ];
    line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LINES_MASK ];

    // FIXME We obvs want to do this faster, at least 16 chars at a time
    for absStartPos .. absStartPos + sizeBytes - 1
    {
        defer
        {
            srcChar += 1;
            if srcChar >= buffer.bytes.data + buffer.bytes.count
                srcChar = buffer.bytes.data;
        }

        if <<srcChar == #char "\n"
        {
            line.absOnePastEndPos = it + 1;

            line += 1;
            if line >= buffer.lines.data + buffer.lines.count
                line = buffer.lines.data;
            // Start a new, initially empty line
            line.absStartPos = it + 1;
            line.absOnePastEndPos = it + 1;

            buffer.absoluteLineIdx += 1;
            if buffer.absoluteLineIdx >= xx buffer.lines.count
                buffer.linesFilled = true;
        }
    }
}


InitRendererState :: ( state: *RendererState, windowWidth: s32, windowHeight: s32, face: LoadedFace, maxCellCount: s32 )
{
    state.windowDim    = .{ windowWidth, windowHeight };
    state.cellSize     = .{ face.advance, face.lineHeight };
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

PackColor :: ( color: v3 ) -> u32
{
    result: u32 = (((cast(u32)(color.z * 255)) & 0xFF) << 16)
                | (((cast(u32)(color.y * 255)) & 0xFF) << 8)
                |  ((cast(u32)(color.x * 255)) & 0xFF);
    return result;
}

UpdateRendererCells :: ( state: *RendererState, face: LoadedFace, sourceBuffer: SourceBuffer, lineOffset: s64 )
{
    fg := PackColor( .{ 1, 1, 1 } );
    bg := PackColor( .{ 0.15, 0.15, 0.2 } );

    absStartLineIdx: u64 = (sourceBuffer.absoluteLineIdx - xx lineOffset - xx state.cellCount.y);
    // Clamp at 0 if we underflowed but the buffer has never filled up yet
    // TODO Do we wanna initially fill the window from the top down or the bottom up?
    //if !sourceBuffer.linesFilled && absStartLineIdx > sourceBuffer.absoluteLineIdx
        //absStartLineIdx = 0;
    relStartLineIdx := absStartLineIdx & SourceBuffer.LINES_MASK;
    line := *sourceBuffer.lines[ relStartLineIdx ];

    linePos := 0;
    dst := state.cells.data;
    for row: 0..state.cellCount.y - 1
    {
        lineLength := GetLineLength( <<line );

        for col: 0..state.cellCount.x - 1
        {
            defer dst += 1;

            dst.foregroundColor = fg;
            dst.backgroundColor = bg;

            if linePos >= lineLength
            {
                // Glyph 0,0 is always the empty/space glyph
                dst.glyphIndex = 0;
                continue;
            }

            char := GetCharAt( sourceBuffer, <<line, linePos );
            if char >= 32 && char < 127
            {
                glyph := face.glyphs[ char - 32 ];
                dst.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);
            }
            else
            {
                // TODO Make a reserved glyph for "unkown symbol"
                dst.glyphIndex = 0;
            }

            linePos += 1;
        }

        // TODO Line wrapping
        line += 1;
        if line >= sourceBuffer.lines.data + sourceBuffer.lines.count
            line = sourceBuffer.lines.data;

        linePos = 0;
    }
    // FIXME Current line at absoluteLineIdx will be empty, so ensure we draw up to the end of the buffer
}


// TODO Disabled for now so we use Intel by default on the laptop
// (we probably don't want to force this anyway?)
//#program_export

//NvOptimusEnablement : DWORD = 0x01;
//AmdPowerXpressRequestHighPerformance : DWORD = 0x01;

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
        // TODO Find and call the newer function for Win10
        //SetProcessDPIAwareContext( .. );

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
    EnableVSync( false );

    windowX, windowY, windowWidth, windowHeight := get_dimensions( mainWindow, false );
    //print( "Window dimensions: %, % - %, %\n", windowX, windowY, windowWidth, windowHeight );

    loadedFace, success := OpenGLLoadFont( "data/fonts/consolas_nf_regular.ttf", 16 );
    if !success
    {
        print( "Failed loading font 'data/fonts/consolas_nf_regular.ttf'\n" );
        exit( 1 );
    }


    lipsumData, success2 := read_entire_file( "data/lipsum.txt" );
    assert( success2 );
    lipsumWrappedData, success3 := read_entire_file( "data/lipsum_wrapped.txt" );
    assert( success3 );

    sourceBuffer: SourceBuffer;
    InitSourceBuffer( *sourceBuffer );
    AppendToSourceBuffer( *sourceBuffer, lipsumWrappedData );


    app : HMODULE;
    app_modtime : Apollo_Time;
    app_dll_path := sprint( "bin/%.dll", APP_DLL_NAME );
    temp_dll_ord := 0;

    renderer : RendererState;
    InitRendererState( *renderer, windowWidth, windowHeight, loadedFace, glState.gridShader.maxCellCount );
    
    lineOffset: s64;

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

                    InitRendererState( *renderer, windowWidth, windowHeight, loadedFace, glState.gridShader.maxCellCount );
                    print( "New window dimensions: %, %\n", windowWidth, windowHeight );
                }
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

                if it.key_code ==
                {
                    case .F4;
                    if it.alt_pressed
                        quit = true;
                //if it.key_code == .ESCAPE
                    //quit = true;

                    case .PAGE_UP;
                    lineOffset += renderer.cellCount.y / 2;
                    case .PAGE_DOWN;
                    lineOffset -= renderer.cellCount.y / 2;
                }
            }
        }

        lineOffset = clamp( lineOffset, 0, sourceBuffer.lines.count - renderer.cellCount.y - 1 );
        glState.windowWidth = cast(float)windowWidth;  
        glState.windowHeight = cast(float)windowHeight;

        //text := test();

        UpdateRendererCells( *renderer, loadedFace, sourceBuffer, lineOffset );
        OpenGLRender( *glState, loadedFace, renderer );

        Swap( mainWindow );

        reset_temporary_storage();

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


