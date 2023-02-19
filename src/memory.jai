
sizeof  :: inline ( x: $T ) -> int { return size_of(T); }
// TODO Nothing like this I could find so far!?
alignof :: inline ( x: $T ) -> int
{
    return ifx size_of(T) <= 8 then size_of(T) else 8;
}
offsetof :: inline ( $T: Type, attributeName: string ) -> int
{
    assert( type_info( T ).type == .STRUCT );
    _, result := get_field( type_info( T ), attributeName );
    return result;
}

Megabytes :: inline ( num: int ) -> int { return num * 1024 * 1024; }
Gigabytes :: inline ( num: int ) -> int { return Megabytes( num ) * 1024; }

IsPowerOf2 :: inline ( x: $T ) -> bool
{
    return x > 0 && (x & (x - 1)) == 0;
}

AlignUp :: inline ( size: int, alignment: int ) -> int
{
    assert( IsPowerOf2( alignment ) );
    result := (size + (alignment - 1)) & ~(alignment - 1);
    return result;
}

AlignUp :: inline ( address: *void, alignment: int ) -> *void
{
    assert( IsPowerOf2( alignment ) );
    result := cast(*void)((cast(int)address + (alignment - 1)) & ~(alignment - 1));
    return result;
}



// TODO Make a module out of this so namespacing works better
MemoryTag :: enum
{
    // TODO Define this app-side somehow
    Unknown :: 0;
}

MemoryFlags :: enum_flags
{
    //None :: 0;
    NoClear;
}

MemoryParams :: struct
{
    // TODO Enum bit size?
    tag: MemoryTag;
    flags: MemoryFlags;
    alignment: u16;
}
Default :: inline ( tag: MemoryTag = .Unknown ) -> MemoryParams { return .{ tag, 0, 0 }; }
NoClear :: inline ( tag: MemoryTag = .Unknown ) -> MemoryParams { return .{ tag, .NoClear, 0 }; }
Aligned :: inline ( alignment: u16, tag: MemoryTag = .Unknown ) -> MemoryParams { return .{ tag, 0, alignment }; }



///// Fixed-size arena
// TODO For the dynamic case, copy over the PerFrameHeap
MemoryArena :: struct
{
    base: *u8;
    size: s64;
    used: s64;
}

// Initialize a static (fixed-size) arena using the given block of memory
Init :: ( using arena: *MemoryArena, newBase: *void, newSize: s64 )
{
    assert( newSize != 0 );
    base = newBase;
    size = newSize;
    used = 0;
}

Init :: ( using arena: *MemoryArena, newSize: s64 )
{
    assert( newSize != 0 );
    // TODO globalPlatform
    base = VirtualAlloc( null, xx newSize, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE );
    size = newSize;
    used = 0;
}

Clear :: ( using arena: *MemoryArena )
{
    used = 0;
}

Destroy :: ( using arena: *MemoryArena )
{
    VirtualFree( base, 0, MEM_RELEASE );
    size = 0;
    used = 0;
}

Alloc :: ( using arena: *MemoryArena, allocSize: int, params: MemoryParams = .{} ) -> *void
{
    assert( used + allocSize < size, "Fixed arena overflow!" );

    alignment := params.alignment;
    if !alignment
        alignment = xx alignof(u64);

    result := AlignUp( base + used, alignment );
    if !(params.flags & MemoryFlags.NoClear)
        memset( result, 0, allocSize );

    used = result + allocSize - base;
    return result;
}

Alloc :: ( using arena: *MemoryArena, $T: Type, params: MemoryParams = .{} ) -> *T
{
    newParams := params;
    newParams.alignment = max( params.alignment, xx alignof(T) );

    // TODO Investigate this business
    clear := !(params.flags & MemoryFlags.NoClear);
    init  :: initializer_of(T);
    #if init
        newParams.flags |= MemoryFlags.NoClear;

    result := cast(*T) inline Alloc( arena, sizeof(T), newParams );
    #if init
    {
        if clear
            inline init( result );
    }

    return result;
}

AllocArray :: ( using arena: *MemoryArena, $T: Type, count: int, params: MemoryParams = .{} ) -> []T
{
    newParams := params;
    newParams.alignment = max( params.alignment, xx alignof(T) );

    clear := !(params.flags & MemoryFlags.NoClear);
    init  :: initializer_of(T);
    #if init
        newParams.flags |= MemoryFlags.NoClear;

    base := Alloc( arena, count * sizeof(T), newParams );

    result: [] T = ---;
    result.count = count;
    result.data  = base;

    #if init
    {
        if clear
        {
            for * result
                inline init( it );
        }
    }

    return result;
}

// TODO How to restrict T to a struct type?
// TODO How to specify the arena attribute by name?
BootstrapStructWithArena :: ( $T: Type, arenaFieldOffset: int, arenaSize: s64 ) -> *T
{
    arena: MemoryArena = ---;
    Init( *arena, arenaSize );

    result := Alloc( *arena, T );
    <<cast(*MemoryArena)(cast(*u8)result + arenaFieldOffset) = arena;

    return result;
}

#scope_file

// TODO Remove
#import "Windows";

