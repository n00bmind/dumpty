#import "Math";
#import "Input";
#load "math.jai";
#load "memory.jai";


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


RendererCell :: struct
{
    glyphIndex: u32;
    props: GlyphProps;
}

RendererState :: struct
{
    cells : [] RendererCell;
    loadedFont: *LoadedFont;

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
        Blinking;
        Bold;
        Dim;
        Italic;
        Underline;
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
    directGlyphs:    [ReservedSlotCount] GlyphSlot;
    bbox:            v2s;
    advance:         s32;
    lineHeight:      s32;
    descender:       s32;        // Absolute value
    atlasSizeTexels: s32;
    textureHandle:   u32;
}


UpdateAndRenderFunc :: #type ( input: AppInput, memory: *AppMemory, renderer: *RendererState );
ShutdownFunc :: #type ( memory: *AppMemory );

