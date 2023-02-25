
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

PackColor :: ( color: v3 ) -> u32
{
    result: u32 = (((cast(u32)(color.z * 255)) & 0xFF) << 16)
                | (((cast(u32)(color.y * 255)) & 0xFF) << 8)
                |  ((cast(u32)(color.x * 255)) & 0xFF);
    return result;
}

// Round to nearest, following C's convention .. https://cplusplus.com/reference/cmath/round/
Round :: ( x: float64 ) -> float64
{
    y := floor( x );

    d := x - y;
    if d > 0.5 || (d == 0.5 && x > 0)
        y += 1;

    return y;
}
Round :: ( x: float32 ) -> float32
{
    return cast(float32) Round( cast(float64)x );
}
