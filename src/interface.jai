#import "Math";
#import "Input";
#load "math.jai";
#load "memory.jai";

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
    using enum_flags u32
    {
        Blinking;
    }

    glyphIndex : u32;
    // NOTE Since we likely won't use the alpha on these, we could pack some flags in there
    foregroundColor : u32;
    backgroundColor : u32;
    flags : u32;
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
}


Glyph :: struct
{
    index:   v2s;
    offset:  v2s;
    size:    v2s;
    bearing: v2s;
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

