
OpenGLInit :: ( window: Window_Type ) -> bool
{
    // TODO Error handling!?
    gl_create_context( window, 3, 3,
                       compatibility = false, debug = true );

    gl_load( *gl );
    gl_enable_debug_output( break_on_error = true );

    // TODO Shaders etc

    DumpGLErrors( "context" );
    return true;
}

OpenGLDrawTest :: ( viewportWidth: int, viewportHeight: int )
{
    //glViewport( 0, 0, xx viewportWidth, xx viewportHeight );
    glViewport( 0, 0, 100, 100 );
    
    //glDisable( GL_SCISSOR_TEST );
    //glEnable( GL_CULL_FACE );
    //glEnable( GL_DEPTH_TEST );
    //glFrontFace( GL_CCW );

    //// TODO Create a 1x1 white texture to bind here so that shaders that use samplers
    //// don't have to check whether there's a 'valid' texture or not
    //glBindTexture( GL_TEXTURE_2D, 0 );
    
    glClearColor( 1.0, 0.0, 0.0, 1.0 ); 
    glClear( GL_COLOR_BUFFER_BIT );
}

