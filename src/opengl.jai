OpenGLState :: struct
{
    vertexBuffer : GLuint;
    indexBuffer : GLuint;

    textShader : Shader;

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

    shaderOk := BuildShaderProgram( *state.textShader, SHADER_TEXT );
    assert( shaderOk );

    // Create a white texture
    state.white = 0xFFFFFFFF;
    state.whiteTextureHandle = OpenGLAllocateTexture( cast(*u8)*state.white, 1, 1, true, null );

    // Setup render state: alpha-blending enabled, no face culling, no depth testing,
    // TODO Review
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

    DumpGLErrors( "shader" );

    return true;
}

prevOrthoMatrix: Matrix4;
OpenGLDrawTest :: ( state: *OpenGLState, screenWidth: int, screenHeight: int )
{
    renderWidth := cast(float)screenWidth;  
    renderHeight := cast(float)screenHeight;
    // TODO scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fbWidth := renderWidth; // * io.DisplayFramebufferScale.x);
    fbHeight := renderHeight; // * io.DisplayFramebufferScale.y);

    glViewport( 0, 0, xx fbWidth, xx fbHeight );

    projection := orthographic_projection_matrix( 0,
                                                  renderWidth, renderHeight,
                                                  0, 0, 1 );
    if( projection != prevOrthoMatrix )
    {
        print( "Orthographic matrix: \n%\t%\t%\t%\n%\t%\t%\t%\n%\t%\t%\t%\n%\t%\t%\t%\n",
               projection._11, projection._12, projection._13, projection._14,
               projection._21, projection._22, projection._23, projection._24,
               projection._31, projection._32, projection._33, projection._34,
               projection._41, projection._42, projection._43, projection._44 );
        prevOrthoMatrix = projection;
    }
    glUniformMatrix4fv( state.textShader.projectionUni, 1, GL_TRUE, *projection._11 );

    // TODO Probably not needed per frame?
    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, state.whiteTextureHandle );  // Bind handle to slot 0.
    glUniform1i( state.textShader.textSamplerUni, 0 );

    //DumpGLErrors( "frame setup" );

    //glClearColor( 0.15, 0.15, 0.2, 1.0 ); 
    glClearColor( 1, 0.15, 0.2, 1.0 ); 
    glClear( GL_COLOR_BUFFER_BIT );

    verts: [4] TextVertex =
    .[
        .{ color = .{ 1, 0, 0, 1 }, uv = .{ 0, 0 } },
        .{ color = .{ 0, 1, 0, 1 }, uv = .{ 1, 0 } },
        .{ color = .{ 0, 0, 1, 1 }, uv = .{ 0, 1 } },
        .{ color = .{ 1, 0, 1, 1 }, uv = .{ 1, 1 } },
    ];
    verts[0].position = .{ 0,               0,              0 }; 
    verts[1].position = .{ renderWidth,     0,              0 }; 
    verts[2].position = .{ 0,               renderHeight,   0 }; 
    verts[3].position = .{ renderWidth,     renderHeight,   0 }; 

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

    // TODO Draw an apron with some thickness right at the window edges to check we have the bounds right
}

#scope_file

#import "Math";

TextVertex :: struct
{
    position:   Vector3;
    color:      Vector4;
    uv:         Vector2;
}

SHADER_TEXT :: #string END

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

        //shader_str := temp_c_string(shaderString);
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

    shader.program     = program;
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

