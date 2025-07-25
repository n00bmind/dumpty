CmdPtyShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdPtyShellStart;
    // base.shutdownProc           = CmdShellShutdown;
    // base.writeProc              = CmdShellWrite;
    // base.readProc               = CmdShellRead;
    // base.getWaitableHandlesProc = CmdShellGetWaitableHandles;

    consoleHandle: HPCON;
    inHandle, outHandle: HANDLE;
}


#scope_file

#import "Windows";

CmdPtyShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdPtyShell = xx base;

    inReadEnd, outWriteEnd: HANDLE;

    // TODO Last param is "the size of the buffer for the pipe, in bytes"
    // Play with it a little, maybe?
    if( !CreatePipe( *inReadEnd, *shell.inHandle, NULL, 0 ) )
    {
        log_error( "Failed creating input pipe: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    if( !CreatePipe( *shell.outHandle, *outWriteEnd, NULL, 0 ) )
    {
        log_error( "Failed creating output pipe: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

     // TODO Pass a settings arg to this function with the current character size
     // TODO This will need to be redimensioned using ResizePseudoConsole.
    size: COORD = .{ 80, 25 };
    hr := CreatePseudoConsole( size, inReadEnd, outWriteEnd, 0, *shell.consoleHandle );
    if( FAILED(hr) )
    {
        log_error( "Failed creating pseudo console: %\n", formatInt( hr, base=16 ) );
        return false;
    }


    si: STARTUPINFOEXA;
    memset( *si, 0, size_of(STARTUPINFOEXA) );
    si.StartupInfo.cb = size_of(STARTUPINFOEXA);

    // Discover the size required for the list
    bytesRequired: u64;;
    res := InitializeProcThreadAttributeList( NULL, 1, 0, *bytesRequired );
    assert( res && "Failed getting size of thread attribute list" );

    si.lpAttributeList = cast(*PROC_THREAD_ATTRIBUTE_LIST) alloc( xx bytesRequired );
    assert( si.lpAttributeList && "Failed allocating attribute list" );

    // Initialize the list memory location
    if( !InitializeProcThreadAttributeList( si.lpAttributeList, 1, 0, *bytesRequired ) )
    {
        free( si.lpAttributeList );
        log_error( "Failed initialising attribute list: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    // Set the pseudoconsole information into the list
    // TODO So the the example seems to imply that if this succeeds, this pointer is now
    // "owned" by the OS? Or am I supposed to still free it up at shutdown?
    if( !UpdateProcThreadAttribute( si.lpAttributeList, 0,
                                    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
    // TODO Copied "verbatim" from example.
    // However this is supposed to be a pointer and the size of the stuff it points to !?
                                    shell.consoleHandle, size_of(HPCON), NULL, NULL ) )
    {
        free( si.lpAttributeList );
        log_error( "Failed initialising attribute list: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }


    pi: PROCESS_INFORMATION;
    memset( *pi, 0, size_of(PROCESS_INFORMATION) );
     // TODO Shouldnt we use %WINDOWS% here or whatever that env var is?
     // TODO We can pass an initial dir here in 'lpCurrentDirectory'
    if( !CreateProcessA( "C:\\windows\\system32\\cmd.exe", NULL, NULL, NULL,
                         .FALSE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
                         *si.StartupInfo, *pi ) )
    {
         // TODO So we dont free si.lpAttributeList here!?
        log_error( "Failed creating 'cmd' process: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

     // TODO After shell process is running (or failure)
     // TODO Should add these (and any frees required above) to the defer list
    free( si.lpAttributeList );

    // We can now close the pipe handles that we dont manage
    CloseHandle( inReadEnd );
    CloseHandle( outWriteEnd );

    return true;
}


NULL :: cast(*void) 0;
HPCON :: *void;
DWORD_PTR :: s64;

PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE :: 131094;

proc_thread_attr :: struct
{
    attr: DWORD_PTR;
    size: SIZE_T;
    value: *void;
}
 
PROC_THREAD_ATTRIBUTE_LIST :: struct
{
    mask: DWORD;  /* bitmask of items in list */
    size: DWORD;  /* max number of items in list */
    count: DWORD; /* number of items in list */
    pad: DWORD;
    unk: DWORD_PTR;
    attrs: [1] proc_thread_attr;
}

STARTUPINFOEXA :: struct
{
    StartupInfo: STARTUPINFOA;
    lpAttributeList: *PROC_THREAD_ATTRIBUTE_LIST;
}


kernel32 :: #system_library "kernel32";

CreatePseudoConsole     :: ( size: COORD, input: HANDLE, output: HANDLE, flags: DWORD,
                             ret: *HPCON ) -> HRESULT #foreign kernel32;
InitializeProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, count: DWORD,
                                       flags: DWORD, size: *SIZE_T ) -> BOOL #foreign kernel32;
UpdateProcThreadAttribute :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, flags: DWORD,
                               attr: DWORD_PTR, value: *void, size: SIZE_T,
                               prev_ret: *void, size_ret: *SIZE_T ) -> BOOL #foreign kernel32;

