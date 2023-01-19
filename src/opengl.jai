OpenGLState :: struct
{
    windowWidth, windowHeight : float;

    vertexBuffer : GLuint;
    indexBuffer : GLuint;

    textShader : Shader;
    testTextShader : Shader;

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

    shaderOk := BuildShaderProgram( *state.textShader, TEXT_SHADER );
    assert( shaderOk );
    shaderOk = BuildShaderProgram( *state.testTextShader, TEST_TEXT_SHADER );
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

    glUseProgram( state.textShader.program );    

    // Enable default text shader's attributes
    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glEnableVertexAttribArray( xx state.textShader.positionAttrib );
    glEnableVertexAttribArray( xx state.textShader.colorAttrib );
    glEnableVertexAttribArray( xx state.textShader.uvAttrib );

    textVertex: *TextVertex: null;
    glVertexAttribPointer( xx state.textShader.positionAttrib,    3, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.position );
    glVertexAttribPointer( xx state.textShader.colorAttrib,       4, GL_FLOAT, GL_TRUE,  size_of(TextVertex), xx *textVertex.color );
    glVertexAttribPointer( xx state.textShader.uvAttrib,          2, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.uv );

    glUseProgram( state.testTextShader.program );    

    // Enable default text shader's attributes
    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glEnableVertexAttribArray( xx state.testTextShader.positionAttrib );
    glEnableVertexAttribArray( xx state.testTextShader.colorAttrib );
    glEnableVertexAttribArray( xx state.testTextShader.uvAttrib );

    glVertexAttribPointer( xx state.testTextShader.positionAttrib,    3, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.position );
    glVertexAttribPointer( xx state.testTextShader.colorAttrib,       4, GL_FLOAT, GL_TRUE,  size_of(TextVertex), xx *textVertex.color );
    glVertexAttribPointer( xx state.testTextShader.uvAttrib,          2, GL_FLOAT, GL_FALSE, size_of(TextVertex), xx *textVertex.uv );

    DumpGLErrors( "shader" );

    return true;
}

v2i :: struct
{
    x, y : s32;
}

Glyph :: struct
{
    size : v2i;
    bearing : v2i;
    advance : float;
    texture : u32;
}

OpenGLDrawTextWithGlyphs :: ( state: *OpenGLState, text: string, xBase: float, yBase: float, face: FT_Face )
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

        (<<vertices)[1] = .{ position = make_vector3( x, y, 0 ), color = white, uv = .{ 0, 0 } };
        (<<vertices)[0] = .{ position = make_vector3( x, y + h, 0 ), color = white, uv = .{ 0, 1 } };
        (<<vertices)[2] = .{ position = make_vector3( x + w, y, 0 ), color = white, uv = .{ 1, 0 } };

        (<<vertices)[4] = .{ position = make_vector3( x + w, y, 0 ), color = white, uv = .{ 1, 0 } };
        (<<vertices)[3] = .{ position = make_vector3( x, y + h, 0 ), color = white, uv = .{ 0, 1 } };
        (<<vertices)[5] = .{ position = make_vector3( x + w, y + h, 0 ), color = white, uv = .{ 1, 1 } };
    }

    // TODO Compare by some kind of id?
    if testLoadedFace.face != *face
    {
        testLoadedFace.face = *face;

        // NOTE This is required for arbitrary-sized textures, will not be needed for a "normal" 1024 (or whatever) atlas
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

        // Load glyphs for ASCII
        for 32..126
        {
            error := FT_Load_Char( face, cast(u32) it, FT_LOAD_RENDER );
            if error
            {
                print( "Failed to load glyph for character %\n", it );
                continue;
            }

            texture : u32;
            glGenTextures( 1, *texture );
            glBindTexture( GL_TEXTURE_2D, texture );
            // TODO Should probably check pixel_mode in the bitmap
            glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, 
                          face.glyph.bitmap.width, face.glyph.bitmap.rows,
                          0, GL_RED, GL_UNSIGNED_BYTE, face.glyph.bitmap.buffer );

            advance := face.glyph.advance.x / 64.0;
            if testLoadedFace.advance == 0
                testLoadedFace.advance = advance;
            assert( advance == testLoadedFace.advance, "Font has non-uniform advance" );

            testLoadedFace.glyphs[ it - 32 ] =
            .{
                .{ cast(s32) face.glyph.bitmap.width, cast(s32) face.glyph.bitmap.rows },
                .{ face.glyph.bitmap_left, face.glyph.bitmap_top },
                advance,
                texture,
            };

            //print( "Loaded character %: %\n", it, testLoadedFace.glyphs[ it - 32 ] );
        }
    }

    vertices : [6] TextVertex;

    glActiveTexture( GL_TEXTURE0 );
    glUseProgram( state.textShader.program );    
    glUniform1i( state.textShader.textSamplerUni, 0 );

    projection := orthographic_projection_matrix( 0, state.windowWidth, state.windowHeight, 0, 0, 1 );
    glUniformMatrix4fv( state.textShader.projectionUni, 1, GL_TRUE, *projection._11 );

    c := text.data;
    while c < text.data + text.count
    {
        glyph := *testLoadedFace.glyphs[ <<c - 32 ];
        glBindTexture( GL_TEXTURE_2D, glyph.texture );  // Bind handle to slot 0.
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
        // TODO Not sure whether we ever want any filtering or not
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );

        DrawLetterQuad( <<c, xBase, yBase, <<glyph, *vertices );

        glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
        glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
        glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );

        xBase += glyph.advance;
        c += 1;
    }
}

OpenGLDrawFontQuads :: ( state: *OpenGLState, font: *Simp.Dynamic_Font, color := Vector4.{1, 1, 1, 1} )
{
    vertices : [..] TextVertex;

    draw_letter_quad :: ( font: *Simp.Dynamic_Font, quad: Simp.Font_Quad, color: Vector4, windowHeight: float, vertices: *[..] TextVertex )
    {
/*
        // @Robustness: These assume our coordinates are in screenspace...
        if quad.x1 < 0 return;
        if quad.x0 > cast(float) render_target_width return;
        if quad.y1 < 0 return;
        if quad.y0 > cast(float) render_target_height return;
*/
        page := quad.glyph.page;
        
        if page.bitmap_data.width  <= 1 return;
        if page.bitmap_data.height <= 1 return;

        using quad;
        uv0 := make_vector2(u0, v0);
        uv1 := make_vector2(u1, v0);
        uv2 := make_vector2(u1, v1);
        uv3 := make_vector2(u0, v1);
        
        // NOTE Invert y coord
        array_add( vertices, .{ position = make_vector3( p0.x, windowHeight - p0.y, 0 ), color = color, uv = uv0 } );
        array_add( vertices, .{ position = make_vector3( p1.x, windowHeight - p1.y, 0 ), color = color, uv = uv1 } );
        array_add( vertices, .{ position = make_vector3( p2.x, windowHeight - p2.y, 0 ), color = color, uv = uv2 } );

        array_add( vertices, .{ position = make_vector3( p0.x, windowHeight - p0.y, 0 ), color = color, uv = uv0 } );
        array_add( vertices, .{ position = make_vector3( p2.x, windowHeight - p2.y, 0 ), color = color, uv = uv2 } );
        array_add( vertices, .{ position = make_vector3( p3.x, windowHeight - p3.y, 0 ), color = color, uv = uv3 } );
    }

    
    last_texture: s64 = -1;

    array_reserve( *vertices, font.current_quads.count * 6 );
    for quad, i: font.current_quads
    {
        page := quad.glyph.page;
        map  := *page.texture;
        
        if page.dirty
        {
            print( "Loading glyph texture from %\n", page.bitmap_data );
            Simp.texture_load_from_bitmap( map, page.bitmap_data );
            page.dirty = false;
        }
 
        if map.gl_handle != last_texture
        {
            handle := map.gl_handle;
            last_texture = handle;

            glActiveTexture( GL_TEXTURE0 );
            glBindTexture( GL_TEXTURE_2D, handle );  // Bind handle to slot 0.
            // TODO Generates invalid value (due to GL version perhaps?)
            //glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 0 );
            glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
            glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
            glUniform1i( state.testTextShader.textSamplerUni, 0 );
        }

        draw_letter_quad( font, quad, color, state.windowHeight, *vertices );
    }

    glBindBuffer( GL_ARRAY_BUFFER, state.vertexBuffer );
    glBufferData( GL_ARRAY_BUFFER, vertices.count * size_of(TextVertex), vertices.data, GL_STREAM_DRAW );
    glDrawArrays( GL_TRIANGLES, 0, xx vertices.count );
}

testFont: *Simp.Dynamic_Font;
//prevOrthoMatrix: Matrix4;
OpenGLDrawFSQTest :: ( state: *OpenGLState, text: string )
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
    glUseProgram( state.testTextShader.program );    
    glUniformMatrix4fv( state.testTextShader.projectionUni, 1, GL_TRUE, *projection._11 );

    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, state.whiteTextureHandle );  // Bind handle to slot 0.
    glUniform1i( state.testTextShader.textSamplerUni, 0 );

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

    // Draw some text
    if !testFont
    {
        testFont = Simp.get_font_at_size("data/fonts", "consolas_nf_regular.ttf", 58 );
        if( testFont == null )
        {
            print( "Failed loading font 'data/fonts/consolas_nf_regular.ttf'\n" );
            exit( 1 );
        }
    }

    Simp.convert_to_temporary_glyphs( testFont, text, 0 );
    Simp.generate_quads_for_prepared_text( testFont, 100, 600, 0 );
    OpenGLDrawFontQuads( state, testFont ); //, .{ 0, 0, 0, 1 } );
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

LoadedFace :: struct
{
    face : *FT_Face;
    advance : float;
    glyphs : [126-32+1] Glyph;
}
testLoadedFace : LoadedFace;


TEXT_SHADER :: #string END

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

TEST_TEXT_SHADER :: #string END

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
    color = vec4(iterated_color.xyz, sample.a * iterated_color.a); // text_color * sample;
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
            // TODO 
            //log( "%", to_string( log_data.data ), flags=.ERROR );
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
        // TODO 
        //log( "%", to_string( log_data.data ), flags=.ERROR );
        return false;
    } 

    glDeleteShader( vShader );
    glDeleteShader( fShader );

    shader.program        = program;
    shader.positionAttrib = glGetAttribLocation( program, "vert_position" );
    shader.colorAttrib    = glGetAttribLocation( program, "vert_color" );
    shader.uvAttrib       = glGetAttribLocation( program, "vert_uv0" );
    shader.projectionUni  = glGetUniformLocation( program, "projection" );
    shader.textSamplerUni = glGetUniformLocation( program, "text_sampler" );

    // TODO Log appropriately
    if( shader.positionAttrib == -1 || shader.colorAttrib == -1 || shader.uvAttrib == -1
        || shader.projectionUni == -1 || shader.textSamplerUni == -1 )
        return false;

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

