
v2 :: Vector2;
v3 :: Vector3;
v2s :: struct
{
    x, y : s32;
}
v2u :: struct
{
    x, y : u32;
}

// TODO Move to our own math module
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
    gl_create_context( window, 3, 3, compatibility = false, debug = true );

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
    glEnable( GL_BLEND );
    glBlendEquation( GL_FUNC_ADD );
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
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


LoadedFace :: struct
{
    glyphs     : [126-32+1] Glyph;
    face       : *FT_Face;
    bbox       : v2s;
    advance    : s32;
    lineHeight : s32;
    descender  : s32;   // Absolute value
    texture    : u32;
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

    // NOTE Using the bbox for the atlas is technically correct as that guarantees to provide enough space for all the font's glyphs
    // However in the simple grid shader we're using, we need glyphs in the atlas to be rendered in the same grid they'll be placed into in the final image
    // This is mostly unimportant when dealing with ASCII only, but it will become more relevant when we support unicode
    pixels_w := FT_MulFix( (face.bbox.xMax - face.bbox.xMin), face.size.metrics.x_scale ) / 64.0;
    pixels_h := FT_MulFix( (face.bbox.yMax - face.bbox.yMin), face.size.metrics.y_scale ) / 64.0;
    print( "Font bbox: % x %\n", pixels_w, pixels_h );
    loadedFace.bbox = .{ xx ceil( pixels_w ), xx ceil( pixels_h ) };

    // TODO Seems to still be necessary even with a Po2 1024x1024 texture size?
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glGenTextures( 1, *loadedFace.texture );
    glBindTexture( GL_TEXTURE_2D, loadedFace.texture );
    // TODO Should probably check pixel_mode in the bitmap
    // TODO According to https://freetype.org/freetype2/docs/tutorial/step1.html this needs to be rendered with gamma correction
    glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, TEX_ATLAS_SIZE, TEX_ATLAS_SIZE, 0, GL_RED, GL_UNSIGNED_BYTE, null );

    // Load glyphs for ASCII
    x, y : s32 = 0;
    xoffset, yoffset : s32 = 0;
    baseline := loadedFace.lineHeight - loadedFace.descender;
    for 32..126
    {
        // TODO For subpixel rendering, or the flags with FT_LOAD_TARGET_LCD here
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
        g.index   = .{ x, y };
        g.offset  = .{ xoffset, yoffset };
        g.size    = .{ cast(s32) face.glyph.bitmap.width, cast(s32) face.glyph.bitmap.rows };
        g.bearing = .{ face.glyph.bitmap_left, face.glyph.bitmap_top };

        //print( "Loaded character %: %\n", it, loadedFace.glyphs[ it - 32 ] );

        x += 1;
        xoffset += loadedFace.advance;
        // Conservatively break the line when one more full-width glyph won't fit
        if xoffset + loadedFace.advance > TEX_ATLAS_SIZE
        {
            y += 1;
            // TODO This is probably still too much.. maybe use the font's pixel height?
            yoffset += loadedFace.lineHeight;
            assert( yoffset + loadedFace.lineHeight <= TEX_ATLAS_SIZE );

            x = 0;
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

RendererState :: struct
{
    cells : [] RendererCell;

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


// Disable to use previous path using a collection of contiguously-mapped uniform blocks (UBOs)
// Doesn't seem to offer a real speed advantage (most likely due to the limitation of using a constant expression to index them),
// although it seems marginally faster on Intel hardware, but it's also pretty limited in the maximum size of cell buffer it can fit,
// and will still be insufficient for fullscreen windows with a small font size
USE_TEXTURE_BUFFER :: true;

OpenGLRender :: ( state: *OpenGLState, face: LoadedFace, renderer: RendererState )
{
    // TODO scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fbWidth := state.windowWidth; // * io.DisplayFramebufferScale.x);
    fbHeight := state.windowHeight; // * io.DisplayFramebufferScale.y);
    glViewport( 0, 0, xx fbWidth, xx fbHeight );

    glUseProgram( state.gridShader.program );    

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, face.texture );  // Bind handle to slot 0.
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
    glUniform1i( state.gridShader.glyphSamplerUni, 0 );

    glBindBuffer( GL_UNIFORM_BUFFER, state.gridShader.constantsBufferHandle );
    glBufferSubData( GL_UNIFORM_BUFFER, 0, size_of(RendererState.Constants), *renderer.constants );

    #if USE_TEXTURE_BUFFER
    {
        glBindBuffer( GL_TEXTURE_BUFFER, state.gridShader.cellsBufferHandle );
        // This was faster than mapping the buffer & memcpying in the tests
        glBufferSubData( GL_TEXTURE_BUFFER, 0, renderer.cells.count * size_of(RendererCell), renderer.cells.data );
    }
    else
    {
        glBindBuffer( GL_UNIFORM_BUFFER, state.gridShader.cellsBufferHandle );
        glBufferSubData( GL_UNIFORM_BUFFER, 0, renderer.cells.count * size_of(RendererCell), renderer.cells.data );
    }

    glDrawArrays( GL_TRIANGLE_STRIP, 0, 4 );

    DumpGLErrors( "OpenGLRender" );
}

// For testing
// Draw a text string with the given font by issuing a separate quad per glyph
OpenGLDrawTextWithFace :: ( state: *OpenGLState, text: string, xBase: float, yBase: float, face: LoadedFace )
{
    DrawLetterQuad :: ( character: u8, xBase: float, yBase: float, glyph: Glyph, face: LoadedFace, vertices: *[6] TextVertex )
    {
        white :: #run make_vector4( 1, 1, 1, 1 );
        red :: #run make_vector4( 1, 0, 0, 1 );
        green :: #run make_vector4( 0, 1, 0, 1 );
        blue :: #run make_vector4( 0, 0, 1, 1 );

        x := xBase;
        y := yBase;

        w := face.advance;
        h := face.lineHeight;

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
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

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

        DrawLetterQuad( <<c, xBase, yBase, <<glyph, face, *vertices );

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
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

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
    glUniform1i( state.testShader.glyphSamplerUni, 0 );

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

Glyph :: struct
{
    index:   v2s;
    offset:  v2s;
    size:    v2s;
    bearing: v2s;
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

// Passed from outside code
#define CELLS_PER_PAGE (1 << CELLS_PER_PAGE_BITS)
#define CELLS_PER_PAGE_MASK (CELLS_PER_PAGE - 1)

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
};

// NOTE Since they're elements in an array, before 4.3 there seems to be no way of avoiding having a minimum sizeof(Cell) of 16!
struct Cell
{
    uint glyphIndex;
    // NOTE Colors are always considered sRGB. Cannot do the linear conversion on the CPU while still keeping them packed
    // See https://blog.demofox.org/2018/03/10/dont-convert-srgb-u8-to-linear-u8/
    uint foregroundColor;
    uint backgroundColor;
    uint _padding;
};

// This amounts to 12 UBOs of 65536 bytes, which is supposedly the minimum guaranteed by the spec.
// TODO Test on old cards!!
layout (std140) uniform CellsBlock
{
    Cell cells[CELLS_PER_PAGE];
} cellPages[12];


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

Cell CellFromBufferIndex( ivec2 cellIndex )
{
    int idx = cellIndex.y * cellCount.x + cellIndex.x;
    int cellPage = idx >> CELLS_PER_PAGE_BITS;
    int indexInPage = idx & CELLS_PER_PAGE_MASK;

    Cell cell;
    // HACK Apparently you can only index an array of blocks using a constant expression, so.. yeah..
    if( cellPage == 0 )
        cell = cellPages[0].cells[indexInPage];
    else if( cellPage == 1 )
        cell = cellPages[1].cells[indexInPage];
    else if( cellPage == 2 )
        cell = cellPages[2].cells[indexInPage];
    else if( cellPage == 3 )
        cell = cellPages[3].cells[indexInPage];
    else if( cellPage == 4 )
        cell = cellPages[4].cells[indexInPage];
    else if( cellPage == 5 )
        cell = cellPages[5].cells[indexInPage];
    else if( cellPage == 6 )
        cell = cellPages[6].cells[indexInPage];
    else if( cellPage == 7 )
        cell = cellPages[7].cells[indexInPage];
    else if( cellPage == 8 )
        cell = cellPages[8].cells[indexInPage];
    else if( cellPage == 9 )
        cell = cellPages[9].cells[indexInPage];
    else if( cellPage == 10 )
        cell = cellPages[10].cells[indexInPage];
    else if( cellPage == 11 )
        cell = cellPages[11].cells[indexInPage];

    // TODO Just so its easy to see when we're using this path
    cell.foregroundColor = 0xFF0000u;
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
    #if USE_TEXTURE_BUFFER
        Cell cell = CellFromTextureIndex( cellIndex );
    #else
        Cell cell = CellFromBufferIndex( cellIndex );
    #endif

        ivec2 glyphPos = UnpackGlyphXY(cell.glyphIndex) * cellSize;

        vec2 atlasPos = vec2( glyphPos + cellPos );
        vec4 glyphTexel = texture(glyphSampler, atlasPos / 1024);

        vec3 background = ColorToLinear( UnpackColor( cell.backgroundColor ) );
        vec3 foreground = ColorToLinear( UnpackColor( cell.foregroundColor ) );
        //vec3 Blink = UnpackColor(BlinkModulate);

        //if((cell.foreground >> 28) & 1) foreground *= Blink;
        //if((cell.foreground >> 25) & 1) foreground *= 0.5;

        // TODO Sub-pixel rendering
        // https://www.puredevsoftware.com/blog/2019/01/22/sub-pixel-gamma-correct-font-rendering/
        // More reading: https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html
        // https://freetype.org/freetype2/docs/hinting/text-rendering-general.html

        // 1-channel texture so alpha is in the r component
        result = (1 - glyphTexel.r) * background + glyphTexel.r * foreground;
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

    builder: String_Builder;
    builder.allocator = temp;
    init_string_builder( *builder );

    // Build a header with some defines
    cellsPerPage := state.maxUniformBlockSize / size_of(RendererCell);
    assert( IsPowerOfTwo( cellsPerPage ) );
    append( *builder, tprint( "#define USE_TEXTURE_BUFFER %\n", ifx USE_TEXTURE_BUFFER then 1 else 0 ) );
    append( *builder, tprint( "#define CELLS_PER_PAGE_BITS %\n", Log2( cellsPerPage ) ) );

    vShader := CreateAndCompileShader( GL_VERTEX_SHADER, GRID_SHADER, PREFIX_V );
    fShader := CreateAndCompileShader( GL_FRAGMENT_SHADER, GRID_SHADER, PREFIX_F, builder_to_string( *builder ) );
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
        // Arbitrarily limit the max size just so that our buffer is not hundreds of Mb big
        shader.maxCellCount = min( state.maxTextureBufferSize / size_of(RendererCell), MAX_TEXTURE_CELLS );
        print( "Max supported cell count (TBO): %\n", shader.maxCellCount );

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
    color = vec4(iterated_color.xyz, sample.r * iterated_color.a); // text_color * sample;
    if (sample.a < .3)  discard;
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

