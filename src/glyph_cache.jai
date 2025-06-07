
GlyphSlot :: struct
{
    // TODO If we (should) allocate these all in one block, these can (should) be indices
    // TODO Could actually go one further, and just initially push all available atlas indices
    // into an array and grab from that until they run out!?
    next: *GlyphSlot;
    // Linear index into the atlas
    // TODO Do we want to instead pack the X.Y here like refterm does?
    index: u32;
}

GlyphEntry :: struct
{
    // Keys to the linked entries in the chain
    lruNext: u32;
    lruPrev: u32;

    slot: *GlyphSlot;
    cachedState: GlyphEntryView.CachedState;
    // TODO These are tiles yeah?
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
    // Linear index into the atlas
    slotIndex: u32;
    // User data
    cachedState: GlyphEntryView.CachedState;
    dimX, dimY: u8;
}

GlyphTable :: struct
{
    entries: Table( u32, GlyphEntry, LOAD_FACTOR_PERCENT = 99, REFILL_REMOVED = true );
    // 'lruPrev' here points to the LRU entry
    lruSentinel: GlyphEntry;
    freeSlots: GlyphSlot;
}



InitGlyphCache :: ( table: *GlyphTable )
{
    // NOTE GlyphCacheSize is the number of non-reserved slots in the atlas
    // Allocate double that to ensure the hashtable never has to reallocate
    init( table.entries, GlyphCacheSize * 2 );

    // TODO Slots array & chain initialisation
}

FindOrAddGlyphEntry :: ( codepoint: u32, table: *GlyphTable ) -> GlyphEntryView
{
    assert( codepoint && "Codepoint 0 is reserved and cannot be added to the glyph table" );

    entry := table_find_pointer( table.entries, codepoint );
    if entry
    {
        // Remove current LRU link for this entry
        prevEntry := GetEntry( table.entries, entry.lruPrev );
        nextEntry := GetEntry( table.entries, entry.lruNext );

        prevEntry.lruNext = entry.lruNext;
        nextEntry.lruPrev = entry.lruPrev;
    }
    else
    {
        // Find a slot (this calls EvictLRU if needed)
        slot := PopFreeSlot( table );

        // Allocate a new entry
        newEntry: GlyphEntry;
        newEntry.slot = slot;

        entry = table_add( table, key, newEntry );
    }

    // Add this entry as the new MRU
    entry.lruNext = table.lruSentinel.lruNext;
    entry.lruPrev = 0;

    nextEntry := GetEntry( table.entries, table.lruSentinel.lruNext );
    nextEntry.lruPrev = codepoint;
    table.lruSentinel.lruNext = codepoint;


    result: GlyphEntryView;
    result.key         = codepoint;
    result.slotIndex   = entry.slot.index;
    result.cachedState = entry.cachedState;
    result.dimX        = entry.dimX;
    result.dimY        = entry.dimY;

    return result;
}



#scope_file

GetEntry( table: *Table, key: u32 ) -> *GlyphEntry
{
    entry := table_find_pointer( table, key );
    // All entries we look for should exist
    assert( entry );

    return entry;
}

#if 0
{
    FindEntryIndex( table: *Table, key: u32 ) -> u32
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

PopFreeSlot( table: *GlyphTable ) -> *GlyphSlot
{
    result: *GlyphSlot;

    if table.freeSlots.next
    {
        result = table.freeSlots.next;

        table.freeSlots.next = result.next;
        result.next = null;
    }
    else
    {
        result = EvictLRU( table );
    }

    return result;
}

EvictLRU :: ( table: *GlyphTable ) -> *GlyphSlot
{
    evictedKey := table.lruSentinel.lruPrev;
    assert( evictedKey );

    entry := GetEntry( table.entries, evictedKey );
    prev := GetEntry( table.entries, entry.lruPrev );

    prev.lruNext = 0;
    table.lruSentinel.lruPrev = entry.lruPrev;

    result := entry.slot;
    table_remove( table.entries, evictedKey );

    return result;
}
