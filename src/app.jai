#import "Basic";

#program_export

// #c_call seems to be required for using with #foreign
Init :: () -> int // #c_call
{
    //print( "Hello from DLL!\n" );
    return 101;
}
