#import "Basic";

#load "interface.jai";


#program_export

// #c_call seems to be required for using with #foreign
Test :: () -> string // #c_call
{
    return "Hello hallo!";
}


// TODO Make an @implements(UpdateAndRenderFunc) note that's parsed by the metaprogram which will then
// #assert( type_of(UpdateAndRender) == UpdateAndRenderFunc );
//UpdateAndRenderFunc :: #type ( input: AppInput, memory: *AppMemory, renderer: *RendererState );
UpdateAndRender :: ( input: AppInput, memory: *AppMemory, renderer: *RendererState )
{

}
