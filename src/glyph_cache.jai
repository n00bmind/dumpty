
GlyphEntry :: struct
{
    // Keys to the linked entries in the chain
    lruNext: u32;
    lruPrev: u32;

    slot: GlyphSlot;
    state: GlyphEntryView.CachedState;
    // TODO These are in tiles yeah?
    dimX, dimY: u8;
}

// A "public view" of the above entry
GlyphEntryView :: struct
{
    CachedState :: enum
    {
        Uninitialised;
        Rasterised;
    }

    // Entry locator (key to entries table, i.e. codepoint value)
    key: u32;
    slot: GlyphSlot;
    // User data
    state: GlyphEntryView.CachedState;
    dimX, dimY: u8;
}

GlyphTable :: struct
{
    entries: Table( u32, GlyphEntry, LOAD_FACTOR_PERCENT = 99, REFILL_REMOVED = true );
    // 'lruPrev' here points to the LRU entry
    lruSentinel: GlyphEntry;

    freeSlots: [] GlyphSlot;
    nextSlotIdx: u32;
}



InitGlyphCache :: ( using table: *GlyphTable, freeSlotCount: u32, firstFreeSlotIdx: u32, slotsPerRow: u32 )
{
    // freeSlotCount is the number of non-reserved slots in the atlas
    // Allocate double that to ensure the hashtable never has to reallocate
    init( *entries, freeSlotCount * 2 );

    // Initialise slots 
    freeSlots = NewArray( freeSlotCount, GlyphSlot );

    slot: GlyphSlot;
    slot.y = cast(u16)(firstFreeSlotIdx / slotsPerRow);
    slot.x = cast(u16)(firstFreeSlotIdx % slotsPerRow);

    for i: 0 .. freeSlotCount - 1
    {
        freeSlots[i] = slot;

        slot.x += 1;
        if slot.x >= slotsPerRow
        {
            slot.x = 0;
            slot.y += 1;
        }
    }
}

FindOrAddGlyphEntry :: ( codepoint: u32, table: *GlyphTable ) -> GlyphEntryView
{
    assert( codepoint && "Codepoint 0 is reserved and cannot be added to the glyph table" );

    entry := table_find_pointer( *table.entries, codepoint );
    if entry
    {
        // Remove current LRU link for this entry
        prevEntry := GetEntry( *table.entries, entry.lruPrev );
        nextEntry := GetEntry( *table.entries, entry.lruNext );

        prevEntry.lruNext = entry.lruNext;
        nextEntry.lruPrev = entry.lruPrev;
    }
    else
    {
        // Find a free atlas slot (this calls EvictLRU if needed)
        slot := PopFreeSlot( table );

        // Allocate a new entry
        newEntry: GlyphEntry;
        newEntry.slot = slot;
        newEntry.state = .Uninitialised;
        newEntry.dimX = 1;
        newEntry.dimY = 1;

        entry = table_add( *table.entries, codepoint, newEntry );
    }

    // Add this entry as the new MRU
    entry.lruNext = table.lruSentinel.lruNext;
    entry.lruPrev = 0;

    nextEntry := GetEntry( *table.entries, table.lruSentinel.lruNext );
    nextEntry.lruPrev = codepoint;
    table.lruSentinel.lruNext = codepoint;


    result: GlyphEntryView;
    result.key   = codepoint;
    result.slot  = entry.slot;
    result.state = entry.state;
    result.dimX  = entry.dimX;
    result.dimY  = entry.dimY;

    return result;
}

UpdateGlyphEntry :: ( key: u32, newState: GlyphEntryView.CachedState, newDimX: u8, newDimY: u8, table: *GlyphTable )
{
    entry := GetEntry( *table.entries, key );
    entry.state = newState;
    entry.dimX  = newDimX;
    entry.dimY  = newDimY;
}


#scope_file

#import "Hash_Table";


GetEntry :: ( table: *Table, key: u32 ) -> *GlyphEntry
{
    entry := table_find_pointer( table, key );
    // All entries we look for should exist
    assert( entry != null );

    return entry;
}

#if 0
{
    FindEntryIndex :: ( table: *Table, key: u32 ) -> u32
    {
        Walk_Table(#code
        {
            entry := *table.entries[index];
            if entry.hash == hash
            {
                if inline table.compare_function( entry.key, key )
                    break;
            }
        });

        return index;
    }
}

PopFreeSlot :: ( table: *GlyphTable ) -> GlyphSlot
{
    result: GlyphSlot;

    if table.nextSlotIdx < table.freeSlots.count
    {
        result = table.freeSlots[ table.nextSlotIdx ];
        table.nextSlotIdx += 1;
    }
    else
    {
        result = EvictLRU( table );
    }

    return result;
}

EvictLRU :: ( table: *GlyphTable ) -> GlyphSlot
{
    evictedKey := table.lruSentinel.lruPrev;
    assert( evictedKey != 0 );

    entry := GetEntry( *table.entries, evictedKey );
    prev := GetEntry( *table.entries, entry.lruPrev );

    prev.lruNext = 0;
    table.lruSentinel.lruPrev = entry.lruPrev;

    result := entry.slot;
    table_remove( *table.entries, evictedKey );

    return result;
}
