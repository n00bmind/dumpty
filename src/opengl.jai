

OpenGLState :: struct
{
    windowWidth, windowHeight : float;

    vertexBuffer : GLuint;
    indexBuffer : GLuint;

    gridShader : GridShader;
    testShader : TestShader;

    white : u32;
    whiteTextureHandle : GLuint;

    maxUniformBlockSize: GLint;
    maxUniformArrayCount: GLint;
    maxTextureBufferSize: GLint;
}

OpenGLInit :: ( state: *OpenGLState, window: Window_Type ) -> bool
{
    // TODO Error handling!
    //gl_create_context( window, 3, 3, compatibility = false, debug = true );
    gl_create_context( window, 3, 3, compatibility = false );

    gl_load( *gl );
    gl_enable_debug_output( break_on_error = true );

    device: *GLubyte = glGetString( GL_RENDERER );
    print( "Using device: %\n", to_string( device ) );

    glGetIntegerv( GL_MAX_UNIFORM_BLOCK_SIZE, *state.maxUniformBlockSize );
    print( "GL_MAX_UNIFORM_BLOCK_SIZE: %\n", state.maxUniformBlockSize );
    glGetIntegerv( GL_MAX_FRAGMENT_UNIFORM_BLOCKS, *state.maxUniformArrayCount );
    print( "GL_MAX_FRAGMENT_UNIFORM_BLOCKS: %\n", state.maxUniformArrayCount );
    // NOTE Cap at 12 + 1 (12 is supposedly the minimum guaranteed by the spec)
    assert( state.maxUniformArrayCount >= 12 );
    state.maxUniformArrayCount = 12;
    glGetIntegerv( GL_MAX_TEXTURE_BUFFER_SIZE, *state.maxTextureBufferSize );
    print( "GL_MAX_TEXTURE_BUFFER_SIZE: %\n", state.maxTextureBufferSize );

    dummyVAO: GLuint;
    glGenVertexArrays( 1, *dummyVAO );
    glBindVertexArray( dummyVAO );

    glGenBuffers( 1, *state.vertexBuffer );
    glGenBuffers( 1, *state.indexBuffer );

    // Create a white texture
    state.white = 0xFFFFFFFF;
    state.whiteTextureHandle = OpenGLAllocateTexture( cast(*u8)*state.white, 1, 1, true, null );

    // Setup render state: alpha-blending enabled, no face culling, no depth testing,
    //glEnable( GL_BLEND );
    //glBlendEquation( GL_FUNC_ADD );
    //glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
    glDisable( GL_CULL_FACE );
    glDisable( GL_DEPTH_TEST );

    DumpGLErrors( "context" );

    // Bind buffer so shaders can bind their attributes
    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );

    shaderOk := BuildGridShaderProgram( *state.gridShader, <<state );
    assert( shaderOk );
    shaderOk = BuildTestShaderProgram( *state.testShader );
    assert( shaderOk );

    return true;
}


DumpGlyphBitmapData :: ( buffer: *u8, width: u32, height: u32 )
{
    for y: 0..height - 1
    {
        for x: 0..width - 1
        {
            v := buffer[ y * width + x ];
            if v == 0
                print( " .  " );
            else
                print( "% ", formatInt( v, minimum_digits = 3, padding = #char " " ) );
        }
        print( "\n" );
    }
    exit( 0 );
}

DumpGlyphBitmapData :: ( glyph: FT_GlyphSlot )
{
    print( "Glyph index %:\n", glyph.glyph_index );
    print( "Width %\n", glyph.bitmap.width );
    print( "Pitch %\n", glyph.bitmap.pitch );
    print( "Height %\n", glyph.bitmap.rows );
    print( "Bearing X %\n", glyph.bitmap_left );
    print( "Bearing Y %\n", glyph.bitmap_top );
    DumpGlyphBitmapData( glyph.bitmap.buffer, xx glyph.bitmap.pitch, glyph.bitmap.rows );
}

FONT_TEX_ATLAS_SIZE :: 1024;
// Undefined in the provided bindings
// TODO Investigate SDF rendering supported on latest FT .. see https://github.com/tsoding/ded/pull/60
//#define FT_LOAD_TARGET_( x )   ( FT_STATIC_CAST( FT_Int32, (x) & 15 ) << 16 )
//#define FT_LOAD_TARGET_LCD     FT_LOAD_TARGET_( FT_RENDER_MODE_LCD    )
FT_LOAD_TARGET_LCD :: (cast(s32)FT_Render_Mode.FT_RENDER_MODE_LCD & 15) << 16;
    

// Loads a font from disk using Freetype and creates an atlas for it
OpenGLLoadFont :: ( path: string, fontHeight: s32, ft: *FT_Library ) -> LoadedFont, bool
{
    fontData, success := read_entire_file( path );
    if !success
    {
        print( "Failed loading font '%'\n", path );
        return .{}, false;
    }

    // FT_Face is actually just an alias for *FT_FaceRec_
    face := New( FT_FaceRec_ );
    error := FT_New_Memory_Face( ft.*, fontData.data, cast(s32) fontData.count, 0, *face );
    if error
    {
        print( "Failed parsing font '%'\n", path );
        return .{}, false;
    }

    // error = FT_Set_Pixel_Sizes( face, 0, xx fontHeight );
    // TODO Figure out actual dpi of the current monitor
    error = FT_Set_Char_Size( face, 0, fontHeight * 64, 96, 96 );
    assert(!error);

    loadedFont: LoadedFont;
    loadedFont.face = face;
    loadedFont.atlasSizeTexels = FONT_TEX_ATLAS_SIZE;

    loadedFont.lineHeight = cast(s32)(face.size.metrics.height / 64.0);
    print( "Font line height: %\n", loadedFont.lineHeight );

    // FIXME This may become quite imprecise at small sizes?
    // In a way we're doing our own grid fitting. Investigate what the best practice is here..
    // TODO Try to find and test non-integer sizes and see how the shader responds
    maxAdvance := FT_MulFix( face.max_advance_width, face.size.metrics.x_scale ) / 64.0;
    loadedFont.advance = cast(s32) Round( maxAdvance );
    print( "Font max advance: % (rounded to %)\n", maxAdvance, loadedFont.advance );

    // Not grid-fitted.. but still rounded!?
    print( "Font metrics max_advance: %\n", face.size.metrics.max_advance / 64.0 );

    // TODO Apparently relying on the ascender / descender is.. unreliable .. see https://freetype.org/freetype2/docs/tutorial/step2.html
    loadedFont.descender = abs( cast(s32)(face.size.metrics.descender / 64.0) );
    print( "Font descender: %\n", loadedFont.descender );
    // NOTE Using the bbox for the atlas is technically correct as that guarantees to provide enough space for all the font's glyphs
    // However in the simple grid shader we're using, we need glyphs in the atlas to be rendered in the same grid they'll be placed into in the final image
    // This is mostly unimportant when dealing with ASCII only, but it will become more relevant when we support unicode
    pixels_w := FT_MulFix( (face.bbox.xMax - face.bbox.xMin), face.size.metrics.x_scale ) / 64.0;
    pixels_h := FT_MulFix( (face.bbox.yMax - face.bbox.yMin), face.size.metrics.y_scale ) / 64.0;
    print( "Font bbox: % x %\n", pixels_w, pixels_h );
    loadedFont.bbox = .{ xx ceil( pixels_w ), xx ceil( pixels_h ) };

    // Get some metrics from first glyph
    error = FT_Load_Char( face, 0, FT_LOAD_RENDER | FT_LOAD_TARGET_LCD );
    if error
    {
        print( "Failed to load first glyph for estimating advance\n" );
        assert( false );
    }
    print( "First glyph advance: %\n", face.glyph.advance.x / 64.0 );
    print( "First glyph linearHoriAdvance: %\n", face.glyph.linearHoriAdvance / 65536.0 );
    print( "First glyph metrics horiAdvance: %\n", face.glyph.metrics.horiAdvance / 64.0 );
    print( "First glyph metrics bounds: %, %\n", face.glyph.metrics.width / 64.0, face.glyph.metrics.height / 64.0 );


    // TODO This must be 1 when doing 1-byte per pixel font textures
    // TODO Make a container for application settings
    // TODO Make subpixel rendering an easily toggeable setting for comparing before/after
    // TODO Play with the various settings available in https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html
    glPixelStorei( GL_UNPACK_ALIGNMENT, 4 );

    glGenTextures( 1, *loadedFont.textureHandle );
    glBindTexture( GL_TEXTURE_2D, loadedFont.textureHandle );
    // TODO Should probably check pixel_mode in the bitmap
    glTexImage2D( GL_TEXTURE_2D, 0, GL_RGB8, FONT_TEX_ATLAS_SIZE, FONT_TEX_ATLAS_SIZE, 0, GL_RGB, GL_UNSIGNED_BYTE, null );

    // Load glyphs for ASCII
    // FIXME At pixel size 15 with consolas.ttf (and smaller), the 'W' gets cut on the right side!
    x, y: s16 = 0;
    W, H := loadedFont.advance, loadedFont.lineHeight;
    for 32..127
    {
        if it == 127
        {
            // Special-case last glyph to use as cursor 
            buffer: [..] u8;
            buffer.allocator = temp;
            // GL_UNPACK_ALIGNMENT of 4 seems to suit FT's subpixel-rendered bitmaps, so this one needs to respect that too
            // See the description for 'pitch' in https://freetype.org/freetype2/docs/reference/ft2-basic_types.html#ft_bitmap
            pitch := AlignUp( loadedFont.advance * 3, 4 );
            array_resize( *buffer, pitch * loadedFont.lineHeight );

            for j: 0..loadedFont.lineHeight - 1
            {
                for i: 0..loadedFont.advance - 1
                {
                    // TODO Cursor style setting
                    //atBorder := (i == 0 || j == 0 || i == loadedFont.advance - 1 || j == loadedFont.lineHeight - 1);
                    //atBorder := (j == loadedFont.lineHeight - 1);
                    //atBorder := (i == 0 || i == 1);
                    atBorder := true;
                    buffer[j * pitch + i*3 + 0] = xx ifx atBorder then 0xFF else 0;
                    buffer[j * pitch + i*3 + 1] = xx ifx atBorder then 0xFF else 0;
                    buffer[j * pitch + i*3 + 2] = xx ifx atBorder then 0xFF else 0;
                }
            }

            glTexSubImage2D( GL_TEXTURE_2D, 0, x * W, y * H, xx W, xx H, GL_RGB, GL_UNSIGNED_BYTE, buffer.data );

            //DumpGlyphBitmapData( buffer.data, xx pitch, xx loadedFont.lineHeight );
        }
        else
        {
            slot := GlyphSlot.{ x, y };

            ok := PrepareGlyphTiles( cast(u32) it, slot, loadedFont );
            if !ok
            {
                print( "Failed to load glyph for ASCII %\n", it );
                return .{}, false;
            }

            //if it == 87
                //DumpGlyphBitmapData( face.glyph );
        }

        slot := *(loadedFont.directGlyphs[ it - 32 ]);
        slot.* = .{ x, y };
        // g.size    = .{ cast(s32) face.glyph.bitmap.width / 3, cast(s32) face.glyph.bitmap.rows };
        // g.bearing = .{ face.glyph.bitmap_left, face.glyph.bitmap_top };

        //print( "Loaded character %: %\n", it, loadedFont.directGlyphs[ it - 32 ] );

        x += 1;
        if x >= FONT_TEX_ATLAS_SIZE / loadedFont.advance
        {
            x = 0;
            y += 1;
            assert( (y + 1) * H <= FONT_TEX_ATLAS_SIZE );
        }
    }

    return loadedFont, true;
}

// TODO This should support rasterizing to multiple tiles for proper Unicode support
PrepareGlyphTiles :: ( codepoint: u32, slot: GlyphSlot, font: LoadedFont ) -> bool
{
    face := cast(FT_Face) font.face;

    // Enable subpixel rendering (3 separate alpha components per pixel)
    // TODO Make a setting that adds support for grayscale AA as some people seem to hate sub-pixel due to the colour fringing
    error := FT_Load_Char( face, codepoint, FT_LOAD_RENDER | FT_LOAD_TARGET_LCD );
    if error
        return false;

    W, H := font.advance, font.lineHeight;
    baseline := font.lineHeight - font.descender;

    // NOTE FT docs incorrectly report this field as being the width in pixels
    pixelWidth := face.glyph.bitmap.width / 3;
    assert( pixelWidth * 3 == face.glyph.bitmap.width, "Glyph width % not multiple of 3", face.glyph.bitmap.width );
    pixelHeight := face.glyph.bitmap.rows;

    // Some chars are just empty
    // if pixelWidth && pixelHeight
    {
        glTexSubImage2D( GL_TEXTURE_2D, 0, slot.x * W + face.glyph.bitmap_left, slot.y * H + baseline - face.glyph.bitmap_top,
                         pixelWidth, pixelHeight, GL_RGB, GL_UNSIGNED_BYTE, face.glyph.bitmap.buffer );
    }

    advance := cast(s32) Round( face.glyph.advance.x / 64.0 );
    // TODO There are (non-complex?) glyphs with a bigger pitch than their reported advance, so what's the deal with those?
    // FIXME Some chromas are wrong, meaning we must not be rendering the complete subpixel triads, due to some glyphs being cut
    // Check glyphs for U, V, W at small sizes
    // TODO Could this have anything to do with font weights?
    assert( advance == font.advance, "Font has non-uniform advance" );

    return true;
}


// Disable to use previous path using a collection of contiguously-mapped uniform blocks (UBOs)
// Doesn't seem to offer a real speed advantage (most likely due to the limitation of using a constant expression to index them),
// although it seems marginally faster on Intel hardware, but it's also pretty limited in the maximum size of cell buffer it can fit,
// and will still be insufficient for fullscreen windows with a small font size
USE_TEXTURE_BUFFER :: true;

OpenGLRender :: ( state: *OpenGLState, font: LoadedFont, renderer: RendererState )
{
    #if BUILD_CONFIG != .Release
    {
        if renderer.debugDrawAtlas
        {
            OpenGLDrawAtlas( state, font );
            return;
        }
    }

    // TODO scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fbWidth := state.windowWidth; // * io.DisplayFramebufferScale.x);
    fbHeight := state.windowHeight; // * io.DisplayFramebufferScale.y);
    glViewport( 0, 0, xx fbWidth, xx fbHeight );

    glUseProgram( state.gridShader.program );    

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, font.textureHandle );  // Bind handle to slot 0.
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
    glUniform1i( state.gridShader.glyphSamplerUni, 0 );

    glBindBuffer( GL_UNIFORM_BUFFER, state.gridShader.constantsBufferHandle );
    glBufferSubData( GL_UNIFORM_BUFFER, 0, size_of(RendererState.Constants), *renderer.constants );

    topCellsCount := (renderer.cellCount.y - renderer.firstRowY) * renderer.cellCount.x;
    botCellsCount := renderer.firstRowY * renderer.cellCount.x;
    assert( topCellsCount + botCellsCount == renderer.cellCount.x * renderer.cellCount.y );
    topCellsSize := topCellsCount * size_of(RendererCell);
    botCellsSize := botCellsCount * size_of(RendererCell);
    #if USE_TEXTURE_BUFFER
    {
        glBindBuffer( GL_TEXTURE_BUFFER, state.gridShader.cellsBufferHandle );
        // This was faster than mapping the buffer & memcpying in the tests
        glBufferSubData( GL_TEXTURE_BUFFER, 0, topCellsSize, renderer.cells.data + botCellsCount );
        glBufferSubData( GL_TEXTURE_BUFFER, topCellsSize, botCellsSize, renderer.cells.data );
    }
    else
    {
        glBindBuffer( GL_UNIFORM_BUFFER, state.gridShader.cellsBufferHandle );
        glBufferSubData( GL_UNIFORM_BUFFER, 0, topCellsSize, renderer.cells.data + botCellsCount );
        glBufferSubData( GL_UNIFORM_BUFFER, topCellsSize, botCellsSize, renderer.cells.data );
    }

    glDrawArrays( GL_TRIANGLE_STRIP, 0, 4 );

    DumpGLErrors( "OpenGLRender" );
}

// For testing
// Draw a text string with the given font by issuing a separate quad per glyph
OpenGLDrawTextWithFace :: ( state: *OpenGLState, text: string, xBase: float, yBase: float, font: LoadedFont )
{
    DrawLetterQuad :: ( character: u8, xBase: float, yBase: float, slot: GlyphSlot, font: LoadedFont, vertices: *[6] TextVertex )
    {
        white :: Vector4.{ 1, 1, 1, 1 };
        red   :: Vector4.{ 1, 0, 0, 1 };
        green :: Vector4.{ 0, 1, 0, 1 };
        blue  :: Vector4.{ 0, 0, 1, 1 };

        x := xBase;
        y := yBase;

        w := font.advance;
        h := font.lineHeight;

        s := cast(float) FONT_TEX_ATLAS_SIZE;
        u0 := slot.x * w / s;
        v0 := slot.y * h / s;
        u1 := (slot.x + 1) * w / s;
        v1 := (slot.y + 1) * h / s;

        (<<vertices)[1] = .{ position = Vector3.{ x, y, 0 }, color = white, uv = .{ u0, v0 } };
        (<<vertices)[0] = .{ position = Vector3.{ x, y + h, 0 }, color = white, uv = .{ u0, v1 } };
        (<<vertices)[2] = .{ position = Vector3.{ x + w, y, 0 }, color = white, uv = .{ u1, v0 } };

        (<<vertices)[4] = .{ position = Vector3.{ x + w, y, 0 }, color = white, uv = .{ u1, v0 } };
        (<<vertices)[3] = .{ position = Vector3.{ x, y + h, 0 }, color = white, uv = .{ u0, v1 } };
        (<<vertices)[5] = .{ position = Vector3.{ x + w, y + h, 0 }, color = white, uv = .{ u1, v1 } };
    }


    vertices : [6] TextVertex;

    glActiveTexture( GL_TEXTURE0 );
    glUseProgram( state.testShader.program );    
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.testShader.projectionUni, 1, GL_TRUE, *projection._11 );

    c := text.data;
    while c < text.data + text.count
    {
        // TODO Only works for ASCII
        slot := font.directGlyphs[ <<c - 32 ];
        glBindTexture( GL_TEXTURE_2D, font.textureHandle );  // Bind handle to slot 0.
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );

        DrawLetterQuad( <<c, xBase, yBase, slot, font, *vertices );

        glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
        glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
        glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );

        xBase += font.advance;
        c += 1;
    }
}

// For testing
// Draw atlas of the given font by issuing a quad of the same size as the full texture
// Font must be loaded already
OpenGLDrawAtlas :: ( state: *OpenGLState, font: LoadedFont )
{
    glUseProgram( state.testShader.program );    
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

    // TODO Would be nice to be able to pan & zoom here
    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.testShader.projectionUni, 1, GL_TRUE, *projection._11 );

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, font.textureHandle );  // Bind handle to slot 0.
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );

    vertices : [6] TextVertex;
    white :: Vector4.{ 1, 1, 1, 1 };
    red   :: Vector4.{ 1, 0, 0, 1 };
    green :: Vector4.{ 0, 1, 0, 1 };
    blue  :: Vector4.{ 0, 0, 1, 1 };

    vertices[1] = .{ position = Vector3.{ 0, 0, 0 }, color = white, uv = .{ 0, 0 } };
    vertices[0] = .{ position = Vector3.{ 0, 1024, 0 }, color = white, uv = .{ 0, 1 } };
    vertices[2] = .{ position = Vector3.{ 1024, 0, 0 }, color = white, uv = .{ 1, 0 } };

    vertices[4] = .{ position = Vector3.{ 1024, 0, 0 }, color = white, uv = .{ 1, 0 } };
    vertices[3] = .{ position = Vector3.{ 0, 1024, 0 }, color = white, uv = .{ 0, 1 } };
    vertices[5] = .{ position = Vector3.{ 1024, 1024, 0 }, color = white, uv = .{ 1, 1 } };

    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
    glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );
}

// For testing
// Draw an apron to test the window borders and other stuff
//prevOrthoMatrix: Matrix4;
OpenGLDrawFSQTest :: ( state: *OpenGLState )
{
    // TODO scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fbWidth := state.windowWidth; // * io.DisplayFramebufferScale.x);
    fbHeight := state.windowHeight; // * io.DisplayFramebufferScale.y);

    glViewport( 0, 0, xx fbWidth, xx fbHeight );

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    //if( projection != prevOrthoMatrix )
    //{
        //print( "Orthographic matrix: \n%\t%\t%\t%\n%\t%\t%\t%\n%\t%\t%\t%\n%\t%\t%\t%\n",
               //projection._11, projection._12, projection._13, projection._14,
               //projection._21, projection._22, projection._23, projection._24,
               //projection._31, projection._32, projection._33, projection._34,
               //projection._41, projection._42, projection._43, projection._44 );
        //prevOrthoMatrix = projection;
    //}
    glUseProgram( state.testShader.program );    
    glUniformMatrix4fv( state.testShader.projectionUni, 1, GL_TRUE, *projection._11 );

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, state.whiteTextureHandle );  // Bind handle to slot 0.
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

    DumpGLErrors( "frame setup" );

    // Clear background with red, cause if we see it that's bad!
    glClearColor( 1, 0, 0, 1.0 ); 
    glClear( GL_COLOR_BUFFER_BIT );

    // Draw an apron with 1-pixel thickness right at the window edges to check we have the bounds right
    verts: [4] TextVertex =
    .[
        .{ color = .{ 1, 1, 0, 1 }, uv = .{ 0, 0 } },
        .{ color = .{ 0, 1, 0, 1 }, uv = .{ 1, 0 } },
        .{ color = .{ 0, 0, 1, 1 }, uv = .{ 0, 1 } },
        .{ color = .{ 1, 0, 1, 1 }, uv = .{ 1, 1 } },
    ];
    verts[0].position = .{ 0,                   0,              0 }; 
    verts[1].position = .{ state.windowWidth,   0,              0 }; 
    verts[2].position = .{ 0,                   state.windowHeight,   0 }; 
    verts[3].position = .{ state.windowWidth,   state.windowHeight,   0 }; 

    indices: [6] u32 =
    .[
        0, 2, 1,
        1, 2, 3,
    ];

    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glBufferData( GL_ARRAY_BUFFER, verts.count * size_of(TextVertex), verts.data,
                  GL_STREAM_DRAW );
    glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, state.indexBuffer );
    glBufferData( GL_ELEMENT_ARRAY_BUFFER, indices.count * size_of(u32), indices.data,
                  GL_STREAM_DRAW );

    glDrawElements( GL_TRIANGLES, indices.count, GL_UNSIGNED_INT, null );

    // Fill with a dark quad
    inset :: 1;
    verts[0].position = .{ 0 + inset,                   0 + inset,              0 }; 
    verts[1].position = .{ state.windowWidth - inset,   0 + inset,              0 }; 
    verts[2].position = .{ 0 + inset,                   state.windowHeight - inset,   0 }; 
    verts[3].position = .{ state.windowWidth - inset,   state.windowHeight - inset,   0 }; 
    for * verts
    {
        it.color = .{ 0.15, 0.15, 0.2, 1 };
    }
    glBufferData( GL_ARRAY_BUFFER, verts.count * size_of(TextVertex), verts.data, GL_STREAM_DRAW );
    glDrawElements( GL_TRIANGLES, indices.count, GL_UNSIGNED_INT, null );
}

#scope_file

#import "File";
#import "Math";
#import "GL" ( DUMP_GL_ERRORS = true );
#import "freetype-2.12.1";

TextVertex :: struct
{
    position:   Vector3;
    color:      Vector4;
    uv:         Vector2;
}

Shader :: struct
{
    program : GLuint;
}
TestShader :: struct
{
    using shader: Shader;

    positionAttrib : GLint;
    colorAttrib : GLint;
    uvAttrib : GLint;

    projectionUni : GLint;
    glyphSamplerUni : GLint;
}
GridShader :: struct
{
    using shader: Shader;

    glyphSamplerUni :      GLint;
    constantsBlockUni:     GLuint;
    constantsBufferHandle: GLuint;
    cellsBlockUni:         [..] GLuint;
    cellsBufferHandle:     GLuint;
    cellsSamplerUni:       GLint;
    cellsTexture:          GLuint;
    maxCellCount:          s32;
}


LOG_BUFFER_SIZE :: 512;

PREFIX_V :: #string END
#version 330 core
#define VERTEX_SHADER
#define OUT_IN out
END

PREFIX_F :: #string END
#version 330 core
#define FRAGMENT_SHADER
#define OUT_IN in
END

CreateAndCompileShader :: ( shaderType : GLenum, shaderString: string, prefix: string, header: string = "" ) -> GLuint
{
    shaderObj := glCreateShader( shaderType );

    shaders: [3] *u8;
    lengths: [3] s32;

    shaders[0] = prefix.data;
    shaders[1] = header.data;
    shaders[2] = shaderString.data;
    lengths[0] = xx prefix.count;
    lengths[1] = xx header.count;
    lengths[2] = xx shaderString.count;

    glShaderSource( shaderObj, 3, shaders.data, lengths.data );
    glCompileShader( shaderObj );

    success : GLint;
    glGetShaderiv( shaderObj, GL_COMPILE_STATUS, *success );

    if !success
    {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetShaderInfoLog( shaderObj, log_data.count, null, log_data.data );
        print( "%", to_string( log_data.data ) );
        return 0;
    }

    return shaderObj;
}

BuildGridShaderProgram :: ( shader: *GridShader, state: OpenGLState ) -> bool
{
GRID_SHADER :: #string END

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
        Cell cell = CellFromTextureIndex( cellIndex );

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
END

    //builder: String_Builder;
    //builder.allocator = temp;
    //init_string_builder( *builder );

    // TODO #if RELEASE etc
    // TODO Hot reloading
    gridShader := GRID_SHADER;
    //gridShader := read_entire_file( "../src/text_grid.glsl", zero_terminated = true );

    // Build a header with some defines
    cellsPerPage := state.maxUniformBlockSize / size_of(RendererCell);
    assert( IsPowerOfTwo( cellsPerPage ) );
    //append( *builder, tprint( "#define USE_TEXTURE_BUFFER %\n", ifx USE_TEXTURE_BUFFER then 1 else 0 ) );
    //append( *builder, tprint( "#define CELLS_PER_PAGE_BITS %\n", Log2( cellsPerPage ) ) );

    vShader := CreateAndCompileShader( GL_VERTEX_SHADER, gridShader, PREFIX_V );
    //fShader := CreateAndCompileShader( GL_FRAGMENT_SHADER, gridShader, PREFIX_F, builder_to_string( *builder ) );
    fShader := CreateAndCompileShader( GL_FRAGMENT_SHADER, gridShader, PREFIX_F );
    if !vShader || !fShader
        return false;

    program := glCreateProgram();
    glAttachShader( program, vShader );
    glAttachShader( program, fShader );
    glLinkProgram( program );

    success : GLint = 0;
    glGetProgramiv( program, GL_LINK_STATUS, *success );

    if !success
    {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog( program, log_data.count, null, log_data.data );
        print( "%", to_string( log_data.data ) );
        return false;
    } 

    glDeleteShader( vShader );
    glDeleteShader( fShader );

    shader.program = program;
    glUseProgram( shader.program );    

    shader.glyphSamplerUni = glGetUniformLocation( program, "glyphSampler" );
    if shader.glyphSamplerUni == -1
        print( "Couldn't bind uniform 'glyphSampler'\n" );

    // Uniform buffer object for constants
    shader.constantsBlockUni = glGetUniformBlockIndex( shader.program, "ConstantsBlock" );
    assert( shader.constantsBlockUni != GL_INVALID_INDEX );
    // Bind it to binding point 0
    // See 'Using uniform buffers' in https://learnopengl.com/Advanced-OpenGL/Advanced-GLSL
    glUniformBlockBinding( shader.program, shader.constantsBlockUni, 0 );
    // And its buffer
    glGenBuffers( 1, *shader.constantsBufferHandle );
    glBindBuffer( GL_UNIFORM_BUFFER, shader.constantsBufferHandle );
    glBufferData( GL_UNIFORM_BUFFER, size_of(RendererState.Constants), null, GL_STREAM_DRAW );
    glBindBufferBase( GL_UNIFORM_BUFFER, 0, shader.constantsBufferHandle );

    #if USE_TEXTURE_BUFFER
    {
        MAX_TEXTURE_CELLS :: 128 * 1024;
        shader.maxCellCount = state.maxTextureBufferSize / size_of(RendererCell);
        print( "Max supported cell count (TBO): % / %\n", MAX_TEXTURE_CELLS, shader.maxCellCount );
        // Arbitrarily limit the max size just so that our buffer is not hundreds of Mb big
        shader.maxCellCount = min( shader.maxCellCount, MAX_TEXTURE_CELLS );

        glGenBuffers( 1, *shader.cellsBufferHandle );
        glBindBuffer( GL_TEXTURE_BUFFER, shader.cellsBufferHandle );
        glBufferData( GL_TEXTURE_BUFFER, shader.maxCellCount * size_of(RendererCell), null, GL_STREAM_DRAW );

        glGenTextures( 1, *shader.cellsTexture );
        glActiveTexture( GL_TEXTURE1 );
        glBindTexture( GL_TEXTURE_BUFFER, shader.cellsTexture );
        glTexBuffer( GL_TEXTURE_BUFFER, GL_RGBA32UI, shader.cellsBufferHandle );

        shader.cellsSamplerUni = glGetUniformLocation( shader.program, "cellsSampler" );
        glUniform1i( shader.cellsSamplerUni, 1 );
    }
    else
    {
        // Uniform buffer objects for cells
        // We already used a block for the ConstantsBlock above
        cellPageCount := state.maxUniformArrayCount - 1;
        // TODO Cap minimum font size based on this!
        shader.maxCellCount = cellPageCount * cellsPerPage;
        print( "Max supported cell count (UBO): % (in % pages)\n", shader.maxCellCount, cellPageCount );

        // Create a single buffer to map across all of them
        glGenBuffers( 1, *shader.cellsBufferHandle );
        glBindBuffer( GL_UNIFORM_BUFFER, shader.cellsBufferHandle );
        glBufferData( GL_UNIFORM_BUFFER, shader.maxCellCount * size_of(RendererCell), null, GL_STREAM_DRAW );

        // Map the individual pages
        bufferOffset := 0;
        pageSize := cellsPerPage * size_of(RendererCell);
        for 0..cellPageCount-1
        {
            blockName := tprint( "CellsBlock[%]\0", it );
            array_add( *shader.cellsBlockUni, glGetUniformBlockIndex( shader.program, blockName.data ) );
            assert( shader.cellsBlockUni[it] != GL_INVALID_INDEX );

            bindingIdx := cast(GLuint)(it + 1);
            glUniformBlockBinding( shader.program, shader.cellsBlockUni[it], bindingIdx );
            glBindBufferRange( GL_UNIFORM_BUFFER, bindingIdx, shader.cellsBufferHandle, bufferOffset, pageSize );
            bufferOffset += pageSize;
        }
    }

    DumpGLErrors( "shader" );

    return true;
}

BuildTestShaderProgram :: ( shader: *TestShader ) -> bool
{
TEST_SHADER :: #string END

OUT_IN vec2 TextureCoords;
OUT_IN vec4 iterated_color;


#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;

uniform mat4 projection;

void main() {
    gl_Position     = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color  = vert_color;
    TextureCoords   = vert_uv0;
}
#endif // VERTEX_SHADER


#ifdef FRAGMENT_SHADER
out vec4 color;

uniform sampler2D glyphSampler;
uniform vec4 text_color;

void main () {
    vec4 sample = texture(glyphSampler, TextureCoords);
    // TODO Swicth based on whether subpixel rendering is enabled
    //color = vec4(iterated_color.xyz, sample.r * iterated_color.a); // text_color * sample;
    color = vec4( sample.rgb, 1 );
}
#endif // FRAGMENT_SHADER
END

    vShader := CreateAndCompileShader( GL_VERTEX_SHADER, TEST_SHADER, PREFIX_V );
    fShader := CreateAndCompileShader( GL_FRAGMENT_SHADER, TEST_SHADER, PREFIX_F );
    if !vShader || !fShader
        return false;

    program := glCreateProgram();
    glAttachShader( program, vShader );
    glAttachShader( program, fShader );
    glLinkProgram( program );

    success : GLint = 0;
    glGetProgramiv( program, GL_LINK_STATUS, *success );

    if !success
    {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog( program, log_data.count, null, log_data.data );
        print( "%", to_string( log_data.data ) );
        return false;
    } 

    glDeleteShader( vShader );
    glDeleteShader( fShader );

    shader.program = program;
    glUseProgram( shader.program );    

    textVertex: *TextVertex: null;
    shader.positionAttrib = glGetAttribLocation( program, "vert_position" );
    if shader.positionAttrib == -1
        print( "Couldn't bind attribute 'vert_position'\n" );
    else
    {
        glEnableVertexAttribArray( xx shader.positionAttrib );
        glVertexAttribPointer( xx shader.positionAttrib,    3, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.position );
    }

    shader.colorAttrib    = glGetAttribLocation( program, "vert_color" );
    if shader.colorAttrib == -1
        print( "Couldn't bind attribute 'vert_color'\n" );
    else
    {
        glEnableVertexAttribArray( xx shader.colorAttrib );
        glVertexAttribPointer( xx shader.colorAttrib,       4, GL_FLOAT, GL_TRUE,  size_of(TextVertex), xx *textVertex.color );
    }

    shader.uvAttrib       = glGetAttribLocation( program, "vert_uv0" );
    if shader.uvAttrib == -1
        print( "Couldn't bind attribute 'vert_uv0'\n" );
    else
    {
        glEnableVertexAttribArray( xx shader.uvAttrib );
        glVertexAttribPointer( xx shader.uvAttrib,          2, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.uv );
    }

    shader.projectionUni  = glGetUniformLocation( program, "projection" );
    if shader.projectionUni == -1
        print( "Couldn't bind uniform 'projection'\n" );
    shader.glyphSamplerUni = glGetUniformLocation( program, "glyphSampler" );
    if shader.glyphSamplerUni == -1
        print( "Couldn't bind uniform 'glyphSampler'\n" );

    DumpGLErrors( "shader" );

    return true;
}

OpenGLAllocateTexture :: ( data: *void, width: int, height: int, filtered: bool, optionalHandle: *void ) -> GLuint
{
    result: *void;

    textureHandle: GLuint;
    if( optionalHandle )
        textureHandle = cast(GLuint)optionalHandle;
    else
        glGenTextures( 1, *textureHandle );

    glBindTexture( GL_TEXTURE_2D, textureHandle );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    // Use GL_LINEAR_MIPMAP_LINEAR?
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, xx ifx filtered GL_LINEAR else GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, xx ifx filtered GL_LINEAR else GL_NEAREST );

    if( optionalHandle )
        glTexSubImage2D( GL_TEXTURE_2D, 0, 0, 0, xx width, xx height, GL_RGBA, GL_UNSIGNED_BYTE, data );
    else
        glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA8, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data );

    glGenerateMipmap( GL_TEXTURE_2D );

    return textureHandle;
}

