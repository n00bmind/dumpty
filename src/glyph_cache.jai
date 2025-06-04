
GlyphSlot :: struct
{
    // TODO If we (should) allocate these all in one block, these can (should) be indices
    next: *GlyphSlot;
    prev: *GlyphSlot;
    // Linear index into the atlas
    index: u32;
}

GlyphEntry :: struct
{
    lruNext: u32;
    lruPrev: u32;
    slot: *GlyphSlot;
    cachedState: GlyphEntryView.CachedState;
    // TODO These are tiles yeah?
    dimX, dimY: u8;
}

// A "public view" of the above entry
// NOTE The id contained here can go stale, so these should be considered temporary! 
GlyphEntryView :: struct
{
    CachedState :: enum
    {
        Uninitialised;
        Rasterised;
    }

    // Entry index
    id: u32;
    // Atlas index
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
}

FindOrAddGlyphEntry :: ( codepoint: u32, table: *GlyphTable ) -> GlyphEntryView
{
    entry := table_find_pointer( table, codepoint );
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

    // TODO This is quite stupid as we need to query the entry again
    // Should we just store all GlyphEntrys in a separate array?
    entryIndex = FindEntryIndex( entry );

    // Add this entry as the new MRU
    entry.lruNext = table.lruSentinel.lruNext;
    entry.lruPrev = U32_MAX;

    nextEntry := GetEntry( table.entries, table.lruSentinel.lruNext );
    nextEntry.lruPrev = entryIndex;
    table.lruSentinel.lruNext = entryIndex;


    result: GlyphEntryView;
    result.id          = entryIndex;
    result.slotIndex   = entry.slot.index;
    result.cachedState = entry.cachedState;
    result.dimX        = entry.dimX;
    result.dimY        = entry.dimY;

    return result;
}



#scope_file

GetEntry( table: *Table, index: u32 ) -> *GlyphEntry
{
    assert( index < table.allocated );

    entry := *table.entries[index];
    return *entry.value;
}

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

PopFreeSlot( table: *GlyphTable ) -> *GlyphSlot
{
    if !table.freeSlots.next
    {
        slot := EvictLRU( table );
        return slot;
    }

    result := table.freeSlots.next;

    next := result.next;
    // TODO Why do we even doubly link these?
    next.prev = *table.freeSlots;
    table.freeSlots.next = next;
    
    result.next = null;
    result.prev = null;
    return result;
}

