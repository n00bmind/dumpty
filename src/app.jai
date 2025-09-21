#import "Basic";

#program_export
AppInit :: ( memory: *AppMemory, renderer: *RendererState )
{
    if !memory.initialized
    {
        Init( memory, renderer );
        memory.initialized = true;

        appState := cast(*AppState) memory.appState;
        appState.shell = CreateShell();
        // appState.shell = New( CmdPtyShellAsync );

        ret := appState.shell.startProc( appState.shell );
        assert( ret, "Failed to start shell" );
    }
    else
    {
        // Anything we need to do upon being reloaded would go here..
    }
}

#program_export
AppShutdown :: ( memory: *AppMemory )
{
    appState := cast(*AppState) memory.appState;

    appState.shell.shutdownProc( appState.shell );
    Shutdown( *appState.builtinProcess );
}

#program_export
AppWaitForInput :: ( memory: *AppMemory )
{
    appState := cast(*AppState) memory.appState;

    nowMs := cast(int)( seconds_since_init() * 1000 );
    // Compute how many millis to wait until the next cursor blink toggling
    remainder := (nowMs / BlinkTimeMillis + 1) * BlinkTimeMillis - nowMs;

    WaitForAllOpenHandles( appState, remainder );
}

// TODO Make an @implements(UpdateAndRenderFunc) note that's parsed by the metaprogram which will then
// #assert( type_of(UpdateAndRender) == UpdateAndRenderFunc );
#program_export
AppUpdateAndRender :: ( input: AppInput, memory: *AppMemory, renderer: *RendererState )
{
    appState := cast(*AppState) memory.appState;
    cmdline := *appState.commandLine;

    // Process this frame's window events
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
                    // appState.shell.writeProc( appState.shell, "\x08" );
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
                        AppendToSourceBuffer( *appState.sourceBuffer,
                                              tprint( "%\n", cast(string) cmdline.input ),
                                              renderer );
                        if !ExecuteBuiltinCommand( *appState.builtinProcess, cmdline.input,
                                                   appState, renderer )
                        {
                            AppendToSourceBuffer( *appState.sourceBuffer,
                                                  "<<dumpty>> Internal error executing builtin command\n",
                                                  renderer );
                        }
                    }
                    else
                    {
                        // appState.shell.writeProc( appState.shell, "\n" );
                        //
                        // TODO nested WSL doesnt like this. We probably need to somehow listen to input/output console mode changes..
                        // Either that or we're gonna need to customize this per shell as well..
                        push( *cmdline.input, "\r" );
                        push( *cmdline.input, "\n" );
                        if !appState.shell.writeProc( appState.shell, xx cmdline.input )
                            AppendToSourceBuffer( *appState.sourceBuffer,
                                                  "<<dumpty>> Internal error executing shell command\n",
                                                  renderer );
                    }

                    cmdline.input.count = 0;
                }

                case .F10;
                {
                    renderer.debugDrawAtlas = !renderer.debugDrawAtlas;
                }
            }

            case .TEXT_INPUT;
            {
                value := it.utf32;

                // The theoretical maximum for UTF8 is 6 bytes
                str := alloc_string( 6 ,, temp );
                character_utf32_to_utf8( value, *str );
                // appState.shell.writeProc( appState.shell, str );
                push( *cmdline.input, str );
                
                UpdateHistoryEntry( cmdline );
                appState.lastInputSeconds = seconds_since_init();
            }
        }
    }

    // Gather output from the builtin and / or shell processes
    if IsRunning( appState.builtinProcess )
    {
        absStartP := appState.sourceBuffer.absoluteHeadPos;

        result, totalBytes := ReadProcessOutput( *appState.builtinProcess, *appState.sourceBuffer );

        if totalBytes > 0
            ParseLines( *appState.sourceBuffer, absStartP, totalBytes, renderer );

        if result.type == .EXITED
        {
            if result.exit_code
                print( "<<dumpty>> Builtin process exited with error code %.\n", result.exit_code );
            deinit( *appState.builtinProcess );

            appState.shell.writeProc( appState.shell, "\n" );
        }
        else if result.type == .FAILED_TO_LAUNCH
        {
            print( "<<dumpty>> Builtin process failed to launch (%).\n", result.exit_code );
            deinit( *appState.builtinProcess );

            appState.shell.writeProc( appState.shell, "\n" );
        }
    }
    // TODO Do we really need to call this at all?
    // if IsRunning( appState.shell )
    {
        absStartP := appState.sourceBuffer.absoluteHeadPos;

        result, totalBytes := appState.shell.readProc( appState.shell, *appState.sourceBuffer );

        if totalBytes > 0
            ParseLines( *appState.sourceBuffer, absStartP, totalBytes, renderer );

        if result.type != .STILL_RUNNING
        {
            print( "Shell process died (%).\n", result );

            // TODO Restart? Exit app?
            // Restart( *appState.shell );
            assert( false );
        }
    }

    nowMs := cast(int)( seconds_since_init() * 1000 );
    blink := (nowMs / BlinkTimeMillis) & 1;
    renderer.blinkModulateColor = cast(u32) ifx blink 0xFFFFFFFF else 0xFF111111;

     // TODO Figure out if we were woken up by the timer last time
     // and dont re-layout the view in that case
    #if false
    {
        UpdateRendererCells( renderer, appState.sourceBuffer, appState.lineOffset, <<cmdline );
    }
    else
    {
        LayoutScreenBuffer( appState.sourceBuffer, appState.lineOffset, cmdline.*, *appState.glyphTable, renderer );
    }
}


#scope_module

#import "String";

Shell :: struct
{
    // TODO Would like all these to take a concrete *subtype* of Shell instead, but unsure how to do this
    startProc: #type ( base: *Shell ) -> bool;
    shutdownProc: #type ( base: *Shell );
    writeProc: #type ( base: *Shell, str: string ) -> bool;
    readProc: #type ( base: *Shell, sourceBuffer: *SourceBuffer ) -> Process_Result, s64;
    getWaitableHandlesProc: #type ( base: *Shell, handles: [] HANDLE, handleCount: *u32 );
}

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

AppendToSourceBuffer :: ( buffer: *SourceBuffer, data: string, renderer: *RendererState )
{
    assert( data.count <= buffer.bytes.count );

    relPos := buffer.absoluteHeadPos & SourceBuffer.SizeMask;
    available := buffer.bytes.count - relPos;

    // Do we need to split the copy? (if we're approaching the end of the buffer)
    if( data.count < available )
    {
        memcpy( buffer.bytes.data + relPos, data.data, data.count );
        ParseLines( buffer, buffer.absoluteHeadPos, data.count, renderer );
    }
    else
    {
        memcpy( buffer.bytes.data + relPos, data.data, available );
        memcpy( buffer.bytes.data, data.data + available, data.count - available );

        ParseLines( buffer, buffer.absoluteHeadPos, available, renderer );
        ParseLines( buffer, buffer.absoluteHeadPos + available, data.count - available,
                    renderer );
    }

    buffer.absoluteHeadPos += data.count;
    if buffer.absoluteHeadPos >= buffer.bytes.count
        buffer.bytesFilled = true;
}


Reset :: ( process: *Process )
{
    deinit( process );
    Init( process );
}

Init :: ( process: *Process )
{
    ini :: initializer_of(Process);
    inline ini( process );

    #if OS == .WINDOWS
        process.info.hProcess = INVALID_HANDLE_VALUE;
    else
        assert( false, "Implement me" );
}

Shutdown :: ( process: *Process )
{
    if IsRunning( process.* )
    {
        kill_process( process );
        deinit( process );
    }
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
#load "shell_cmd_pty.jai";
#load "shell_cmd_pty_async.jai";
#load "glyph_cache.jai";

// TODO May want to call PrepareGlyphTiles indirectly so we can remove this coupling
#import "Window_Creation";
#load "opengl.jai";


BlinkTimeMillis :: 750;

#if OS == .WINDOWS
{
    #import "Windows";

    WAIT_ABANDONED_0 :: 0x00000080;

    kernel32 :: #system_library "kernel32";
    user32   :: #system_library "user32";
    MsgWaitForMultipleObjects :: ( nCount: DWORD, lpHandles: *HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD ) -> DWORD #foreign user32;

    QS_KEY            :: 0x0001;
    QS_MOUSEMOVE      :: 0x0002;
    QS_MOUSEBUTTON    :: 0x0004;
    QS_MOUSE          :: (QS_MOUSEMOVE | QS_MOUSEBUTTON);
    QS_POSTMESSAGE    :: 0x0008;
    QS_TIMER          :: 0x0010;
    QS_PAINT          :: 0x0020;
    QS_SENDMESSAGE    :: 0x0040;
    QS_HOTKEY         :: 0x0080;
    QS_ALLPOSTMESSAGE :: 0x0100;
    QS_RAWINPUT       :: 0x0400;
    QS_TOUCH          :: 0x0800;
    QS_POINTER        :: 0x1000;
    QS_INPUT          :: (QS_MOUSE     | QS_KEY         | QS_RAWINPUT | QS_TOUCH | QS_POINTER);
    QS_ALLEVENTS      :: (QS_INPUT     | QS_POSTMESSAGE | QS_TIMER    | QS_PAINT | QS_HOTKEY);
    QS_ALLINPUT       :: (QS_ALLEVENTS | QS_SENDMESSAGE);
}


AppState :: struct
{
    mainArena: MemoryArena;

    commandLine: CommandLine;
    cursor: CursorState;

    shell: *Shell;
    builtinProcess: Process;

    sourceBuffer: SourceBuffer;
    lineOffset: s64;

    glyphTable: GlyphTable;

    lastInputSeconds: float64;
}

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


Init :: ( memory: *AppMemory, renderer: *RendererState ) -> *AppState
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

    slotsPerRow := renderer.loadedFont.atlasSizeTexels / renderer.loadedFont.advance;
    rowCount := renderer.loadedFont.atlasSizeTexels / renderer.loadedFont.lineHeight;
    freeSlotCount := rowCount * slotsPerRow - ReservedSlotCount;
    InitGlyphCache( *appState.glyphTable, ReservedSlotCount, freeSlotCount, slotsPerRow );

    Init( *appState.builtinProcess );

    renderer.palette = *DefaultPalette;

    return appState;
}

ParseLines :: ( buffer: *SourceBuffer, absStartPos: s64, sizeBytes: s64,
                renderer: *RendererState )
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
            // Ensure really long lines dont cause too many issues
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
                // TODO Do we need to create a faster / lighter version of this that's only concerned with cursor props?
                escape, cursorJumped := TryParseEscapeCode( *range, *buffer.runningCursor, renderer, absP );
                if escape
                {
                    // TODO This doesnt really *require* us to break the line does it?
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


DebugDrawLineBufferValues :: false;
DebugLineValuesReservedCols :: 17;

// TODO Delete
UpdateRendererCells :: ( renderer: *RendererState, sourceBuffer: SourceBuffer, lineOffset: s64, commandLine: CommandLine )
{
    LineValuesColOffset :: #ifx DebugDrawLineBufferValues then DebugLineValuesReservedCols else 0;

    font := renderer.loadedFont;
    fg := PackColor( v3.{ 1, 1, 1 } );
    bg := PackColor( v3.{ 0.15, 0.15, 0.2 } );

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
                    dst.glyphIndex = GlyphIndexForChar( char, font );
                    dst.props.foregroundColor = PackColor( v3.{ 0.5, 0.5, 0.5 } );
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
                        slot := *font.directGlyphs[ char - 32 ];
                        dst.glyphIndex = PackGlyphIndex( slot );
                        continue;
                    }
                    // FIXME Actual cursor pos
                    else if col >= cmdLineStartPos && col == cmdLineStartPos + commandString.count
                    {
                        slot := *font.directGlyphs[127 - 32];
                        dst.glyphIndex = PackGlyphIndex( slot );
                        dst.props.flags |= .Blinking;
                        continue;
                    }
                }

                // Glyph 0,0 is always the empty/space glyph
                dst.glyphIndex = 0;
                continue;
            }

            char := GetCharAt( sourceBuffer, <<line, col );
            dst.glyphIndex = GlyphIndexForChar( char, font );
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

            slot: GlyphSlot;
            if col == 0
                slot = *font.directGlyphs[ #char ">" - 32 ];
            else if col == 1
                slot = *font.directGlyphs[ #char " " - 32 ];
            else if col == command.count + 2
            {
                slot = *font.directGlyphs[127 - 32];
                dst.props.flags |= .Blinking;
            }
            else if col > command.count + 2
            {
                slot = *font.directGlyphs[0];
            }
            else
            {
                char := command[ col - 2 ];
                if char >= 32 && char <= 127
                {
                    slot = *font.directGlyphs[ char - 32 ];
                }
                else
                {
                    // TODO Unknown symbol should be separate from the cursor glyph
                    slot = *font.directGlyphs[127 - 32];
                }
            }
            dst.glyphIndex = PackGlyphIndex( slot );

            dst += 1;
        }
    }
}

LayoutScreenBuffer :: ( sourceBuffer: SourceBuffer, lineOffset: s64, commandLine: CommandLine, glyphTable: *GlyphTable,
                        renderer: *RendererState )
{
    ClearScreenBuffer( renderer );

    // Ensure we start at a line that starts *at or before* the first cell on the screen
    // i.e. if every line fits the screen width (or wrapping is disabled) we layout cellCount.y rows, otherwise we'll do more
    // TODO This is kinda wasteful when we have very long lines, would be preferable to count how many glyphs in each line?
    // NOTE Overflowing the bottom of the screen is not a problem, at the very end we note which screen row we ended up in,
    // so that the renderer knows to horizontally split the buffer in two at that row and render the two halves appropriately.
    absStartLineIdx := GetFirstScreenLineAbsIndex( sourceBuffer.absoluteLineIdx, lineOffset, renderer.cellCount.y );
    // TODO Refterm does many more lines per pass here, I assume to try to account for arbitrary cursor jumps etc
    // but I'm unsure that's really necessary?
    lineCount := renderer.cellCount.y;

    cursor: CursorState;
    // TODO 
    #if DebugDrawLineBufferValues
        cursor.debugLeftMargin = 5;
    ClearCursor( *cursor );

    commandString := commandLine.input;

    for l: 0 .. lineCount - 1
    {
        lineIdx := (absStartLineIdx + l) & SourceBuffer.LinesMask;
        line := *sourceBuffer.lines[ lineIdx ];

        // TODO Test huge lines straddling the end of the source buffer
        range := GetBufferRange( line, sourceBuffer );
        // If visualising the line buffer, prefix non empty lines
        // TODO Debug draw line info
        #if DebugDrawLineBufferValues
            if range.count
            {
                lineInfoString := " ### ";
                ComputeRenderedGlyphs( cast([] u8) lineInfoString, *cursor, glyphTable, renderer );
            }

        // We need the cursor properties with which the line started to give an initial sensible value to our cursor
        // This is because we're merely displaying a small window of content, and the last cursor properties could have been
        // set many many lines back
        cursor.props = line.startingProps;
        ComputeRenderedGlyphs( range, *cursor, glyphTable, renderer );
    }

    // Current commandline contents
    ComputeRenderedGlyphs( commandString, *cursor, glyphTable, renderer );

    // TODO Actual moveable cursor?
    cell := GetCellAt( cursor, renderer );
    if cell
    {
        slot := *renderer.loadedFont.directGlyphs[127 - 32];
        cell.glyphIndex = PackGlyphIndex( slot );
        cell.props = cursor.props;
        cell.props.flags |= .Blinking;
    }

    AdvanceRow( *cursor, renderer.cellCount );
    // Track where we should start when mapping cells
    renderer.firstRowY = cursor.y;
}

ComputeRenderedGlyphs :: ( range: $Range, cursor: *CursorState, glyphTable: *GlyphTable, renderer: *RendererState )
{
    font := renderer.loadedFont;

    while range.count > 0
    {
        c0 := PeekToken( range, 0 );

        if c0 ==
        {
            case #char "\r";
            {
                ConsumeCount( *range, 1 );
                RewindRow( cursor );
            }
            case #char "\n";
            {
                ConsumeCount( *range, 1 );
                AdvanceRowAndClear( cursor, renderer );
            }
            case #char "\x08";  // Backspace
            {
                ConsumeCount( *range, 1 );
                RewindColumn( cursor );
            }
            case;
            {
                // TODO Refterm wants to reposition the prompt line when the cursor jumps here
                // but our prompt is controlled by the shell, so I doubt we can do anything about that..
                escape, cursorJumped := TryParseEscapeCode( *range, cursor, renderer, -1 );
                if !escape
                {
                    cell := GetCellAt( cursor.*, renderer );
                    if cell
                    {
                        slot: GlyphSlot;
                        if c0 >= 32 && c0 < 127
                        {
                            slot = font.directGlyphs[ c0 - 32 ];
                            ConsumeCount( *range, 1 );
                        }
                        else
                        {
                            // TODO Shaping, font fallback, etc

                            str := GetContiguousView( range, 6 );
                            codepoint, advance, result := character_utf8_to_utf32( str.data, str.count );
                            str.count = advance;

                            entry := FindOrAddGlyphEntry( codepoint, glyphTable );
                            if entry.state != .Rasterised
                            {
                                PrepareGlyphTiles( codepoint, entry.slot, renderer.loadedFont );
                                UpdateGlyphEntry( entry.key, .Rasterised, 1, 1, glyphTable );

                                print( "UTF8: % -> codepoint % (%) -> slot %,%\n", str,
                                       formatInt( codepoint, base = 16 ), result, entry.slot.x, entry.slot.y );
                            }
                            slot = entry.slot;

                            ConsumeCount( *range, advance );
                        }

                        cell.glyphIndex = PackGlyphIndex( slot );
                        cell.props.foregroundColor = cursor.props.foregroundColor;
                        cell.props.backgroundColor = cursor.props.backgroundColor;
                        cell.props.flags = cursor.props.flags;
                    }

                    // TODO Are we ever gonna support disabling linewrapping?
                    // TODO When not linewrapping, we should detect when we go off-bounds here and just skip a full line
                    AdvanceColumn( cursor, lineWrap = true, renderer );
                }
            }
        }
    }
}

// As seen on Wikipedia..
// TODO Colour palettes .. https://iterm2colorschemes.com/
BuildDefaultPalette :: () -> string
{
    builder: String_Builder;

    append( *builder, ".[\n" );
    for c: 0..15
        print_to_builder( *builder, "    DefaultSystemColours[ % ],\n", c );
    // Colors 16-231 are a 6x6x6 color cube
    for r: 0..5
    {
        for g: 0..5
        {
            for b: 0..5
            {
                print_to_builder( *builder, "    .{ %, %, % },\n",
                                  ifx r then r * 40 + 55 else 0,
                                  ifx g then g * 40 + 55 else 0,
                                  ifx b then b * 40 + 55 else 0 );
            }
        }
    }
    // Colors 232-255 are a grayscale ramp, intentionally leaving out black and white
    for c: 0..23
    {
        gr := c * 10 + 8;
        print_to_builder( *builder, "    .{ %, %, % },\n", gr, gr, gr );
    }
    append( *builder, "];\n" );

    return builder_to_string( *builder );
}

DefaultPalette : [256] c3 : #insert #run BuildDefaultPalette();
DefaultSystemColours : [16] c3 :
.[
    .{ 0,    0,    0    }, // black
    .{ 0x80, 0,    0    }, // red
    .{ 0,    0x80, 0    }, // green
    .{ 0x80, 0x80, 0    }, // yellow
    .{ 0,    0,    0x80 }, // blue
    .{ 0x80, 0,    0x80 }, // magenta
    .{ 0,    0x80, 0x80 }, // cyan
    .{ 0xc0, 0xc0, 0xc0 }, // white

    .{ 0x80, 0x80, 0x80 }, // black
    .{ 0xff, 0,    0    }, // red
    .{ 0,    0xff, 0    }, // green
    .{ 0xff, 0xff, 0    }, // yellow
    .{ 0,    0,    0xff }, // blue
    .{ 0xff, 0,    0xff }, // magenta
    .{ 0,    0xff, 0xff }, // cyan
    .{ 0xff, 0xff, 0xff }, // white
];


globalECLocations: Table( s64, bool );

// TODO Do we want to make 2 versions of this to speed up ingestion?
// TODO In any case, we'll need this to be more table-driven to remove as many branches as possible
// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
// https://www.xfree86.org/4.8.0/ctlseqs.html
// https://en.wikipedia.org/wiki/ANSI_escape_code
// https://ghostty.org/docs/vt/concepts/sequences
TryParseEscapeCode :: ( range: *$RangeT, cursor: *CursorState, renderer: *RendererState, absP: s64 = -1 )
    -> success: bool, movedCursor: bool
{
    // TODO We wouldnt even want to make the call into here if this doesnt hold
    if PeekToken( range.*, 0 ) != #char "\x1b" 
        return false, false;

    startRange := range.*;
    parsed := false;

    defer
    {
        #if BUILD_CONFIG != .Release 
            if !parsed 
            {
                range.* = startRange;

                #if RangeT != SourceBufferRange
                    if absP != -1 && !table_contains( *globalECLocations, absP )
                    {
                        log( "Unknown EC starting at %: %..\n", absP,
                            GetContiguousView( startRange, 8 ) );
                        table_add( *globalECLocations, absP, true );
                    }
            }
    }

    ConsumeCount( range, 1 );
    if PeekToken( range.*, 0 ) == #char "["
        // TODO Flag this?
        ConsumeCount( range, 1 );
    else if PeekToken( range.*, 0 ) == #char "]"
    {
        ConsumeCount( range, 1 );
        result := ParseOSC( range );

        parsed = true;
        return result, false;
    }


    command: u8;
    params: [8] s32;

    paramCount := 0;
    while range.count > 0
    {
        token := PeekToken( range.*, 0 );
        // NOTE Some codes accept symbol params here (screen / private modes)
        if IsDigitOrKnownSymbol( token ) && paramCount < params.count
        {
            params[ paramCount ]
                = ifx IsDigit( token ) ParseInt( range ) else ConsumeToken( range );
            paramCount += 1;
            
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
        //// Cursor movement
        // TODO Wrapping for all these?
        case #char "H"; #through;
        case #char "f";
        {
            cursor.x = ifx paramCount then (params[1] - 1) else 0;
            cursor.y = ifx paramCount then (params[0] - 1) else 0;
            movedCursor = true;
        }
        case #char "A";
            cursor.y -= ifx paramCount then params[0] else 1;
            movedCursor = true;
        case #char "B";
            cursor.y += ifx paramCount then params[0] else 1;
            movedCursor = true;
        // TODO Do we care about breaking the line for the ones that only change the col?
        case #char "C";
            cursor.x += ifx paramCount then params[0] else 1;
        case #char "D";
            cursor.x -= ifx paramCount then params[0] else 1;
        case #char "E";
        {
            cursor.x = 0;
            cursor.y += ifx paramCount then params[0] else 1;
            movedCursor = true;
        }
        case #char "F";
        {
            cursor.x = 0;
            cursor.y -= ifx paramCount then params[0] else 1;
            movedCursor = true;
        }
        case #char "G";
            cursor.x = ifx paramCount then (params[1] - 1) else 0;
        case #char "n";
        {
            // if params[0] == #char "6"
            // TODO This is supposed to write the current cursor pos as 'ESC[#;#R'
        }
        case #char "M";   // NOTE No CSI
        {
            cursor.y -= 1;
            movedCursor = true;
            // TODO This is supposed to "scroll if needed"
        }

        case #char "7"; #through;   // NOTE No CSI
        case #char "s";
        {
            renderer.savedCursor.x = cursor.x;
            renderer.savedCursor.y = cursor.y;
        }
        case #char "8"; #through;   // NOTE No CSI
        case #char "u";
        {
            cursor.x = renderer.savedCursor.x;
            cursor.y = renderer.savedCursor.y;
            movedCursor = true;
        }


        //// Erasing
        case #char "J";
        {
            if params[0] ==
            {
                case 0;
                {
                    curCellIdx := cursor.y * renderer.cellCount.x + cursor.x;
                    totalCellCount := renderer.cellCount.x * renderer.cellCount.y;

                    cellRange: [] RendererCell = .{ totalCellCount - curCellIdx,
                                                *renderer.cells[ curCellIdx ] };
                    ClearCells( cellRange );
                }
                case 1;
                {
                    curCellIdx := cursor.y * renderer.cellCount.x + cursor.x;

                    cellRange: [] RendererCell = .{ curCellIdx,
                                                *renderer.cells[ 0 ] };
                    ClearCells( cellRange );
                }
                case 2;
                    ClearScreenBuffer( renderer );
                // case 3;
                    // "Erase saved lines" ..
            }
        }
        case #char "K";
        {
            if params[0] ==
            {
                case 0;
                {
                    curCellIdx := cursor.y * renderer.cellCount.x + cursor.x;
                    cellCount := renderer.cellCount.x - cursor.x;

                    cellRange: [] RendererCell = .{ cellCount,
                                                *renderer.cells[ curCellIdx ] };
                    ClearCells( cellRange );
                }
                case 1;
                {
                    curCellIdx := cursor.y * renderer.cellCount.x + cursor.x;

                    cellRange: [] RendererCell = .{ cursor.x,
                                                *renderer.cells[ curCellIdx - cursor.x ] };
                    ClearCells( cellRange );
                }
                case 2;
                    ClearLine( cursor.y, renderer );
            }
        }
        case #char "X";
        {
            curCellIdx := cursor.y * renderer.cellCount.x + cursor.x;

            cellRange: [] RendererCell = .{ params[0],
                                        *renderer.cells[ curCellIdx ] };
            ClearCells( cellRange );
        }


        //// Colors / graphics mode
        case #char "m";
        {
            // TODO Apparently no args should be interpreted as '0' (clear props)?
            if paramCount == 0
            {
                params[0] = 0;
                paramCount += 1;
            }

            p := params.data;
            pEnd := params.data + paramCount;
            while p < pEnd 
            {
                if p[0] ==
                {
                    case 0; ClearProps( *cursor.props );

                    // TODO Implement all these
                    case 1; cursor.props.flags |= .Bold;
                    case 2; cursor.props.flags |= .Dim;
                    case 3; cursor.props.flags |= .Italic;
                    case 4; cursor.props.flags |= .Underline;
                    case 5; cursor.props.flags |= .Blinking;
                    case 7; cursor.props.flags |= .ReverseVideo;
                    case 8; cursor.props.flags |= .Invisible;
                    case 9; cursor.props.flags |= .Strikethrough;

                    case 22; cursor.props.flags &= ~(.Bold | .Dim);
                    case 23; cursor.props.flags &= ~.Italic;
                    case 24; cursor.props.flags &= ~.Underline;
                    case 25; cursor.props.flags &= ~.Blinking;
                    case 27; cursor.props.flags &= ~.ReverseVideo;
                    case 28; cursor.props.flags &= ~.Invisible;
                    case 29; cursor.props.flags &= ~.Strikethrough;

                     // TODO All colous here should probably be pre-packed
                    case 30; #through;
                    case 31; #through;
                    case 32; #through;
                    case 33; #through;
                    case 34; #through;
                    case 35; #through;
                    case 36; #through;
                    case 37;
                        offset := ifx cursor.props.flags & .Bold then 8 else 0;
                        cursor.props.foregroundColor
                            = PackColor( renderer.palette.*[ p[0] - 30 + offset ] );
                    case 38;
                    {
                        if p[1] == 2
                        {
                            cursor.props.foregroundColor = PackColor( xx p[2], xx p[3], xx p[4] );
                            p += 4;
                        }
                        else if p[1] == 5
                        {
                            cursor.props.foregroundColor = PackColor( renderer.palette.*[ p[2] ] );
                            p += 2;
                        }
                        else
                            return false, false;
                    }
                    case 39;
                        cursor.props.foregroundColor = PackColor( renderer.palette.*[7] );

                    case 40; #through;
                    case 41; #through;
                    case 42; #through;
                    case 43; #through;
                    case 44; #through;
                    case 45; #through;
                    case 46; #through;
                    case 47;
                        offset := ifx cursor.props.flags & .Bold then 8 else 0;
                        cursor.props.backgroundColor
                            = PackColor( renderer.palette.*[ p[0] - 40 + offset ] );
                    case 48;
                    {
                        if p[1] == 2
                        {
                            cursor.props.backgroundColor
                                = PackColor( xx p[2], xx p[3], xx p[4] );
                            p += 4;
                        }
                        else if p[1] == 5
                        {
                            cursor.props.backgroundColor
                                = PackColor( renderer.palette.*[ p[2] ] );
                            p += 2;
                        }
                        else
                            return false, false;
                    }
                    case 49;
                        cursor.props.backgroundColor = PackColor( renderer.palette.*[0] );

                    case 90; #through;
                    case 91; #through;
                    case 92; #through;
                    case 93; #through;
                    case 94; #through;
                    case 95; #through;
                    case 96; #through;
                    case 97;
                        cursor.props.foregroundColor = PackColor( renderer.palette.*[ p[0] - 90 + 8 ] );

                    case 100; #through;
                    case 101; #through;
                    case 102; #through;
                    case 103; #through;
                    case 104; #through;
                    case 105; #through;
                    case 106; #through;
                    case 107;
                        cursor.props.backgroundColor = PackColor( renderer.palette.*[ p[0] - 100 + 8 ] );

                    case;
                         // TODO Should we just ignore (+log) instead?
                        if !parsed
                            return false, false;
                }

                p += 1;
                parsed = true;
            }
        }

         // TODO Private modes ('?')
        // case #char "l";
        // case #char "h";
        case;
            return false, false;
    }

    parsed = true;
    return parsed, movedCursor;
}

ParseOSC :: ( range: *$RangeT ) -> bool
{
    command := -1;
    payload: string = xx GetContiguousView( range.*, 0 );

    extraAdvance := 0;
    startCount := range.count;
    while range.count > 0 && startCount - range.count < 256
    {
        if range.count == startCount && IsDigit( PeekToken( range.*, 0 ) )
        {
            command = ParseInt( range );
            if PeekToken( range.*, 0 ) == #char ";"
                ConsumeCount( range, 1 );

            payload = xx GetContiguousView( range.*, 0 );
            startCount = range.count;
        }

        token := PeekToken( range.*, 0 );
        if token == 0x7
        {
            extraAdvance = 1;
            break;
        }
        else if token == 0x1b && PeekToken( range.*, 1 ) == #char "\\"
        {
            extraAdvance = 2;
            break;
        }
        // TODO Faster!
        ConsumeCount( range, 1 );
    }

    payload.count = startCount - range.count;
    ConsumeCount( range, extraAdvance );

     // TODO Implement any of these?
    return true;
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

GlyphIndexForChar :: ( char: u8, font: *LoadedFont ) -> u32
{
    result: u32;
    if char >= 32 && char < 127
    {
        slot := font.directGlyphs[ char - 32 ];
        result = cast(u32)((slot.y << 16) | slot.x);
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

GetContiguousView :: ( range: [] u8, count: s64 ) -> [] u8
{
    return .{ Min( count, range.count ), range.data };
}

// Returns a temp copy if the SourceBufferRange cannot fit 'count' contiguous bytes
GetContiguousView :: ( range: SourceBufferRange, count: s64 ) -> [] u8
{
    if count > range.count
        count = range.count;

    relP := range.absP & SourceBuffer.SizeMask;
    remaining := SourceBuffer.MaxSize - relP;

    if count > remaining
    {
        result := NewArray( count, u8,, temp );
        memcpy( result.data, range.base + relP, remaining );
        memcpy( result.data + remaining, range.base, count - remaining );
        return result;
    }
    else
    {
        return .{ count, range.base + relP };
    }
}


IsDigit :: inline ( c: u8 ) -> bool
{
    return c >= #char "0" && c <= #char "9";
}

IsDigitOrKnownSymbol :: inline ( c: u8 ) -> bool
{
    return IsDigit( c ) || c == #char "=" || c == #char "?";
}

ParseInt :: ( range: *$Range ) -> s32
{
    result: s32 = 0;
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

RewindRow :: ( cursor: *CursorState )
{
    cursor.x = cursor.debugLeftMargin;
}

AdvanceColumn :: ( cursor: *CursorState, lineWrap: bool, renderer: *RendererState )
{
    cursor.x += 1;
    if lineWrap && cursor.x >= renderer.cellCount.x
    {
        AdvanceRowAndClear( cursor, renderer );
        cursor.x += cursor.debugLeftMargin;
    }
}

RewindColumn :: ( cursor: *CursorState )
{
    // TODO Is there any scenario where we want to allow this to ever go back a row?
    if cursor.x > cursor.debugLeftMargin
        cursor.x -= 1;
}

ClearProps :: ( props: *GlyphProps )
{
    // TODO Color schemes etc
    props.foregroundColor = PackColor( v3.{ 1, 1, 1 } );
    props.backgroundColor = PackColor( v3.{ 0.15, 0.15, 0.2 } );
    props.flags = 0;
}

ClearCells :: ( cells : [] RendererCell )
{
    // TODO Color schemes etc
    bg := PackColor( v3.{ 0.15, 0.15, 0.2 } );
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
    range: [] RendererCell = .{ renderer.cellCount.x,
                                *renderer.cells[ y * renderer.cellCount.x ] };
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


CreateShell :: () -> *Shell
{
    // TODO This would in principle return whatever shell was saved in the prefs etc
    result := New( CmdShell );
    return result;
}

Restart :: ( shell: *Shell ) -> bool
{
    shell.shutdownProc( shell );
    return shell.startProc( shell );
}

ExecuteBuiltinCommand :: ( process: *Process, command: [] u8, appState: *AppState,
                           renderer: *RendererState ) -> bool
{
    Reset( *appState.builtinProcess );

    // Extract command
    found, cmd, args := split_from_left( xx command, #char " " );

    // TODO builtins table
    if cmd == "#run"
    {
        cmdArgs := break_command_into_strings( args );
        success := create_process( process, ..cmdArgs,
                                   working_directory = get_working_directory(),
                                   capture_and_return_output = true,
                                   arg_quoting = Process_Argument_Quoting.NEVER_QUOTE );

        // TODO Diagnostics
        return success;
    }
    else
    {
        AppendToSourceBuffer( *appState.sourceBuffer,
                              tprint( "<<dumpty>> Unknown builtin: %\n", cmd ), renderer );
        return true;
    }
}

ReadProcessOutput :: ( process: *Process, sourceBuffer: *SourceBuffer ) -> Process_Result, s64
{
    success: bool;
    outBytes, errBytes: s64;
    if !process.output.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success, outBytes = read_pipe( *process.output, range );

        if outBytes
            CommitWrite( sourceBuffer, outBytes );
    }
    if !process.error.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success, errBytes = read_pipe( *process.error, range );

        if errBytes
            CommitWrite( sourceBuffer, errBytes );
    }

    totalBytes := outBytes + errBytes;

    result: Process_Result = .{ type = .STILL_RUNNING };
    // No more output, so check if it's been killed
    if process.output.eof && process.error.eof
    {
        success, result = get_process_result( process );
        if !success
        {
            error_code, error_string := get_error_value_and_string();
            // TODO Diagnostics
            //log_error( "Couldn’t get process result for command \"%\": % %", get_quoted_command_string(args), error_code, error_string );
            kill_process( process );
            result = .{type = .EXITED, exit_code = -1};
        }
    }

    return result, totalBytes;
}

// timeoutMs == -1 means wait forever
// timeoutMs == 0 means dont wait at all
WaitForAllOpenHandles :: ( appState: *AppState, timeoutMs := -1 ) -> bool
{
#if OS == .WINDOWS
{
    timeout := INFINITE;
    if timeoutMs >= 0
        timeout = cast(u32) timeoutMs;

    handles: [4] HANDLE = ---;
    handleCount: u32 = 0;

    if IsRunning( appState.builtinProcess )
    {
        if !appState.builtinProcess.output.eof
        {
            handles[handleCount] = appState.builtinProcess.output.overlapped.hEvent;
            handleCount += 1;
        }
        if !appState.builtinProcess.error.eof
        {
            handles[handleCount] = appState.builtinProcess.error.overlapped.hEvent;
            handleCount += 1;
        }
    }

    if appState.shell.getWaitableHandlesProc
        appState.shell.getWaitableHandlesProc( appState.shell, handles, *handleCount );
    else
    {
        // If the shell doesnt provide waitable handles, assume we're gonna be doing constant polling on its pipes
        timeout = 0;
    }

    // NOTE Passing RAWINPUT here causes us to constantly be woken up by window msgs and burn cpu like crazy
    result := MsgWaitForMultipleObjects( handleCount, handles.data, .FALSE, timeout, QS_KEY | QS_MOUSE ); //QS_RAWINPUT );

    if result == WAIT_FAILED
    {
        // TODO Logs / diagnotics
        log_error("Unable to read command's output.\n");
        return false;
    }
    // else
    // {
    //     print( "MsgWaitForMultipleObjects woken up by: %\n",
    //            ifx result == WAIT_TIMEOUT then -1 else result - WAIT_OBJECT_0 );
    // }
}
else
{
    #assert( false && "Implement me" );
}
    
    return true;
}

