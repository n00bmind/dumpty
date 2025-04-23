#import "Basic";

// TODO Make an @implements(UpdateAndRenderFunc) note that's parsed by the metaprogram which will then
// #assert( type_of(UpdateAndRender) == UpdateAndRenderFunc );
#program_export
UpdateAndRender :: ( input: AppInput, memory: *AppMemory, renderer: *RendererState )
{
    if !memory.initialized
    {
        Init( memory );
        memory.initialized = true;

        appState := cast(*AppState) memory.appState;
        ret := StartShell( *appState.shellProcess );
        assert( ret, "Failed to start shell" );
    }

    appState := cast(*AppState) memory.appState;
    commandLine := *appState.commandLine;

    for input.events
    {
        if it.type ==
        {
            case .KEYBOARD;
            if it.key_code ==
            {
                case .PAGE_UP;
                {
                    newOffset := appState.lineOffset;
                    newOffset += renderer.cellCount.y / 2;
                    newOffset = Min( newOffset, appState.sourceBuffer.lines.count - renderer.cellCount.y - 1 );
                    // Still need to check we're not showing too far back into sourceBuffer (wrapping around content)
                    absStartLineIdx := GetFirstScreenLineAbsIndex( appState.sourceBuffer.absoluteLineIdx, newOffset,
                                                                    renderer.cellCount.y );
                    line := appState.sourceBuffer.lines[ absStartLineIdx & SourceBuffer.LINES_MASK ];
                    if line.absStartPos < appState.sourceBuffer.absoluteHeadPos - SourceBuffer.MAX_SIZE
                        newOffset = appState.lineOffset;

                    appState.lineOffset = newOffset;
                }
                case .PAGE_DOWN;
                {
                    appState.lineOffset -= renderer.cellCount.y / 2;
                    appState.lineOffset = Max( 0, appState.lineOffset );
                }

                case .BACKSPACE;
                // WriteToProcess( *appState.shellProcess, "\x08" );
                if commandLine.input.count > 0
                    pop( *commandLine.input );

                case .ENTER;
                if begins_with( xx commandLine.input, "#" )
                {
                    AppendToSourceBuffer( *appState.sourceBuffer, tprint( "%\n", cast(string) commandLine.input ) );
                    if !ExecuteBuiltinCommand( *appState.builtinProcess, commandLine.input, appState )
                        AppendToSourceBuffer( *appState.sourceBuffer, "<<replr>> Internal error executing builtin command\n" );
                }
                else
                {
                    // WriteToProcess( *appState.shellProcess, "\n" );
                    //
                    push( *commandLine.input, "\n" );
                    if !ExecuteShellCommand( *appState.shellProcess, commandLine.input )
                        AppendToSourceBuffer( *appState.sourceBuffer, "<<replr>> Internal error executing shell command\n" );
                }
                commandLine.input.count = 0;
            }

            case .TEXT_INPUT;
            {
                value := it.utf32;

                // TODO Temp mem!
                str := character_utf32_to_utf8( value );
                // WriteToProcess( *appState.shellProcess, str );
                push( *commandLine.input, str );
                free( str );
                
                appState.lastInputSeconds = seconds_since_init();
            }
        }
    }

    if IsRunning( appState.builtinProcess )
    {
        alive, result := ReadProcessOutput( *appState.builtinProcess, *appState.sourceBuffer );
        if result.type == .EXITED
        {
            if result.exit_code
                print( "<<replr>> Builtin process exited with error code %.\n", result.exit_code );
            deinit( *appState.builtinProcess );

            WriteToProcess( *appState.shellProcess, "\n" );
        }
        else if result.type == .FAILED_TO_LAUNCH
        {
            print( "<<replr>> Builtin process failed to launch (%).\n", result.exit_code );
            deinit( *appState.builtinProcess );

            WriteToProcess( *appState.shellProcess, "\n" );
        }
    }
    else if IsRunning( appState.shellProcess )
    {
        alive, result := ReadProcessOutput( *appState.shellProcess, *appState.sourceBuffer );
        if !alive
        {
            print( "Shell process died (%).\n", result );
            Reset( *appState.shellProcess );
            // TODO Restart
            assert( false );
        }
    }

    BlinkTimeMillis :: 900;
    blink := ~(cast(int)( (seconds_since_init() - appState.lastInputSeconds) * 1000 / BlinkTimeMillis )) & 1;
    renderer.blinkModulateColor = cast(u32) ifx blink 0xFFFFFFFF else 0xFF111111;

    UpdateRendererCells( renderer, memory.loadedFace, appState.sourceBuffer, appState.lineOffset, <<commandLine );
}

#program_export
Shutdown :: ( memory: *AppMemory )
{
    appState := cast(*AppState) memory.appState;

    Shutdown( *appState.shellProcess );
    Shutdown( *appState.builtinProcess );
}


#scope_module

SourceBuffer :: struct
{
    MAX_SIZE :: 16 * 1024 * 1024;
    SIZE_MASK :: MAX_SIZE - 1;
    MAX_LINES :: 4096;
    LINES_MASK :: MAX_LINES - 1;
    
    bytes: [] u8;
    lines: [] Line;
    // Points to the next character to write. Absolute, so needs to be masked
    absoluteHeadPos: s64;
    // Same as above, but for the *current* (open) line in the lines buffer
    absoluteLineIdx: s64;
    bytesFilled: bool;
    linesFilled: bool;
}
#assert( IsPowerOfTwo( SourceBuffer.MAX_SIZE ) );
#assert( IsPowerOfTwo( SourceBuffer.MAX_LINES ) );

// TODO For the general case we'll actually want to be able to get a range in the buffer to copy straight into
AppendToSourceBuffer :: ( buffer: *SourceBuffer, data: string )
{
    assert( data.count <= buffer.bytes.count );

    relPos := buffer.absoluteHeadPos & SourceBuffer.SIZE_MASK;
    available := buffer.bytes.count - relPos;

    // Do we need to split the copy? (if we're approaching the end of the buffer)
    if( data.count < available )
    {
        memcpy( buffer.bytes.data + relPos, data.data, data.count );
    }
    else
    {
        memcpy( buffer.bytes.data + relPos, data.data, available );
        memcpy( buffer.bytes.data, data.data + available, data.count - available );
    }
    ParseNewLines( buffer, buffer.absoluteHeadPos, data.count );

    buffer.absoluteHeadPos += data.count;
    if buffer.absoluteHeadPos >= buffer.bytes.count
        buffer.bytesFilled = true;
}


#scope_module

#import "String";

AppState :: struct
{
    mainArena: MemoryArena;

    sourceBuffer: SourceBuffer;
    lineOffset: s64;

    commandLine: CommandLine;
    shellProcess: Process;
    builtinProcess: Process;

    lastInputSeconds: float64;
}

Reset :: ( process: *Process )
{
    deinit( process );
    Init( process );
}

#scope_file

#import "File";
#import "Unicode";
#import "Process";
#import "System";
#load "interface.jai";
#load "util.jai";
#load "shell_cmd.jai";


CommandLine :: struct
{
    input: [..] u8;
    // TODO Cursor pos etc
}

Init :: ( memory: *AppMemory ) -> *AppState
{
    // TODO Adjust this better
    // TODO Add support for commiting & decommiting as we go?
    appState := BootstrapStructWithArena( AppState, offsetof( AppState, "mainArena" ), Gigabytes( 1 ) );
    memory.appState = appState;

    // TODO Should concat with exe path
    //lipsumData, success2 := read_entire_file( "data/lipsum.txt" );
    //assert( success2 );
    //lipsumWrappedData, success3 := read_entire_file( "data/lipsum_wrapped.txt" );
    //assert( success3 );

    Init( *appState.sourceBuffer );
    //AppendToSourceBuffer( *appState.sourceBuffer, lipsumWrappedData );

    array_reserve( *appState.commandLine.input, 1024 );

    Init( *appState.shellProcess );
    Init( *appState.builtinProcess );

    return appState;
}

DebugDrawLineBufferValues :: false;
DebugLineValuesReservedCols :: 17;

UpdateRendererCells :: ( renderer: *RendererState, face: *LoadedFace, sourceBuffer: SourceBuffer, lineOffset: s64, commandLine: CommandLine )
{
    LineValuesColOffset :: #ifx DebugDrawLineBufferValues then DebugLineValuesReservedCols else 0;

    fg := PackColor( .{ 1, 1, 1 } );
    bg := PackColor( .{ 0.15, 0.15, 0.2 } );

    commandString := to_string( commandLine.input.data, commandLine.input.count );

    absStartLineIdx := GetFirstScreenLineAbsIndex( sourceBuffer.absoluteLineIdx, lineOffset, renderer.cellCount.y );
    // Clamp at 0 if we underflowed but the buffer has never filled up yet
    // TODO Do we wanna initially fill the window from the top down or the bottom up?
    //if !sourceBuffer.linesFilled && absStartLineIdx > sourceBuffer.absoluteLineIdx
        //absStartLineIdx = 0;
    relStartLineIdx := absStartLineIdx & SourceBuffer.LINES_MASK;
    line := *sourceBuffer.lines[ relStartLineIdx ];

    dst := renderer.cells.data;
    for y: 0..renderer.cellCount.y - 1
    {
        lineLength := GetLineLength( <<line );

        for x: 0..renderer.cellCount.x - 1
        {
            defer dst += 1;

            dst.foregroundColor = fg;
            dst.backgroundColor = bg;
            dst.flags = 0;

            col := x;

            #if DebugDrawLineBufferValues
            {
                if col < LineValuesColOffset
                {
                    char := GetLineBufferCharAt( <<line, col );
                    dst.glyphIndex = GlyphIndexForChar( char, face );
                    dst.foregroundColor = PackColor( .{ 0.5, 0.5, 0.5 } );
                    continue;
                }

                // Offset everything else left
                col -= LineValuesColOffset;
            }

            if col >= lineLength
            {
                // Draw current command and cursor on the last line
                // TODO Probably should just echo everything straight to the shell?
                if lineOffset == 0 && y == renderer.cellCount.y - 1
                {
                    cmdLineStartPos := lineLength;
                    if col >= cmdLineStartPos && col < cmdLineStartPos + commandString.count
                    {
                        char := commandString[ col - cmdLineStartPos ];
                        glyph := *face.glyphs[ char - 32 ];
                        dst.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);
                        continue;
                    }
                    // FIXME Actual cursor pos
                    else if col >= cmdLineStartPos && col == cmdLineStartPos + commandString.count
                    {
                        glyph := *face.glyphs[127 - 32];
                        dst.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);
                        dst.flags |= xx RendererCell.Blinking;
                        continue;
                    }
                }

                // Glyph 0,0 is always the empty/space glyph
                dst.glyphIndex = 0;
                continue;
            }

            char := GetCharAt( sourceBuffer, <<line, col );
            dst.glyphIndex = GlyphIndexForChar( char, face );
        }

        // TODO Line wrapping
        line += 1;
        if line >= sourceBuffer.lines.data + sourceBuffer.lines.count
            line = sourceBuffer.lines.data;
    }
    // FIXME Current line at absoluteLineIdx will be empty, so ensure we draw up to the end of the buffer
    // TODO This is no longer true, but step over all that data and do some tests

    #if false
    {
        for col: 0..renderer.cellCount.x - 1
        {
            dst.foregroundColor = fg;
            dst.backgroundColor = bg;
            dst.flags = 0;

            glyph: *Glyph;
            if col == 0
                glyph = *face.glyphs[ #char ">" - 32 ];
            else if col == 1
            glyph = *face.glyphs[ #char " " - 32 ];
            else if col == command.count + 2
            {
                glyph = *face.glyphs[127 - 32];
                dst.flags |= xx RendererCell.Blinking;
            }
            else if col > command.count + 2
            {
                glyph = *face.glyphs[0];
            }
            else
            {
                char := command[ col - 2 ];
                if char >= 32 && char <= 127
                {
                    glyph = *face.glyphs[ char - 32 ];
                }
                else
                {
                    // TODO Unknown symbol should be separate from the cursor glyph
                    glyph = *face.glyphs[127 - 32];
                }
            }
            dst.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);

            dst += 1;
        }
    }
}


Line :: struct
{
    absStartPos: s64;
    absOnePastEndPos: s64;
    flags: u32;
}

Init :: ( buffer: *SourceBuffer )
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

// TODO Test all this absolute-relative line positions malarkey again
ParseNewLines :: ( buffer: *SourceBuffer, absStartPos: s64, sizeBytes: s64 )
{
    srcChar := *buffer.bytes[ absStartPos & SourceBuffer.SIZE_MASK ];
    line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LINES_MASK ];

    // FIXME We obvs want to do this faster, at least 16 chars at a time
    for absStartPos .. absStartPos + sizeBytes - 1
    {
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
            if buffer.absoluteLineIdx >= buffer.lines.count
                buffer.linesFilled = true;
        }

        srcChar += 1;
        if srcChar >= buffer.bytes.data + buffer.bytes.count
            srcChar = buffer.bytes.data;
    }
    // Ensure the last line runs up to the end of the range
    line.absOnePastEndPos = absStartPos + sizeBytes;
}

GetLineLength :: ( line: Line ) -> s64
{
    // TODO Test lines that span back to expired buffer positions
    // TODO What about lines that span the whole buffer?
    result := line.absOnePastEndPos - line.absStartPos;
    return result;
}

GetFirstScreenLineAbsIndex :: ( absLineIdx: s64, lineOffset: s64, rendererRowCount: s64 ) -> s64
{
    return absLineIdx - lineOffset - rendererRowCount + 1;
}

GetCharAt :: ( buffer: SourceBuffer, line: Line, col: int ) -> u8
{
    relPos := (line.absStartPos + col) & SourceBuffer.SIZE_MASK;
    return buffer.bytes[ relPos ];
}

GetLineBufferCharAt :: ( line: Line, col: int ) -> u8
{
    LineValuesColOffset :: #ifx DebugDrawLineBufferValues then DebugLineValuesReservedCols else 0;

    MaxDigits :: (LineValuesColOffset - 3) / 2;
    Separator :: MaxDigits * 2 + 1;

    #if DebugDrawLineBufferValues
    {
        if col ==
        {
            case MaxDigits; return #char ",";
            case Separator; return #char ":";
            case;
            {
                if col > Separator
                return #char " ";

                value := line.absStartPos & SourceBuffer.SIZE_MASK;
                // value := line.absStartPos;
                if col > MaxDigits
                {
                    col -= (MaxDigits + 1);
                    value = line.absOnePastEndPos & SourceBuffer.SIZE_MASK;
                    // value = line.absOnePastEndPos;
                }
                digit := MaxDigits - col;
                for 1 .. digit - 1
                {
                    value /= 10;
                }
                // return #char "0" + cast(u8) (digit);
                return #char "0" + cast(u8) (value % 10);
            }
        }
    }
    return 0;
}

GlyphIndexForChar :: ( char: u8, face: *LoadedFace ) -> u32
{
    result: u32;
    if char >= 32 && char < 127
    {
        glyph := face.glyphs[ char - 32 ];
        result = cast(u32)((glyph.index.y << 16) | glyph.index.x);
    }
    else
    {
        // TODO Unknown symbol should be separate from the cursor glyph
        // FIXME Also, use the first 32 slots as reserved, but still we can't directly index them like this!
        result = 127;
    }
    return result;
}


Init :: ( process: *Process )
{
    init :: initializer_of(Process);
    inline init( process );

    #if OS == .WINDOWS
        process.info.hProcess = INVALID_HANDLE_VALUE;
    else
        assert( false, "Implement me" );
}

IsRunning :: ( process: Process ) -> bool
{
    #if OS == .WINDOWS
        return process.info.hProcess != INVALID_HANDLE_VALUE;
    else
        assert( false, "Implement me" );
}

Shutdown :: ( process: *Process )
{
    kill_process( process );
    deinit( process );
}
