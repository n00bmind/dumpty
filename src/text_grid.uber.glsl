// This is the same as text_grid.glsl but also includes the "old" UBO path
// For some reason, having both these paths in makes shader compilation hideously
// slow on my Intel card, while the TBO-only version is basically instant..
#ifdef VERTEX_SHADER

const vec2 positions[4] = vec2[](
    vec2(-1, -1),
    vec2(+1, -1),
    vec2(-1, +1),
    vec2(+1, +1)
);
void main()
{
    // Emit hardcoded positions for the 4 corners of the window
    // This assumes we're invoking this with a GL_TRIANGLE_STRIP call (and a count of 4)
    gl_Position = vec4( positions[gl_VertexID], 0.0, 1.0 );
}

#endif // VERTEX_SHADER


#ifdef FRAGMENT_SHADER

// Passed from outside code
#define CELLS_PER_PAGE (1 << CELLS_PER_PAGE_BITS)
#define CELLS_PER_PAGE_MASK (CELLS_PER_PAGE - 1)

layout(origin_upper_left) in vec4 gl_FragCoord;
out vec4 color;

uniform sampler2D glyphSampler;
uniform usamplerBuffer cellsSampler;

layout (std140) uniform ConstantsBlock
{
    ivec2 windowDim;
    ivec2 cellSize;
    ivec2 cellCount;
    ivec2 borderDim;
    uint borderColor;
    uint blinkModulateColor;
};

// NOTE Since they're elements in an array, before 4.3 there seems to be no way of avoiding having a minimum sizeof(Cell) of 16!
struct Cell
{
    uint glyphIndex;
    // NOTE Colors are always considered sRGB. Cannot do the linear conversion on the CPU while still keeping them packed
    // See https://blog.demofox.org/2018/03/10/dont-convert-srgb-u8-to-linear-u8/
    uint foregroundColor;
    uint backgroundColor;
    uint flags;
};

// This amounts to 12 UBOs of 65536 bytes, which is supposedly the minimum guaranteed by the spec.
// TODO Test on old cards!!
layout (std140) uniform CellsBlock
{
    Cell cells[CELLS_PER_PAGE];
} cellPages[12];


ivec2 UnpackGlyphXY( uint packedIndex )
{
    uint x = packedIndex & 0xffffu;
    uint y = packedIndex >> 16;
    return ivec2( x, y );
}

vec3 UnpackColor(uint packedColor)
{
    uint r = packedColor & 0xffu;
    uint g = (packedColor >> 8) & 0xffu;
    uint b = (packedColor >> 16) & 0xffu;
    return vec3(r, g, b) / 255.0;
}

// TODO We could make this value a program setting.
// According to https://www.puredevsoftware.com/blog/2019/01/22/sub-pixel-gamma-correct-font-rendering/ and
// https://freetype.org/freetype2/docs/reference/ft2-base_interface.html, it seems to be more optimal to go below the standard 2.2 power curve
//const vec3 gamma = vec3( 2.2 );

// For now go with the "Adobe tested" value (pass it as a uniform to quickly compare a few values)
const vec3 gamma = vec3( 1.8 );
const vec3 oneOverGamma = vec3( 1.0 / gamma );

vec3 ColorToLinear( vec3 gammaColor )
{
    return pow( gammaColor, gamma );
}
vec3 ColorToGamma( vec3 linearColor )
{
    return pow( linearColor, oneOverGamma );
}


Cell CellFromTextureIndex( ivec2 cellIndex )
{
    int idx = cellIndex.y * cellCount.x + cellIndex.x;
    uvec4 value = texelFetch( cellsSampler, idx );

    Cell cell = Cell( value.r, value.g, value.b, value.a );
    return cell;
}

Cell CellFromBufferIndex( ivec2 cellIndex )
{
    int idx = cellIndex.y * cellCount.x + cellIndex.x;
    int cellPage = idx >> CELLS_PER_PAGE_BITS;
    int indexInPage = idx & CELLS_PER_PAGE_MASK;

    Cell cell;
    // HACK Apparently you can only index an array of blocks using a constant expression, so.. yeah..
    if( cellPage == 0 )
        cell = cellPages[0].cells[indexInPage];
    else if( cellPage == 1 )
        cell = cellPages[1].cells[indexInPage];
    else if( cellPage == 2 )
        cell = cellPages[2].cells[indexInPage];
    else if( cellPage == 3 )
        cell = cellPages[3].cells[indexInPage];
    else if( cellPage == 4 )
        cell = cellPages[4].cells[indexInPage];
    else if( cellPage == 5 )
        cell = cellPages[5].cells[indexInPage];
    else if( cellPage == 6 )
        cell = cellPages[6].cells[indexInPage];
    else if( cellPage == 7 )
        cell = cellPages[7].cells[indexInPage];
    else if( cellPage == 8 )
        cell = cellPages[8].cells[indexInPage];
    else if( cellPage == 9 )
        cell = cellPages[9].cells[indexInPage];
    else if( cellPage == 10 )
        cell = cellPages[10].cells[indexInPage];
    else if( cellPage == 11 )
        cell = cellPages[11].cells[indexInPage];

    // TODO Just so its easy to see when we're using this path
    cell.foregroundColor = 0xFF0000u;
    return cell;
}


void main ()
{
    // Compute what the top left margin must be so the bottom left is kept constant
    ivec2 topLeftMargin = ivec2( borderDim.x, windowDim.y - cellCount.y*cellSize.y - borderDim.y );
    ivec2 cellIndex = ivec2( gl_FragCoord.xy - topLeftMargin ) / cellSize;
    ivec2 cellPos = ivec2( gl_FragCoord.xy - topLeftMargin ) % cellSize;

    vec3 result;
    if( (gl_FragCoord.x >= topLeftMargin.x) &&
        (gl_FragCoord.y >= topLeftMargin.y) &&
        (cellIndex.x < cellCount.x) &&
        (cellIndex.y < cellCount.y) )
    {
    #if USE_TEXTURE_BUFFER
        Cell cell = CellFromTextureIndex( cellIndex );
    #else
        Cell cell = CellFromBufferIndex( cellIndex );
    #endif

        ivec2 glyphPos = UnpackGlyphXY( cell.glyphIndex ) * cellSize;

        vec2 atlasPos = vec2( glyphPos + cellPos );
        vec4 glyphTexel = texture( glyphSampler, atlasPos / 1024 );

        // Gamma-correct cell colors
        vec3 background = ColorToLinear( UnpackColor( cell.backgroundColor ) );
        vec3 foreground = ColorToLinear( UnpackColor( cell.foregroundColor ) );

        vec3 blink = UnpackColor( blinkModulateColor );
        if( (cell.flags & 1u) != 0u ) foreground *= blink;
        //if((cell.foreground >> 25) & 1) foreground *= 0.5;

        // Blend using (subpixel) alpha values with each color component
        // https://www.puredevsoftware.com/blog/2019/01/22/sub-pixel-gamma-correct-font-rendering/
        // https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html
        result.r = glyphTexel.r * foreground.r + (1 - glyphTexel.r) * background.r;
        result.g = glyphTexel.g * foreground.g + (1 - glyphTexel.g) * background.g;
        result.b = glyphTexel.b * foreground.b + (1 - glyphTexel.b) * background.b;

        // Gamma encode it again for presentation
        result = ColorToGamma( result );
    }
    else
    {
        result = UnpackColor( borderColor );
        //result = vec3( 0.15, 0.15, 0.2 );
    }

    color = vec4( result, 1 );
}

#endif // FRAGMENT_SHADER

