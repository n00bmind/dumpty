
//// Deferred logging

DeferredLogger :: (message: string, data: *void, info: Log_Info)
{
    // TODO 
}

log_warn :: ( format_string: string, args: .. Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0,
              section : *Log_Section = null )
{
    log( format_string, ..args, loc, flags | .WARNING, user_flags, section );
} @PrintLike


push :: ( array: *[..] $T, data: T )
{
    array_add( array, data );
}

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



PackGlyphIndex :: ( x: int, y: int ) -> u32
{
    assert( x >= 0 && x < U16_MAX && "Slot x coordinate out of range" );
    assert( y >= 0 && y < U16_MAX && "Slot y coordinate out of range" );

    result: u32 = (cast(u32)y << 16) | cast(u32)x;
    return result;
}

PackGlyphIndex :: ( slot: GlyphSlot ) -> u32
{
    return PackGlyphIndex( slot.x, slot.y );
}
