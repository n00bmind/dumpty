#import "Basic";

#program_export

// #c_call seems to be required for using with #foreign
Test :: () -> string // #c_call
{
    return "Hello hallo!";
}
