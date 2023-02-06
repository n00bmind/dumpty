#import "Math";


// TODO Move all this stuff to our own math module
v2 :: Vector2;
v3 :: Vector3;

v2s :: struct
{
    x, y : s32;
}
operator + :: ( a: v2s, b: v2s ) -> v2s 
{
    return .{ a.x + b.x, a.y + b.y };
}
operator - :: ( a: v2s, b: v2s ) -> v2s 
{
    return .{ a.x - b.x, a.y - b.y };
}
operator * :: ( a: v2s, b: s32 ) -> v2s #symmetric
{
    return .{ b * a.x, b* a.y };
}

v2u :: struct
{
    x, y : u32;
}

IsPowerOfTwo :: (x: int) -> bool
{
    return (x & (x - 1)) == 0;
}
Log2 :: ( n: s32 ) -> s32
{
    assert( n > 0 );

    result: s32;
    if n >> 16  { n >>= 16; result += 16; }
    if n >> 8  { n >>= 8; result += 8; }
    if n >> 4  { n >>= 4; result += 4; }
    if n >> 2  { n >>= 2; result += 2; }
    if n >> 1  { n >>= 1; result += 1; }

    return result;
}

AppInput :: struct
{

}

AppMemory :: struct
{

}


RendererCell :: struct
{
    glyphIndex : u32;
    // NOTE Since we likely won't use the alpha on these, we could pack some flags in there
    foregroundColor : u32;
    backgroundColor : u32;

    _padding : u32;
}

RendererState :: struct
{
    cells : [] RendererCell;

    // NOTE This mirrors the ConstantsBlock in the GridShader
    Constants :: struct
    {
        windowDim: v2s;
        cellSize: v2s;
        cellCount: v2s;
        borderDim: v2s;
        borderColor: u32;
    }
    using constants : Constants;
}


UpdateAndRenderFunc :: #type ( input: AppInput, memory: *AppMemory, renderer: *RendererState );

