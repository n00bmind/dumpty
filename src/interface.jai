#import "Math";
#import "Input";
#load "math.jai";
#load "memory.jai";


APP_DLL_NAME :: "app";
GRID_SHADER_FILENAME :: "text_grid.glsl";


BuildConfig :: enum
{
    Debug;
    Dev;
    Release;
}
#placeholder BUILD_CONFIG;


AppInput :: struct
{
    events: [..] Event;
}

AppMemory :: struct
{
    appState: *void;

    initialized: bool;
}


CursorState :: struct
{
    x, y: s32;
    props: GlyphProps;
    debugLeftMargin: s8;
}

// NOTE This mirrors the Cell struct in the GridShader
RendererCell :: struct
{
    glyphIndex: u32;
    props: GlyphProps;
}

RendererState :: struct
{
    cells : [] RendererCell;
    loadedFont: *LoadedFont;
    palette: *[256] c3;
    savedCursor: CursorState;

    // NOTE This mirrors the ConstantsBlock in the GridShader
    Constants :: struct
    {
        windowDim:          v2s;
        cellSize:           v2s;
        cellCount:          v2s;
        borderDim:          v2s;
        borderColor:        u32;
        blinkModulateColor: u32;
    }
    using constants : Constants;
    firstRowY: s32;

    debugDrawAtlas: bool;
}


Glyph :: struct
{
    tile:    v2s;
    size:    v2s;
    bearing: v2s;
}

GlyphSlot :: struct
{
    // Tile coords into the atlas
    x, y: s16;
}

GlyphProps :: struct
{
    Flags :: enum_flags u32
    {
        Bold;
        Dim;
        Italic;
        Underline;
        Blinking;
        ReverseVideo;
        Invisible;
        Strikethrough;
    }

    foregroundColor: u32;
    backgroundColor: u32;
    flags: Flags;
}

// Writable ASCII (32..127) plus 1 slot for the cursor glyph
ReservedSlotCount :: 128 - 32;

LoadedFont :: struct
{
    face:            *void;
    stagingBitmap:   [..] u8;
    directGlyphs:    [ReservedSlotCount] GlyphSlot;
    bbox:            v2s;
    advance:         s32;
    lineHeight:      s32;
    descender:       s32;        // Absolute value
    bitmapPitch:     s32;
    atlasSizeTexels: s32;
    textureHandle:   u32;
}


UpdateAndRenderFunc :: #type ( input: AppInput, memory: *AppMemory, renderer: *RendererState );
ShutdownFunc :: #type ( memory: *AppMemory );

