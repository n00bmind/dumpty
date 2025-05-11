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
    cmdline := *appState.commandLine;

    for input.events
    {
        if it.type ==
        {
            case .KEYBOARD;
            if it.key_code ==
            {
                case .PAGE_UP;
                {
                    // TODO We should probably just add an offset in bytes based on the current screen size,
                    // then let the layout function solve for the right line to start with
                    // TODO i.e. this should scroll half a page of *VISUAL* lines
                    // TODO Test with some good ol structured data
                    newOffset := appState.lineOffset;
                    newOffset += renderer.cellCount.y / 2;
                    newOffset = Min( newOffset, appState.sourceBuffer.lines.count - renderer.cellCount.y - 1 );
                    // Still need to check we're not showing too far back into sourceBuffer (wrapping around content)
                    absStartLineIdx := GetFirstScreenLineAbsIndex( appState.sourceBuffer.absoluteLineIdx, newOffset,
                                                                    renderer.cellCount.y );
                    line := appState.sourceBuffer.lines[ absStartLineIdx & SourceBuffer.LinesMask ];
                    if line.absStartPos < appState.sourceBuffer.absoluteHeadPos - SourceBuffer.MaxSize
                        newOffset = appState.lineOffset;

                    appState.lineOffset = newOffset;
                }
                case .PAGE_DOWN;
                {
                    appState.lineOffset -= renderer.cellCount.y / 2;
                    appState.lineOffset = Max( 0, appState.lineOffset );
                }

                case .ARROW_UP;
                    // Ensure we dont ever underflow the array
                    minHistoryIdx := ifx cmdline.history.nextEntryAbsIdx >= CommandLineHistory.MaxEntries
                        then cmdline.history.nextEntryAbsIdx - CommandLineHistory.MaxEntries + 1
                        else 0;
                    if cmdline.history.displayedAbsIdx > minHistoryIdx
                    {
                        cmdline.history.displayedAbsIdx -= 1;
                        RetrieveHistoryEntry( cmdline );
                    }
                case .ARROW_DOWN;
                    if cmdline.history.displayedAbsIdx < cmdline.history.nextEntryAbsIdx
                    {
                        cmdline.history.displayedAbsIdx += 1;
                        RetrieveHistoryEntry( cmdline );
                    }

                case .BACKSPACE;
                    // WriteToProcess( *appState.shellProcess, "\x08" );
                    if cmdline.input.count > 0
                        pop( *cmdline.input );

                case .ENTER;
                {
                    if cmdline
                    {
                        UpdateHistoryEntry( cmdline );
                        // TODO We should probably "collapse" (i.e. discard) the entered line
                        // if the previous history entry was identical..
                        CommitHistoryEntry( cmdline );
                    }

                    if begins_with( xx cmdline.input, "#" )
                    {
                        AppendToSourceBuffer( *appState.sourceBuffer, tprint( "%\n", cast(string) cmdline.input ) );
                        if !ExecuteBuiltinCommand( *appState.builtinProcess, cmdline.input, appState )
                        AppendToSourceBuffer( *appState.sourceBuffer, "<<replr>> Internal error executing builtin command\n" );
                    }
                    else
                    {
                        // WriteToProcess( *appState.shellProcess, "\n" );
                        //
                        push( *cmdline.input, "\n" );
                        if !ExecuteShellCommand( *appState.shellProcess, cmdline.input )
                        AppendToSourceBuffer( *appState.sourceBuffer, "<<replr>> Internal error executing shell command\n" );
                    }

                    cmdline.input.count = 0;
                }
            }

            case .TEXT_INPUT;
            {
                value := it.utf32;

                // TODO Temp mem!
                str := character_utf32_to_utf8( value );
                // WriteToProcess( *appState.shellProcess, str );
                push( *cmdline.input, str );
                free( str );
                
                UpdateHistoryEntry( cmdline );
                appState.lastInputSeconds = seconds_since_init();
            }
        }
    }

    BlinkTimeMillis :: 750;
    nowMs := cast(int)( seconds_since_init() * 1000 );
    // Compute how many millis to wait until the next cursor blink switching
    remainder := (nowMs / BlinkTimeMillis + 1) * BlinkTimeMillis - nowMs;

    // FIXME Unsure why but we're getting woken up constantly rn.. *something* seems to cause our message queue to be spammed?
    // This seems to only happen whenever our window has the focus for some reason
    // Even more fun! Seems to happen on the desktop and not on the laptop!?
    WaitForAllOpenHandles( appState, remainder );

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
    if IsRunning( appState.shellProcess )
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

    nowMs = cast(int)( seconds_since_init() * 1000 );
    blink := (nowMs / BlinkTimeMillis) & 1;
    renderer.blinkModulateColor = cast(u32) ifx blink 0xFFFFFFFF else 0xFF111111;

    #if false
    {
        UpdateRendererCells( renderer, memory.loadedFace, appState.sourceBuffer, appState.lineOffset, <<cmdline );
    }
    else
    {
        LayoutScreenBuffer( appState.sourceBuffer, appState.lineOffset, cmdline.*, memory.loadedFace, renderer );
    }
}

#program_export
Shutdown :: ( memory: *AppMemory )
{
    appState := cast(*AppState) memory.appState;

    Shutdown( *appState.shellProcess );
    Shutdown( *appState.builtinProcess );
}


#scope_module

#import "String";

SourceBuffer :: struct
{
    #if BUILD_CONFIG == .Debug
    {
        MaxSize :: 1024 * 1024;
        MaxLines :: 1024;
    }
    else
    {
        MaxSize :: 16 * 1024 * 1024;
        MaxLines :: 8192;
    }
    SizeMask  :: MaxSize - 1;
    LinesMask :: MaxLines - 1;
    
    bytes: [] u8;
    lines: [] Line;
    // Points to the next character to write. Absolute, so needs to be masked
    absoluteHeadPos: s64;
    // Same as above, but for the *current* (open) line in the lines buffer
    absoluteLineIdx: s64;
    bytesFilled: bool;
    linesFilled: bool;

    // Used purely to keep track of the glyph props at the start of every line as new escape codes are ingested
    runningCursor: CursorState;
}
#assert( IsPowerOfTwo( SourceBuffer.MaxSize ) );
#assert( IsPowerOfTwo( SourceBuffer.MaxLines ) );

GetNextWriteableRange :: ( buffer: *SourceBuffer, maxCount: s64 = S64_MAX ) -> [] u8
{
    relPos := buffer.absoluteHeadPos & SourceBuffer.SizeMask;

    maxAvailableCount := buffer.bytes.count - relPos;
    count := Min( maxCount, maxAvailableCount );

    return .{ count, buffer.bytes.data + relPos };
}

CommitWrite :: ( buffer: *SourceBuffer, count: s64 )
{
    relPos := buffer.absoluteHeadPos & SourceBuffer.SizeMask;
    maxAvailableCount := buffer.bytes.count - relPos;

    assert( count <= maxAvailableCount && "Trying to commit data that doesnt fit in the available range" );

    buffer.absoluteHeadPos += count;
    if buffer.absoluteHeadPos >= buffer.bytes.count
        buffer.bytesFilled = true;
}

AppendToSourceBuffer :: ( buffer: *SourceBuffer, data: string )
{
    assert( data.count <= buffer.bytes.count );

    relPos := buffer.absoluteHeadPos & SourceBuffer.SizeMask;
    available := buffer.bytes.count - relPos;

    // Do we need to split the copy? (if we're approaching the end of the buffer)
    if( data.count < available )
    {
        memcpy( buffer.bytes.data + relPos, data.data, data.count );
        ParseLines( buffer, buffer.absoluteHeadPos, data.count );
    }
    else
    {
        memcpy( buffer.bytes.data + relPos, data.data, available );
        memcpy( buffer.bytes.data, data.data + available, data.count - available );

        ParseLines( buffer, buffer.absoluteHeadPos, available );
        ParseLines( buffer, buffer.absoluteHeadPos + available, data.count - available );
    }

    buffer.absoluteHeadPos += data.count;
    if buffer.absoluteHeadPos >= buffer.bytes.count
        buffer.bytesFilled = true;
}

ParseLines :: ( buffer: *SourceBuffer, absStartPos: s64, sizeBytes: s64 )
{
    #if false
    {
        // TODO This block is now lagging behind in terms of features
        srcChar := *buffer.bytes[ absStartPos & SourceBuffer.SizeMask ];
        line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LinesMask ];

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
                line.startingProps = buffer.runningCursor.props;

                buffer.absoluteLineIdx += 1;
                if buffer.absoluteLineIdx >= buffer.lines.count
                buffer.linesFilled = true;
            }

            srcChar += 1;
            if srcChar >= buffer.bytes.data + buffer.bytes.count
            srcChar = buffer.bytes.data;
        }
        // Ensure the last line runs up to the end of the range for now
        line.absOnePastEndPos = absStartPos + sizeBytes;
    }
    else
    {
        // TODO Check codegen for all this stuff
        relStartPos := absStartPos & SourceBuffer.SizeMask;
        assert( relStartPos + sizeBytes <= buffer.bytes.count );

        range: [] u8 = .{ sizeBytes, *buffer.bytes[ relStartPos ] };
        // TODO Test artificial line splitting a bit more (see below)
        SplitLineAtCount :: 4096;
        // SplitLineAtCount :: 32;

        nl := u8.[ 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa, 0xa ];
        esc := u8.[ 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b, 0x1b ];
        nlData := nl.data;
        escData := esc.data;
        #asm
        {
            movdqu carriage: vec, [nlData];
            movdqu escape: vec, [escData];
        }

        while range.count > 0
        {
            data := range.data;
            count := range.count;
            // Ensure really long lines dont case too many issues
            // TODO There's an edge case here, where if a VT code straddles this artificial split, we should stop
            // parsing right at the point where the code starts and restart parsing there on the next ParseLines call
            // For that we'd need to introduce a 'parseHead' which we dont have rn..
            if count > SplitLineAtCount
                count = SplitLineAtCount;

            while count >= 16
            {
                setBits: u32 = 0;
                #asm
                {
                    movdqu batch:, [data];
                    movdqu testNL:, batch;
                    pcmpeqb testNL, carriage;
                    movdqu testEsc:, batch;
                    pcmpeqb testEsc, escape;

                    movdqu test:, testNL;
                    por test, testEsc;
                    pmovmskb testBits:, test;
                    mov [*setBits], testBits;
                }

                if setBits
                {
                    advance := 0;
                    #asm
                    {
                        tzcnt advance, testBits;
                    }
                    data += advance;
                    count -= advance;
                    break;
                }

                data += 16;
                count -= 16;
            }

            ConsumeCount( *range, data - range.data );
            if range.count > 0
            {
                absP := absStartPos + sizeBytes - range.count;

                // TODO Dont we have a similar edge case here? Since the input that comes from the pipe can start wherever,
                // we could start parsing in the middle of some VT code that affects the props, then split a new line right
                // after, and we'll have failed to determine the correct glyphs props to start the line with!?
                // TODO Prepare some kind of test case for this, seems like another argument for an independent 'parseHead'
                escape, cursorJumped := TryParseEscapeCode( *range, *buffer.runningCursor );
                if escape
                {
                    if cursorJumped
                        NewLine( absP, buffer );
                }
                else
                {
                    token := ConsumeToken( *range );
                    if token == #char "\n"
                    {
                        NewLine( absP + 1, buffer );
                    }
                }

            }
            // If the current line has gotten too long, split it now
            absP := absStartPos + sizeBytes - range.count;
            if absP - GetCurLine( buffer ).absStartPos >= SplitLineAtCount
                NewLine( absP, buffer );
        }

        // Ensure the last line runs up to the end of the range for now
        UpdateCurLineEnd( absStartPos + sizeBytes, buffer );
    }
}

NewLine :: ( absP: s64, buffer: *SourceBuffer )
{
    // Complete currently open line
    UpdateCurLineEnd( absP, buffer );

    buffer.absoluteLineIdx += 1;
    if buffer.absoluteLineIdx >= buffer.lines.count
        buffer.linesFilled = true;

    line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LinesMask ];
    // Start a new, initially empty line
    line.absStartPos = absP;
    line.absOnePastEndPos = absP;
    line.startingProps = buffer.runningCursor.props;
}

AppState :: struct
{
    mainArena: MemoryArena;

    sourceBuffer: SourceBuffer;
    lineOffset: s64;

    commandLine: CommandLine;
    cursor: CursorState;

    shellProcess: Process;
    builtinProcess: Process;

    lastInputSeconds: float64;
}

CursorState :: struct
{
    x, y: s32;
    props: GlyphProps;
}

Reset :: ( process: *Process )
{
    deinit( process );
    Init( process );
}

IsRunning :: ( process: Process ) -> bool
{
    #if OS == .WINDOWS
        return process.info.hProcess != INVALID_HANDLE_VALUE;
    else
        assert( false, "Implement me" );
}

#scope_file

#import "File";
#import "Unicode";
#import "Process";
#import "System";
#load "interface.jai";
#load "util.jai";
#load "shell_cmd.jai";


SourceBufferRange :: struct
{
    base: *u8;
    absP: s64;
    count: s64;
}

Line :: struct
{
    absStartPos: s64;
    absOnePastEndPos: s64;
    startingProps: GlyphProps;
}

CommandLine :: struct
{
    input: [..] u8;
    history: CommandLineHistory;
}

CommandLineHistory :: struct
{
    MaxEntries :: 256;
    EntriesMask :: MaxEntries - 1;
    entries: [MaxEntries] [..] u8;

    nextEntryAbsIdx: u32;
    displayedAbsIdx: u32;  // If equal to nextEntry, no entry is displayed
}

UpdateHistoryEntry :: ( using commandLine: *CommandLine )
{
    array_copy( *history.entries[ history.nextEntryAbsIdx & history.EntriesMask ],
                input );
}

// Resets displayed index to point to a new empty entry
CommitHistoryEntry :: ( using commandLine: *CommandLine )
{
    history.nextEntryAbsIdx += 1;
    history.displayedAbsIdx = history.nextEntryAbsIdx;

    newEntry := *history.entries[ history.nextEntryAbsIdx & history.EntriesMask ];
    newEntry.count = 0;
}

RetrieveHistoryEntry :: ( using cmdline: *CommandLine )
{
    src := *history.entries[ history.displayedAbsIdx & history.EntriesMask ];
    array_copy( *input, src.* );
}


Init :: ( memory: *AppMemory ) -> *AppState
{
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

// TODO Delete
UpdateRendererCells :: ( renderer: *RendererState, face: *LoadedFace, sourceBuffer: SourceBuffer, lineOffset: s64, commandLine: CommandLine )
{
    LineValuesColOffset :: #ifx DebugDrawLineBufferValues then DebugLineValuesReservedCols else 0;

    fg := PackColor( .{ 1, 1, 1 } );
    bg := PackColor( .{ 0.15, 0.15, 0.2 } );

    commandString := commandLine.input;

    absStartLineIdx := GetFirstScreenLineAbsIndex( sourceBuffer.absoluteLineIdx, lineOffset, renderer.cellCount.y );
    // Clamp at 0 if we underflowed but the buffer has never filled up yet
    // TODO Do we wanna initially fill the window from the top down or the bottom up?
    //if !sourceBuffer.linesFilled && absStartLineIdx > sourceBuffer.absoluteLineIdx
        //absStartLineIdx = 0;
    relStartLineIdx := absStartLineIdx & SourceBuffer.LinesMask;
    line := *sourceBuffer.lines[ relStartLineIdx ];

    dst := renderer.cells.data;
    for y: 0..renderer.cellCount.y - 1
    {
        lineLength := GetLineLength( <<line );

        for x: 0..renderer.cellCount.x - 1
        {
            defer dst += 1;

            dst.props.foregroundColor = fg;
            dst.props.backgroundColor = bg;
            dst.props.flags = 0;

            col := x;

            #if DebugDrawLineBufferValues
            {
                if col < LineValuesColOffset
                {
                    char := GetLineBufferCharAt( <<line, col );
                    dst.glyphIndex = GlyphIndexForChar( char, face );
                    dst.props.foregroundColor = PackColor( .{ 0.5, 0.5, 0.5 } );
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
                        dst.props.flags |= .Blinking;
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
            dst.props.foregroundColor = fg;
            dst.props.backgroundColor = bg;
            dst.props.flags = 0;

            glyph: *Glyph;
            if col == 0
                glyph = *face.glyphs[ #char ">" - 32 ];
            else if col == 1
                glyph = *face.glyphs[ #char " " - 32 ];
            else if col == command.count + 2
            {
                glyph = *face.glyphs[127 - 32];
                dst.props.flags |= .Blinking;
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

LayoutScreenBuffer :: ( sourceBuffer: SourceBuffer, lineOffset: s64, commandLine: CommandLine, face: *LoadedFace,
                        renderer: *RendererState )
{
    ClearScreenBuffer( renderer );

    // TODO Ensure the first line here starts *at or before* the first cell on the screen
    absStartLineIdx := GetFirstScreenLineAbsIndex( sourceBuffer.absoluteLineIdx, lineOffset, renderer.cellCount.y );
    // TODO Refterm does many more lines per pass here, I assume to try to account for arbitrary cursor jumps etc
    // but I'm unsure that's really necessary?
    lineCount := renderer.cellCount.y;

    cursor: CursorState;
    ClearCursor( *cursor );

    commandString := commandLine.input;

    // TODO Debug draw line info
    for l: 0 .. lineCount - 1
    {
        lineIdx := (absStartLineIdx + l) & SourceBuffer.LinesMask;
        line := *sourceBuffer.lines[ lineIdx ];

        // We need the cursor properties with which the line started to give an initial sensible value to our cursor
        // This is because we're merely displaying a small window of content, and the last cursor properties could have been
        // set many many lines back
        cursor.props = line.startingProps;
        // TODO Test huge lines straddling the end of the source buffer
        range := GetBufferRange( line, sourceBuffer );

        ComputeRenderedGlyphs( range, *cursor, face, renderer );
    }

    // Current commandline contents
    ComputeRenderedGlyphs( commandString, *cursor, face, renderer );

    // TODO Actual moveable cursor
    cell := GetCellAt( cursor, renderer );
    if cell
    {
        glyph := *face.glyphs[127 - 32];
        cell.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);
        cell.props = cursor.props;
        cell.props.flags |= .Blinking;
    }

    AdvanceRow( *cursor, renderer.cellCount );
    // Track where we should start when mapping cells
    renderer.firstRowY = cursor.y;
}

ComputeRenderedGlyphs :: ( range: $Range, cursor: *CursorState, face: *LoadedFace, renderer: *RendererState )
{
    while range.count > 0
    {
        c0 := PeekToken( range, 0 );

        if c0 == #char "\r"
        {
            ConsumeCount( *range, 1 );
            cursor.x = 0;
        }
        else if c0 == #char "\n"
        {
            ConsumeCount( *range, 1 );
            AdvanceRowAndClear( cursor, renderer );
        }
        // TODO Unicode
        else
        {
            // TODO Refterm wants to reposition the prompt line when the cursor jumps here
            // but our prompt is controlled by the shell, so I doubt we can do anything about that..
            // TODO Do we need to enable VT code support through some Win32 crap to receive VT codes from Windows apps?
            escape, cursorJumped := TryParseEscapeCode( *range, cursor );
            if !escape
            {
                codepoint := ConsumeToken( *range );

                cell := GetCellAt( cursor.*, renderer );
                if cell
                {
                    glyph: *Glyph;
                    if codepoint >= 32 && codepoint < 127
                    {
                        glyph = *face.glyphs[ codepoint - 32 ];
                    }
                    else
                    {
                        // TODO Unicode
                        glyph = *face.glyphs[127 - 32];
                    }

                    cell.glyphIndex = cast(u32)((glyph.index.y << 16) | glyph.index.x);
                    cell.props.foregroundColor = cursor.props.foregroundColor;
                    cell.props.backgroundColor = cursor.props.backgroundColor;
                    cell.props.flags = cursor.props.flags;
                }

                AdvanceColumn( cursor, lineWrap = true, renderer );
            }
        }
    }
}

TryParseEscapeCode :: ( range: *$Range, cursor: *CursorState ) -> success: bool, movedCursor: bool
{
    // TODO Some sequences dont start with '['
    if PeekToken( range.*, 0 ) != #char "\x1b" || PeekToken( range.*, 1 ) != #char "["
        return false, false;

    ConsumeCount( range, 2 );

    command: u8;
    params: [..] u64;
    params.allocator = temp;

    while range.count > 0
    {
        token := PeekToken( range.*, 0 );
        if IsDigit( token )
        {
            array_add( *params, ParseUnsignedInt( range ) );
            
            if PeekToken( range.*, 0 ) == #char ";"
                ConsumeCount( range, 1 );
        }
        else
        {
            command = ConsumeToken( range );
            break;
        }
    }

    movedCursor := false;
    if command ==
    {
        case #char "H";
        {
            if params.count != 2
                return false, false;

            cursor.x = cast(s32) (params[1] - 1);
            cursor.y = cast(s32) (params[0] - 1);
            movedCursor = true;
        }
        case #char "m";
        {
            if params.count < 1
                return false, false;

            if params[0] ==
            {
                case 0; ClearProps( *cursor.props );

                case 1; cursor.props.flags |= .Bold;
                case 2; cursor.props.flags |= .Dim;
                case 3; cursor.props.flags |= .Italic;
                case 4; cursor.props.flags |= .Underline;
                case 5; cursor.props.flags |= .Blinking;
                case 7; cursor.props.flags |= .ReverseVideo;
                case 8; cursor.props.flags |= .Invisible;
                case 9; cursor.props.flags |= .Strikethrough;

                case 38;
                {
                    if params[1] == 2
                        cursor.props.foregroundColor = PackColor( xx params[2], xx params[3], xx params[4] );
                    else
                        return false, false;
                }
                case 48;
                {
                    if params[1] == 2
                        cursor.props.backgroundColor = PackColor( xx params[2], xx params[3], xx params[4] );
                    else
                        return false, false;
                }

                case;
                    return false, false;
            }
        }
        case;
            return false, false;
    }

    return true, movedCursor;
}


Init :: ( buffer: *SourceBuffer )
{
    base: *void;
    // Ensure we can call this on already initialised data
    free( buffer.bytes.data );
    buffer.bytes, base = NewArray( SourceBuffer.MaxSize, u8 );
    assert( base == buffer.bytes.data );

    free( buffer.lines.data );
    buffer.lines, base = NewArray( SourceBuffer.MaxLines, Line );
    assert( base == buffer.lines.data );

    ClearCursor( *buffer.runningCursor );
    // Given how lines are currently parsed, the first line never gets the correct initial glyph props set, so set them here
    buffer.lines[0].startingProps = buffer.runningCursor.props;
}

GetCurLine :: ( buffer: *SourceBuffer ) -> *Line
{
    line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LinesMask ];
    return line;
}

GetLineLength :: ( line: Line ) -> s64
{
    result := line.absOnePastEndPos - line.absStartPos;
    return result;
}

GetBufferRange :: ( line: Line, buffer: SourceBuffer ) -> SourceBufferRange
{
    assert( line.absOnePastEndPos >= line.absStartPos );
    result: SourceBufferRange = ---;
    result.base  = buffer.bytes.data;
    result.absP  = line.absStartPos;
    result.count = line.absOnePastEndPos - line.absStartPos;
    return result;
}

UpdateCurLineEnd :: ( absP: s64, buffer: *SourceBuffer )
{
    line := *buffer.lines[ buffer.absoluteLineIdx & SourceBuffer.LinesMask ];
    line.absOnePastEndPos = absP;
}

GetFirstScreenLineAbsIndex :: ( absLineIdx: s64, lineOffset: s64, rendererRowCount: s64 ) -> s64
{
    return absLineIdx - lineOffset - rendererRowCount + 1;
}


GetCharAt :: ( buffer: SourceBuffer, line: Line, col: int ) -> u8
{
    relPos := (line.absStartPos + col) & SourceBuffer.SizeMask;
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

                value := line.absStartPos & SourceBuffer.SizeMask;
                // value := line.absStartPos;
                if col > MaxDigits
                {
                    col -= (MaxDigits + 1);
                    value = line.absOnePastEndPos & SourceBuffer.SizeMask;
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

PeekToken :: ( range: [] u8, offset: s64 ) -> u8
{
    result: u8;
    if offset < range.count
        result = range[offset];

    return result;
}

PeekToken :: ( range: SourceBufferRange, offset: s64 ) -> u8
{
    result: u8;
    if offset < range.count
        result = range.base[ (range.absP + offset) & SourceBuffer.SizeMask ];

    return result;
}

ConsumeToken :: ( range: *[] u8 ) -> u8
{
    result: u8;
    
    if range.count > 0
    {
        result = range.*[0];
        ConsumeCount( range, 1 );
    }
    return result;
}

ConsumeToken :: ( range: *SourceBufferRange ) -> u8
{
    result: u8;
    
    if range.count > 0
    {
        result = range.base[ range.absP & SourceBuffer.SizeMask ];
        ConsumeCount( range, 1 );
    }
    return result;
}

ConsumeCount :: ( range: *[] u8, count: s64 )
{
    if count > range.count
        count = range.count;

    range.data += count;
    range.count -= count;
}

ConsumeCount :: ( range: *SourceBufferRange, count: s64 )
{
    if count > range.count
        count = range.count;

    range.absP += count;
    range.count -= count;
}

IsDigit :: ( char: u8 ) -> bool
{
    return char >= #char "0" && char <= #char "9";
}

ParseUnsignedInt :: ( range: *$Range ) -> u64
{
    result: u64 = 0;
    while IsDigit( PeekToken( range.*, 0 ) )
    {
        token := ConsumeToken( range );
        result = result * 10 + (token - #char "0");
    }
    return result;
}


ClearCursor :: ( cursor: *CursorState )
{
    cursor.x = 0;
    cursor.y = 0;
    ClearProps( *cursor.props );
}

AdvanceRow :: ( cursor: *CursorState, screenBounds: v2s )
{
    cursor.x = 0;
    cursor.y += 1;
    // Allow the cursor to wrap around the bottom of the screen, then offset the rows back when GPU mapping the cell buffer
    // Makes dealing with horizontal line wrapping trivial
    if cursor.y >= screenBounds.y
        cursor.y = 0;
}

AdvanceRowAndClear :: ( cursor: *CursorState, renderer: *RendererState )
{
    AdvanceRow( cursor, renderer.cellCount );
    ClearLine( cursor.y, renderer );
}

AdvanceColumn :: ( cursor: *CursorState, lineWrap: bool, renderer: *RendererState )
{
    cursor.x += 1;
    if lineWrap && cursor.x >= renderer.cellCount.x
        AdvanceRowAndClear( cursor, renderer );
}

ClearProps :: ( props: *GlyphProps )
{
    // TODO Color schemes etc
    props.foregroundColor = PackColor( .{ 1, 1, 1 } );
    props.backgroundColor = PackColor( .{ 0.15, 0.15, 0.2 } );
    props.flags = 0;
}

ClearCells :: ( cells : [] RendererCell )
{
    // TODO Color schemes etc
    bg := PackColor( .{ 0.15, 0.15, 0.2 } );
    for * c : cells
    {
        c.glyphIndex = 0;
        c.props.foregroundColor = bg;
        c.props.backgroundColor = bg;
        c.props.flags = 0;
    }
}

ClearLine :: ( y: s32, renderer: *RendererState )
{
    range: [] RendererCell = .{ renderer.cellCount.x, *renderer.cells[ y * renderer.cellCount.x ] };
    ClearCells( range );
}

ClearScreenBuffer :: ( renderer: *RendererState )
{
    ClearCells( renderer.cells );
}

GetCellAt :: ( cursor: CursorState, renderer: *RendererState ) -> *RendererCell
{
    result: *RendererCell = null;
    if cursor.x >= 0 && cursor.y >= 0 && cursor.x < renderer.cellCount.x && cursor.y < renderer.cellCount.y
        result = *renderer.cells[ cursor.y * renderer.cellCount.x + cursor.x ];

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

Shutdown :: ( process: *Process )
{
    kill_process( process );
    deinit( process );
}
