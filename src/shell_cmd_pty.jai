// TODO Now that we have the async version of this, this one can probably be binned.
CmdPtyShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdPtyShellStart;
    base.shutdownProc           = CmdPtyShellShutdown;
    base.writeProc              = CmdPtyShellWrite;
    base.readProc               = CmdPtyShellRead;
    // NOTE This is the "official" sync IO version of the ConPTY mechanism, without overlapped IO hence no waitable handles
    // base.getWaitableHandlesProc = CmdPtyShellGetWaitableHandles;

    processInfo: PROCESS_INFORMATION;
    consoleHandle: HPCON;
    inHandle, outHandle: HANDLE;
    eof: bool;
}


#scope_file

#import "Windows";

CmdPtyShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdPtyShell = xx base;

    inReadEnd, outWriteEnd: HANDLE;

    // TODO Last param is "the size of the buffer for the pipe, in bytes"
    // Play with it a little, maybe?
    // TODO modules/Process/windows.jai claims that named pipes cannot be used with WaitFor..
    // however refterm seems to be doing that just fine?
    if( !CreatePipe( *inReadEnd, *shell.inHandle, NULL, 0 ) )
    {
        log_error( "Failed creating input pipe: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }
    defer CloseHandle( inReadEnd );

    if( !CreatePipe( *shell.outHandle, *outWriteEnd, NULL, 0 ) )
    {
        log_error( "Failed creating output pipe: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }
    defer CloseHandle( outWriteEnd );

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
    bytesRequired: SIZE_T;
    InitializeProcThreadAttributeList( NULL, 1, 0, *bytesRequired );

    si.lpAttributeList = cast(*PROC_THREAD_ATTRIBUTE_LIST) alloc( xx bytesRequired );
    assert( si.lpAttributeList && "Failed allocating attribute list" );

    defer free( si.lpAttributeList );

    // Initialize the list memory location
    if( !InitializeProcThreadAttributeList( si.lpAttributeList, 1, 0, *bytesRequired ) )
    {
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
        log_error( "Failed initialising attribute list: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }


    memset( *shell.processInfo, 0, size_of(PROCESS_INFORMATION) );
    // TODO Shouldnt we use %WINDOWS% here or whatever that env var is?
    // TODO We can pass an initial dir here in 'lpCurrentDirectory'
    // TODO Use job objects to auto-kill children when this dies
    if( !CreateProcessA( "C:\\windows\\system32\\cmd.exe", NULL, NULL, NULL,
                         .FALSE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
                         *si.StartupInfo, *shell.processInfo ) )
    {
        log_error( "Failed creating 'cmd' process: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    // TODO Check use of ReleasePseudoConsole & ClosePseudoConsole on the async version of this

    return true;
}

CmdPtyShellShutdown :: ( base: *Shell )
{
    shell: *CmdPtyShell = xx base;

    CloseHandle( shell.inHandle );
    CloseHandle( shell.outHandle );

    CloseHandle( shell.consoleHandle );
}


CmdPtyShellWrite :: ( base: *Shell, str: string ) -> bool
{
    shell: *CmdPtyShell = xx base;

    // result, bytesWritten := write_to_process( *shell.process, xx str );
    bytesWritten: u32 = ---;
    result := WriteFile( shell.inHandle, str.data, cast(u32) str.count, *bytesWritten, null );

    assert( result && bytesWritten == str.count, "Couldn't write full string" );
    return cast(bool) result;
}

ReadPipe :: ( shell: *CmdPtyShell, buffer: [] u8 ) -> success: bool, bytesRead: int
{
    bytesRead: u32;
    bytesAvailable: u32;

    success := PeekNamedPipe( shell.outHandle, null, 0, null, *bytesAvailable, null ) != 0;
    if success && bytesAvailable
    {
        success = ReadFile( shell.outHandle, buffer.data, cast(u32) buffer.count, *bytesRead, null ) != 0;
        // if success {
        //     success = issue_read(pipe);
        // }
    }

    if !success
    {
        // We can read some bytes even if BROKEN_PIPE, so return those.
        if GetLastError() == ERROR_BROKEN_PIPE
            shell.eof = true;
        else
            return false, 0;
    }

    return true, bytesRead;
}

CmdPtyShellRead :: ( base: *Shell, sourceBuffer: *SourceBuffer ) -> Process_Result, s64
{
    shell: *CmdPtyShell = xx base;

    success: bool;
    outBytes, errBytes: s64;
    if !shell.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        // TODO Get some stats going for how many bytes per sec. the pipe is actually filling here
        // TODO Try to figure out a way to easily determine whether the bottleneck is the shell or our parsing
        success, outBytes = ReadPipe( shell, range );

        if outBytes
            CommitWrite( sourceBuffer, outBytes );
    }
    // if !shell.process.error.eof
    // {
    //     range := GetNextWriteableRange( sourceBuffer );
    //
    //     success, errBytes = ReadPipe( *shell.process.error, range );
    //
    //     if errBytes
    //         CommitWrite( sourceBuffer, errBytes );
    // }

    totalBytes := outBytes + errBytes;

    // TODO 
    result: Process_Result = .{ type = .STILL_RUNNING };
    // No more output, so check if it's been killed
    #if false // shell.eof //&& shell.process.error.eof
    {
        success, result = get_process_result( *shell.process );
        if !success
        {
            error_code, error_string := get_error_value_and_string();
            // TODO Diagnostics
            //log_error( "Couldn’t get process result for command \"%\": % %", get_quoted_command_string(args), error_code, error_string );
            kill_process( *shell.process );
            result = .{type = .EXITED, exit_code = -1};
        }
    }

    return result, totalBytes;
}

CmdPtyShellGetWaitableHandles :: ( base: *Shell, handles: [] HANDLE, handleCount: *u32 )
{

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
// Only available on Windows 11 build 26100
// ReleasePseudoConsole    :: ( hPC: HPCON ) -> HRESULT #foreign kernel32;
ClosePseudoConsole      :: ( hPC: HPCON ) -> HRESULT #foreign kernel32;

InitializeProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, count: DWORD,
                                       flags: DWORD, size: *SIZE_T ) -> BOOL #foreign kernel32;
UpdateProcThreadAttribute :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, flags: DWORD,
                               attr: DWORD_PTR, value: *void, size: SIZE_T,
                               prev_ret: *void, size_ret: *SIZE_T ) -> BOOL #foreign kernel32;

