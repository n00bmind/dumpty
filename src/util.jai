
push :: ( array: *[..] $T, data: *T, count: int )
{
    oldCount := array.count;
    array_resize( array, oldCount + count, false ); // Don't init the new range
    memcpy( array.data + oldCount, data, count * size_of(T) );
}

push :: ( array: *[..] $T, data: [] T )
{
    push( array, data.data, data.count );
}

push :: ( array: *[..] u8, data: string )
{
    push( array, data.data, data.count );
}

pop :: ( array: *[..] $T, count: int = 1 )
{
    assert( array.count > 0 );
    array.count -= count;
}
