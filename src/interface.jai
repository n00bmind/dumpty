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
    loadedFace: *LoadedFace;

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
}


Glyph :: struct
{
    index:   v2s;
    offset:  v2s;
    size:    v2s;
    bearing: v2s;
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

GlyphSlot :: struct
{
    // Tile coords into the atlas
    x, y: u16;
}

LoadedFace :: struct
{
    glyphs     : [128-32] Glyph;
    bbox       : v2s;
    advance    : s32;
    lineHeight : s32;
    descender  : s32;   // Absolute value
    texture    : u32;
}


UpdateAndRenderFunc :: #type ( input: AppInput, memory: *AppMemory, renderer: *RendererState );
ShutdownFunc :: #type ( memory: *AppMemory );

