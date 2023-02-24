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
    }

    appState := cast(*AppState) memory.appState;

    for input.events
    {
        if it.type == .KEYBOARD
        {
            if it.key_code ==
            {
                case .PAGE_UP;
                appState.lineOffset += renderer.cellCount.y / 2;
                case .PAGE_DOWN;
                appState.lineOffset -= renderer.cellCount.y / 2;
            }
        }
    }
    appState.lineOffset = clamp( appState.lineOffset, 0, appState.sourceBuffer.lines.count - renderer.cellCount.y - 1 );

    UpdateRendererCells( renderer, memory.loadedFace, appState.sourceBuffer, appState.lineOffset );
}

#scope_file

#import "File";
#load "interface.jai";


AppState :: struct
{
    mainArena: MemoryArena;

    sourceBuffer: SourceBuffer;
    lineOffset: s64;
}

Init :: ( memory: *AppMemory ) -> *AppState
{
    // TODO Adjust this better
    // TODO Add support for commiting & decommiting as we go?
    appState := BootstrapStructWithArena( AppState, offsetof( AppState, "mainArena" ), Gigabytes( 1 ) );
    memory.appState = appState;

    lipsumData, success2 := read_entire_file( "data/lipsum.txt" );
    assert( success2 );
    lipsumWrappedData, success3 := read_entire_file( "data/lipsum_wrapped.txt" );
    assert( success3 );

    InitSourceBuffer( *appState.sourceBuffer );
    AppendToSourceBuffer( *appState.sourceBuffer, lipsumWrappedData );
    AppendToSourceBuffer( *appState.sourceBuffer, "\n>>> \x7F\n" );

    return appState;
}

UpdateRendererCells :: ( state: *RendererState, face: *LoadedFace, sourceBuffer: SourceBuffer, lineOffset: s64 )
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
            if char >= 32 && char <= 127
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


