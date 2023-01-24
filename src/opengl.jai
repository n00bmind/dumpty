OpenGLState :: struct
{
    windowWidth, windowHeight : float;

    vertexBuffer : GLuint;
    indexBuffer : GLuint;

    gridShader : Shader;
    testShader : Shader;

    white : u32;
    whiteTextureHandle : GLuint;
}

Shader :: struct
{
    program : GLuint;

    positionAttrib : GLint;
    colorAttrib : GLint;
    uvAttrib : GLint;

    projectionUni : GLint;
    textSamplerUni : GLint;
}

OpenGLInit :: ( state: *OpenGLState, window: Window_Type ) -> bool
{
    // TODO Error handling!
    gl_create_context( window, 3, 3,
                       compatibility = false, debug = true );

    gl_load( *gl );
    gl_enable_debug_output( break_on_error = true );

    dummyVAO: GLuint;
    glGenVertexArrays( 1, *dummyVAO );
    glBindVertexArray( dummyVAO );

    glGenBuffers( 1, *state.vertexBuffer );
    glGenBuffers( 1, *state.indexBuffer );

    DumpGLErrors( "context" );

    shaderOk := BuildShaderProgram( *state.gridShader, GRID_SHADER );
    assert( shaderOk );
    shaderOk = BuildShaderProgram( *state.testShader, TEST_SHADER );
    assert( shaderOk );

    // Create a white texture
    state.white = 0xFFFFFFFF;
    state.whiteTextureHandle = OpenGLAllocateTexture( cast(*u8)*state.white, 1, 1, true, null );

    // Setup render state: alpha-blending enabled, no face culling, no depth testing,
    glEnable( GL_BLEND );
    glBlendEquation( GL_FUNC_ADD );
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
    glDisable( GL_CULL_FACE );
    glDisable( GL_DEPTH_TEST );

    glUseProgram( state.gridShader.program );    

    // Enable default text shader's attributes
    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glEnableVertexAttribArray( xx state.gridShader.positionAttrib );
    glEnableVertexAttribArray( xx state.gridShader.colorAttrib );
    glEnableVertexAttribArray( xx state.gridShader.uvAttrib );

    textVertex: *TextVertex: null;
    glVertexAttribPointer( xx state.gridShader.positionAttrib,    3, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.position );
    glVertexAttribPointer( xx state.gridShader.colorAttrib,       4, GL_FLOAT, GL_TRUE,  size_of(TextVertex), xx *textVertex.color );
    glVertexAttribPointer( xx state.gridShader.uvAttrib,          2, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.uv );

    glUseProgram( state.testShader.program );    

    // Enable default text shader's attributes
    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glEnableVertexAttribArray( xx state.testShader.positionAttrib );
    glEnableVertexAttribArray( xx state.testShader.colorAttrib );
    glEnableVertexAttribArray( xx state.testShader.uvAttrib );

    glVertexAttribPointer( xx state.testShader.positionAttrib,    3, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.position );
    glVertexAttribPointer( xx state.testShader.colorAttrib,       4, GL_FLOAT, GL_TRUE,  size_of(TextVertex), xx *textVertex.color );
    glVertexAttribPointer( xx state.testShader.uvAttrib,          2, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.uv );

    DumpGLErrors( "shader" );

    return true;
}


TEX_ATLAS_SIZE :: 1024;

// Loads a font from disk using Freetype and creates an atlas for it
OpenGLLoadFont :: ( path: string, pixelHeight: int ) -> LoadedFace, bool
{
    ft: FT_Library;
    error := FT_Init_FreeType( *ft );
    if error
    {
        print( "Failed initialising FreeType lib!" );
        return .{}, false;
    }

    fontData, success := read_entire_file( path );
    if !success
    {
        print( "Failed loading font '%'\n", path );
        return .{}, false;
    }

    face: FT_Face;
    error = FT_New_Memory_Face( ft, fontData.data, cast(s32) fontData.count, 0, *face );
    if error
    {
        print( "Failed parsing font '%'\n", path );
        return .{}, false;
    }

    error = FT_Set_Pixel_Sizes( face, 0, xx pixelHeight );
    assert(!error);

    
    loadedFace: LoadedFace;
    loadedFace.face = *face;
    loadedFace.lineHeight = cast(s32)(face.size.metrics.height / 64.0);
    print( "Font line height is %\n", loadedFace.lineHeight );
    // TODO Apparently relying on the ascender / descender is.. unreliable .. see https://freetype.org/freetype2/docs/tutorial/step2.html
    loadedFace.descender = abs( cast(s32)(face.size.metrics.descender / 64.0) );
    print( "Font descender is %\n", loadedFace.descender );

    // NOTE Using the bbox for the atlas is technically correct but wastes a lot of texture space.. however, memory is cheap?
    pixels_w := FT_MulFix( (face.bbox.xMax - face.bbox.xMin), face.size.metrics.x_scale ) / 64.0;
    pixels_h := FT_MulFix( (face.bbox.yMax - face.bbox.yMin), face.size.metrics.y_scale ) / 64.0;
    print( "Font bbox: % x %\n", pixels_w, pixels_h );
    loadedFace.bbox = .{ xx ceil( pixels_w ), xx ceil( pixels_h ) };

    // TODO Seems to still be necessary even with a "standard" 1024x1024 texture size?
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glGenTextures( 1, *loadedFace.texture );
    glBindTexture( GL_TEXTURE_2D, loadedFace.texture );
    // TODO Should probably check pixel_mode in the bitmap
    // TODO According to https://freetype.org/freetype2/docs/tutorial/step1.html this needs to be rendered with gamma correction
    glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, TEX_ATLAS_SIZE, TEX_ATLAS_SIZE, 0, GL_RED, GL_UNSIGNED_BYTE, null );

    // Load glyphs for ASCII
    xoffset, yoffset : s32 = 0;
    baseline := loadedFace.bbox.y - loadedFace.descender;
    for 32..126
    {
        error := FT_Load_Char( face, cast(u32) it, FT_LOAD_RENDER );
        if error
        {
            print( "Failed to load glyph for character %\n", it );
            continue;
        }

        glTexSubImage2D( GL_TEXTURE_2D, 0, xoffset + face.glyph.bitmap_left, yoffset + baseline - face.glyph.bitmap_top,
                         face.glyph.bitmap.width, face.glyph.bitmap.rows, GL_RED, GL_UNSIGNED_BYTE, face.glyph.bitmap.buffer );

        advance := cast(s32)(face.glyph.advance.x / 64.0);
        if loadedFace.advance == 0
        {
            loadedFace.advance = advance;
            print( "Font advance is %\n", loadedFace.advance );
        }
        assert( advance == loadedFace.advance, "Font has non-uniform advance" );

        g := *(loadedFace.glyphs[ it - 32 ]);
        g.offset  = .{ xoffset, yoffset };
        g.size    = .{ cast(s32) face.glyph.bitmap.width, cast(s32) face.glyph.bitmap.rows };
        g.bearing = .{ face.glyph.bitmap_left, face.glyph.bitmap_top };

        //print( "Loaded character %: %\n", it, loadedFace.glyphs[ it - 32 ] );

        xoffset += loadedFace.bbox.x;
        // Conservatively break the line when one more full-width glyph won't fit
        if xoffset + loadedFace.bbox.x > TEX_ATLAS_SIZE
        {
            yoffset += loadedFace.bbox.y;
            assert( yoffset + loadedFace.bbox.y <= TEX_ATLAS_SIZE );
            xoffset = 0;
        }
    }

    FT_Done_Face( face );
    FT_Done_FreeType( ft );

    return loadedFace, true;
}

RendererCell :: struct
{
    glyphIndex : u32;
    // NOTE Since we likely won't use the alpha on these, we could pack some flags in there
    foregroundColor : u32;
    backgroundColor : u32;

    _padding : u32;
}

RendererBuffer :: struct
{
    cells : [] RendererCell;
    xDim, yDim : u32;
    //firstLineY : u32;
}

OpenGLRender :: ( state: *OpenGLState, face: LoadedFace, buffer: RendererBuffer )
{
    glUseProgram( state.gridShader.program );    

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.gridShader.projectionUni, 1, GL_TRUE, *projection._11 );

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, face.texture );  // Bind handle to slot 0.
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
    glUniform1i( state.gridShader.textSamplerUni, 0 );

    // Uniform buffer object for cells
    // TODO Review all APIs
    cellsBlockUni : GLuint = glGetUniformBlockIndex( state.gridShader.program, "CellsBlock" );
    //print( "CellsBlock uniform: %\n", cellsBlockUni );
    //glUniformBlockBinding( state.gridShader.program, cellsBlockUni, 0 );

    //cellsBufferHandle : GLuint;
    //glGenBuffers( 1, *cellsBufferHandle );
    //glBindBuffer( GL_UNIFORM_BUFFER, cellsBufferHandle );
    //// TODO Read somewhere only glBufferSubData is needed per-frame, and this shouldn't be called again because it implies reallocating?
    //glBufferData( GL_UNIFORM_BUFFER, buffer.cells.count * size_of(RendererCell), null, GL_STREAM_DRAW );
    //glBindBufferBase( GL_UNIFORM_BUFFER, cellsBlockUni, cellsBufferHandle );
    //glBufferSubData( GL_UNIFORM_BUFFER, 0, buffer.cells.count * size_of(RendererCell), buffer.cells.data );

    vertices : [6] TextVertex;
    white :: #run make_vector4( 1, 1, 1, 1 );
    red :: #run make_vector4( 1, 0, 0, 1 );
    green :: #run make_vector4( 0, 1, 0, 1 );
    blue :: #run make_vector4( 0, 0, 1, 1 );

    // TODO Only need position now
    vertices[1] = .{ position = make_vector3( 0, 0, 0 ), color = white, uv = .{ 0, 0 } };
    vertices[0] = .{ position = make_vector3( 0, state.windowHeight, 0 ), color = white, uv = .{ 0, 1 } };
    vertices[2] = .{ position = make_vector3( state.windowWidth, 0, 0 ), color = white, uv = .{ 1, 0 } };

    vertices[4] = .{ position = make_vector3( state.windowWidth, 0, 0 ), color = white, uv = .{ 1, 0 } };
    vertices[3] = .{ position = make_vector3( 0, state.windowHeight, 0 ), color = white, uv = .{ 0, 1 } };
    vertices[5] = .{ position = make_vector3( state.windowWidth, state.windowHeight, 0 ), color = white, uv = .{ 1, 1 } };

    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
    glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );

    //DumpGLErrors( "OpenGLRender" );
}

// For testing
// Draw a text string with the given font by issuing a separate quad per glyph
OpenGLDrawTextWithFace :: ( state: *OpenGLState, text: string, xBase: float, yBase: float, face: LoadedFace )
{
    DrawLetterQuad :: ( character: u8, xBase: float, yBase: float, glyph: Glyph, vertices: *[6] TextVertex )
    {
        white :: #run make_vector4( 1, 1, 1, 1 );
        red :: #run make_vector4( 1, 0, 0, 1 );
        green :: #run make_vector4( 0, 1, 0, 1 );
        blue :: #run make_vector4( 0, 0, 1, 1 );

        x := xBase + glyph.bearing.x;
        y := yBase - glyph.bearing.y; 

        w := glyph.size.x;
        h := glyph.size.y;

        s := cast(float) TEX_ATLAS_SIZE;
        u0 := glyph.offset.x / s;
        v0 := glyph.offset.y / s;
        u1 := (glyph.offset.x + w) / s;
        v1 := (glyph.offset.y + h) / s;

        (<<vertices)[1] = .{ position = make_vector3( x, y, 0 ), color = white, uv = .{ u0, v0 } };
        (<<vertices)[0] = .{ position = make_vector3( x, y + h, 0 ), color = white, uv = .{ u0, v1 } };
        (<<vertices)[2] = .{ position = make_vector3( x + w, y, 0 ), color = white, uv = .{ u1, v0 } };

        (<<vertices)[4] = .{ position = make_vector3( x + w, y, 0 ), color = white, uv = .{ u1, v0 } };
        (<<vertices)[3] = .{ position = make_vector3( x, y + h, 0 ), color = white, uv = .{ u0, v1 } };
        (<<vertices)[5] = .{ position = make_vector3( x + w, y + h, 0 ), color = white, uv = .{ u1, v1 } };
    }


    vertices : [6] TextVertex;

    glActiveTexture( GL_TEXTURE0 );
    glUseProgram( state.testShader.program );    
    glUniform1i( state.testShader.textSamplerUni, 0 );

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.testShader.projectionUni, 1, GL_TRUE, *projection._11 );

    c := text.data;
    while c < text.data + text.count
    {
        glyph := *face.glyphs[ <<c - 32 ];
        glBindTexture( GL_TEXTURE_2D, face.texture );  // Bind handle to slot 0.
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );

        DrawLetterQuad( <<c, xBase, yBase, <<glyph, *vertices );

        glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
        glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
        glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );

        xBase += face.advance;
        c += 1;
    }
}

// For testing
// Draw atlas of the given font by issuing a quad of the same size as the full texture
// Font must be loaded already
OpenGLDrawAtlas :: ( state: *OpenGLState, face: LoadedFace )
{
    glUseProgram( state.testShader.program );    
    glUniform1i( state.testShader.textSamplerUni, 0 );

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.testShader.projectionUni, 1, GL_TRUE, *projection._11 );

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, face.texture );  // Bind handle to slot 0.
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );

    vertices : [6] TextVertex;
    white :: #run make_vector4( 1, 1, 1, 1 );
    red :: #run make_vector4( 1, 0, 0, 1 );
    green :: #run make_vector4( 0, 1, 0, 1 );
    blue :: #run make_vector4( 0, 0, 1, 1 );

    vertices[1] = .{ position = make_vector3( 0, 0, 0 ), color = white, uv = .{ 0, 0 } };
    vertices[0] = .{ position = make_vector3( 0, 1024, 0 ), color = white, uv = .{ 0, 1 } };
    vertices[2] = .{ position = make_vector3( 1024, 0, 0 ), color = white, uv = .{ 1, 0 } };

    vertices[4] = .{ position = make_vector3( 1024, 0, 0 ), color = white, uv = .{ 1, 0 } };
    vertices[3] = .{ position = make_vector3( 0, 1024, 0 ), color = white, uv = .{ 0, 1 } };
    vertices[5] = .{ position = make_vector3( 1024, 1024, 0 ), color = white, uv = .{ 1, 1 } };

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
    glUniform1i( state.testShader.textSamplerUni, 0 );

    DumpGLErrors( "frame setup" );

    //glClearColor( 0.15, 0.15, 0.2, 1.0 ); 
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

#import "Math";
Simp  :: #import "Simp";

TextVertex :: struct
{
    position:   Vector3;
    color:      Vector4;
    uv:         Vector2;
}

v2i :: struct
{
    x, y : s32;
}

Glyph :: struct
{
    offset : v2i;
    size : v2i;
    bearing : v2i;
}

LoadedFace :: struct
{
    glyphs     : [126-32+1] Glyph;
    face       : *FT_Face;
    bbox       : v2i;
    advance    : s32;
    lineHeight : s32;
    descender  : s32;   // Absolute value
    texture    : u32;
}


GRID_SHADER :: #string END

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

layout(origin_upper_left) in vec4 gl_FragCoord;
out vec4 color;

uniform sampler2D text_sampler;
//uniform vec4 text_color;

void main () {
    vec4 sample = texture(text_sampler, TextureCoords);
    color = vec4(iterated_color.xyz, sample.r * iterated_color.a); // text_color * sample;
    if (sample.a < .3)  discard;
}
#endif // FRAGMENT_SHADER
END

/*
struct Cell {
    uint glyphIndex;
    uint foregroundColor;
    uint backgroundColor;
    uint _padding;
};

// TODO This seems to be near the maximum for the GTX. Test on old cards!!
layout (std140) uniform CellsBlock {
    Cell cells[4096];
};

vec3 UnpackColor(uint packedColor)
{
    uint r = packedColor & 0xffu;
    uint g = (packedColor >> 8) & 0xffu;
    uint b = (packedColor >> 16) & 0xffu;

    return vec3(r, g, b) / 255.0;
}

void main ()
{
    vec2 topLeftMargin = vec2( 10, 10 );
    uvec2 cellSize = uvec2( 32, 68 ); // TODO
        uvec2 termSize = uvec2( 10, 10 );
    uvec2 cellIndex = uvec2( gl_FragCoord.xy - topLeftMargin ) / cellSize;
    uvec2 cellPos = uvec2( gl_FragCoord.xy - topLeftMargin ) % cellSize;

    vec3 result;
    if( (gl_FragCoord.x >= topLeftMargin.x) &&
        (gl_FragCoord.y >= topLeftMargin.y) &&
        (cellIndex.x < termSize.x) &&
        (cellIndex.y < termSize.y) )
    {
        Cell cell = cells[cellIndex.y * termSize.x + cellIndex.x];
        //uvec2 glyphPos = UnpackGlyphXY(cell.glyphIndex) * cellSize;
        uvec2 glyphPos = uvec2( 10, 0 ) * cellSize;

        uvec2 pixelPos = glyphPos + cellPos;
        // FIXME Normalize pos
        vec4 glyphTexel = texture(text_sampler, pixelPos);

        vec3 background = UnpackColor( cell.backgroundColor );
        vec3 foreground = UnpackColor( cell.foregroundColor );
        //vec3 Blink = UnpackColor(BlinkModulate);

        //if((cell.foreground >> 28) & 1) foreground *= Blink;
        //if((cell.foreground >> 25) & 1) foreground *= 0.5;

        // TODO: proper ClearType blending
        result = (1 - glyphTexel.a) * background + glyphTexel.rgb * foreground;
    }
    else
    {
        // TODO: margin color
        result = vec3( 0.1, 0.1, 0.1 );
    }

    color = vec4( result, 1 );
}

#endif // FRAGMENT_SHADER
END
*/

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

uniform sampler2D text_sampler;
uniform vec4 text_color;

void main () {
    vec4 sample = texture(text_sampler, TextureCoords);
    color = vec4(iterated_color.xyz, sample.r * iterated_color.a); // text_color * sample;
    if (sample.a < .3)  discard;
}
#endif // FRAGMENT_SHADER
END

BuildShaderProgram :: ( shader: *Shader, shaderString: string ) -> bool
{
    LOG_BUFFER_SIZE :: 512;
    
    CreateAndCompileShader :: ( shaderString: string, prefix: string, shaderType : GLenum ) -> GLuint
    {
        shaderObj := glCreateShader( shaderType );

        shaders: [2] *u8;
        lengths: [2] s32;

        shaders[0] = prefix.data;
        shaders[1] = shaderString.data;
        lengths[0] = xx prefix.count;
        lengths[1] = xx shaderString.count;

        glShaderSource( shaderObj, 2, shaders.data, lengths.data );
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
    
    vShader := CreateAndCompileShader( shaderString, PREFIX_V, GL_VERTEX_SHADER );
    fShader := CreateAndCompileShader( shaderString, PREFIX_F, GL_FRAGMENT_SHADER );
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

    shader.program        = program;
    shader.positionAttrib = glGetAttribLocation( program, "vert_position" );
    if shader.positionAttrib == -1
    {
        print( "Couldn't bind attribute 'vert_position'\n" );
        return false;
    }
    shader.colorAttrib    = glGetAttribLocation( program, "vert_color" );
    if shader.colorAttrib == -1
    {
        print( "Couldn't bind attribute 'vert_color'\n" );
        return false;
    }
    shader.uvAttrib       = glGetAttribLocation( program, "vert_uv0" );
    if shader.uvAttrib == -1
    {
        print( "Couldn't bind attribute 'vert_uv0'\n" );
        return false;
    }
    shader.projectionUni  = glGetUniformLocation( program, "projection" );
    if shader.projectionUni == -1
    {
        print( "Couldn't bind uniform 'projection'\n" );
        return false;
    }
    shader.textSamplerUni = glGetUniformLocation( program, "text_sampler" );
    if shader.textSamplerUni == -1
    {
        print( "Couldn't bind uniform 'text_sampler'\n" );
        return false;
    }

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

