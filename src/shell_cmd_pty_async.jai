// TODO 
// TODO We're gonna need much better on-screen visualisation & inspection of VTCs if we're ever gonna understand this mess..
// TODO 

// Async version of the "canonical" Pseudoconsole shell described in
// https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session
// Uses a couple tricks taken from the MS Terminal repo to create (supposedly unsupported) overlapped pipes
// https://github.com/PKRoma/Terminal/commit/d68c6a5e7a8059678828e2c68f7b94f9736b36b5

// The whole idea with using this instead of a vanilla cmd.exe plus a couple pipes is that this shell auto-translates
// any Windows Console API calls into the (hopefully) equivalent VT codes..
// And also, crucially, that any child processes of cmd.exe identify that they're running in a "true" tty.
// The main drawback of that is that debugging 100 VT codes in the output all at once is akin to visiting Dante's inferno.
// Oh, and based on the first few impressions, it also appears to be hideously slow.
CmdPtyShellAsync :: struct
{
    #as using base: Shell;
    base.startProc              = CmdPtyShellStart;
    base.shutdownProc           = CmdPtyShellShutdown;
    base.writeProc              = CmdPtyShellWrite;
    base.readProc               = CmdPtyShellRead;
    base.getWaitableHandlesProc = CmdPtyShellGetWaitableHandles;

    processInfo: PROCESS_INFORMATION;
    consoleHandle: HPCON;
    pipeHandle: HANDLE;
    pipeOverlapped: *OVERLAPPED;
    eof: bool;
}


#scope_file

#import "Windows";
#import "Windows_Utf8";
System :: #import "System";


CmdPtyShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdPtyShellAsync = xx base;

    // Since we're using async IO, we can use a single duplex pipe for reading AND writing
    // TODO Play with the buffer size here
    clientHandle :HANDLE;
    if( !CreateOverlappedPipe( PIPE_ACCESS_DUPLEX, 128 * 1024, *clientHandle, *shell.pipeHandle, *shell.pipeOverlapped ) )
    {
        log_error( "Failed creating shell pipe: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    // TODO Pass a settings arg to this function with the current character size
    // TODO This will need to be redimensioned using ResizePseudoConsole.
    size: COORD = .{ 80, 25 };
    hr := CreatePseudoConsole( size, clientHandle, clientHandle, 0, *shell.consoleHandle );
    if( FAILED(hr) )
    {
        log_error( "Failed creating pseudo console: %\n", formatInt( hr, base=16 ) );
        return false;
    }


    si: STARTUPINFOEXW;
    memset( *si, 0, size_of(STARTUPINFOEXW) );
    si.StartupInfo.cb = size_of(STARTUPINFOEXW);
    // TODO NOTE This is in WinTerm's code, however no handles seem to be provided?
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;

    // Discover the size required for the list (returns an error, but we're supposed to ignore that..)
    bytesRequired: SIZE_T;
    InitializeProcThreadAttributeList( NULL, 1, 0, *bytesRequired );

    si.lpAttributeList = cast(*PROC_THREAD_ATTRIBUTE_LIST) alloc( xx bytesRequired );
    assert( si.lpAttributeList && "Failed allocating attribute list" );

    // TODO Should probably use temp memory..
    defer free( si.lpAttributeList );

    // Initialize the list memory location
    if( !InitializeProcThreadAttributeList( si.lpAttributeList, 1, 0, *bytesRequired ) )
    {
        log_error( "Failed initialising attribute list: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    // Set the pseudoconsole information into the list
    if( !UpdateProcThreadAttribute( si.lpAttributeList, 0,
                                    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                    shell.consoleHandle, size_of(HPCON), NULL, NULL ) )
    {
        log_error( "Failed updating attribute list: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }


    memset( *shell.processInfo, 0, size_of(PROCESS_INFORMATION) );
    cmdPath := "C:\\windows\\system32\\cmd.exe";
    // TODO Shouldnt we use %WINDOWS% here or whatever that env var is?
    // TODO We can pass an initial dir here in 'lpCurrentDirectory'
    // TODO Use job objects to auto-kill children when this dies
    // TODO Could add our own env vars here in lpEnvironment.. in particular for WSL
    // https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
    if( !CreateProcessW( NULL, utf8_to_wide(cmdPath,, temp), NULL, NULL,
                        .FALSE, EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT, NULL, NULL,
                        *si.StartupInfo, *shell.processInfo ) )
    {
        log_error( "Failed creating 'cmd' process: %\n", formatInt( GetLastError(), base=16 ) );
        return false;
    }

    DeleteProcThreadAttributeList( si.lpAttributeList );
    // NOTE This is available on Windows 11 only, so use our own definition below instead of trying to import it
    ConptyReleasePseudoConsole( shell.consoleHandle );

     // TODO 
    // // Forward Ctrl-C to the PTY.
    // SetConsoleCtrlHandler(
    //     [](DWORD type) -> BOOL {
    //         switch (type)
    //         {
    //         case CTRL_C_EVENT:
    //         case CTRL_BREAK_EVENT:
    //             WriteFile(pipe.server.get(), "\x03", 1, nullptr, nullptr);
    //             return true;
    //         default:
    //             return false;
    //         }
    //     },
    //     TRUE);

    // Issue an initial read on the pipe, so we get notified as soon as something comes in
    IssueRead( shell );

    return true;
}

CmdPtyShellShutdown :: ( base: *Shell )
{
    shell: *CmdPtyShellAsync = xx base;

    CloseHandle( shell.pipeOverlapped.hEvent );
    CloseHandle( shell.pipeHandle );
    ClosePseudoConsole( shell.consoleHandle );
}


CmdPtyShellWrite :: ( base: *Shell, str: string ) -> bool
{
    shell: *CmdPtyShellAsync = xx base;

    bytesWritten: u32 = ---;
    result := WriteFile( shell.pipeHandle, str.data, cast(u32) str.count, *bytesWritten, null );

    assert( result && bytesWritten == str.count, "Couldn't write full string" );
    return cast(bool) result;
}

CmdPtyShellRead :: ( base: *Shell, sourceBuffer: *SourceBuffer ) -> Process_Result, s64
{
    shell: *CmdPtyShellAsync = xx base;

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

// TODO Can we pass an array of *void here?
CmdPtyShellGetWaitableHandles :: ( base: *Shell, handles: [] HANDLE, handleCount: *u32 )
{
    shell: *CmdPtyShellAsync = xx base;

    // if IsRunning( shell.process )
    {
        if !shell.eof
        {
            handles[handleCount.*] = shell.pipeOverlapped.hEvent;
            handleCount.* += 1;
        }
        // if !shell.process.error.eof
        // {
        //     handles[handleCount.*] = shell.process.error.overlapped.hEvent;
        //     handleCount.* += 1;
        // }
    }
}



//// Adapted from Windows Terminal code
// Creates an overlapped anonymous pipe. openMode should be either:
// * PIPE_ACCESS_INBOUND
// * PIPE_ACCESS_OUTBOUND
// * PIPE_ACCESS_DUPLEX
//
// I know, I know. MSDN infamously says
// > Asynchronous (overlapped) read and write operations are not supported by anonymous pipes.
// but that's a lie. The only reason they're not supported is because the Win32
// API doesn't have a parameter where you could pass FILE_FLAG_OVERLAPPED!
// So, we'll simply use the underlying NT APIs instead.
//
// Most code on the internet suggests creating named pipes with a random name,
// but usually conveniently forgets to mention that named pipes require strict ACLs.
// https://stackoverflow.com/q/60645 for instance contains a lot of poor advice.
// Anonymous pipes also cannot be discovered via NtQueryDirectoryFile inside the NPFS driver,
// whereas running a tool like Sysinternals' PipeList will return all those semi-named pipes.
//
// The code below contains comments to create unidirectional pipes.
CreateOverlappedPipe :: ( openMode: u32, bufferSize: int, clientHandleOut: *HANDLE, serverHandleOut: *HANDLE,
                          overlappedOut: **OVERLAPPED ) -> bool
{
    timeout: LARGE_INTEGER = .{ QuadPart = -10_0000_0000 }; // 1 second
    emptyPath: UNICODE_STRING;
    statusBlock: IO_STATUS_BLOCK;
    objectAttributes: OBJECT_ATTRIBUTES =
    .{
        Length = size_of(OBJECT_ATTRIBUTES),
        ObjectName = *emptyPath,
        Attributes = OBJ_CASE_INSENSITIVE,
    };
    serverDesiredAccess: DWORD;
    clientDesiredAccess: DWORD;
    serverShareAccess: DWORD;
    clientShareAccess: DWORD;

    if openMode ==
    {
        case PIPE_ACCESS_INBOUND;
        {
            serverDesiredAccess = SYNCHRONIZE | GENERIC_READ | FILE_WRITE_ATTRIBUTES;
            clientDesiredAccess = SYNCHRONIZE | GENERIC_WRITE | FILE_READ_ATTRIBUTES;
            serverShareAccess = FILE_SHARE_WRITE;
            clientShareAccess = FILE_SHARE_READ;
        }
        case PIPE_ACCESS_OUTBOUND;
        {
            serverDesiredAccess = SYNCHRONIZE | GENERIC_WRITE | FILE_READ_ATTRIBUTES;
            clientDesiredAccess = SYNCHRONIZE | GENERIC_READ | FILE_WRITE_ATTRIBUTES;
            serverShareAccess = FILE_SHARE_READ;
            clientShareAccess = FILE_SHARE_WRITE;
        }
        case PIPE_ACCESS_DUPLEX;
        {
            serverDesiredAccess = SYNCHRONIZE | GENERIC_READ | GENERIC_WRITE;
            clientDesiredAccess = SYNCHRONIZE | GENERIC_READ | GENERIC_WRITE;
            serverShareAccess = FILE_SHARE_READ | FILE_SHARE_WRITE;
            clientShareAccess = FILE_SHARE_READ | FILE_SHARE_WRITE;
        }
        case;
            assert( false && "Unsupported openMode value" );
    }

    // Cache a handle to the pipe driver.
    pipeDirectory := () -> HANDLE
    {
        pathData, _, byteCount := utf8_to_wide("\\Device\\NamedPipe\\",, temp);
        len: u16 = xx byteCount;
        path: UNICODE_STRING = .{ len, len + size_of(WCHAR), pathData };

        dirAttributes: OBJECT_ATTRIBUTES = .{
            Length = size_of(OBJECT_ATTRIBUTES),
            ObjectName = *path,
        };

        dir: HANDLE;
        statusBlock: IO_STATUS_BLOCK;
        result: NTSTATUS = NtCreateFile(
            /* FileHandle        */ *dir,
            /* DesiredAccess     */ SYNCHRONIZE | GENERIC_READ,
            /* ObjectAttributes  */ *dirAttributes,
            /* IoStatusBlock     */ *statusBlock,
            /* AllocationSize    */ null,
            /* FileAttributes    */ 0,
            /* ShareAccess       */ FILE_SHARE_READ | FILE_SHARE_WRITE,
            /* CreateDisposition */ FILE_OPEN,
            /* CreateOptions     */ FILE_SYNCHRONOUS_IO_NONALERT,
            /* EaBuffer          */ null,
            /* EaLength          */ 0 );

        // TODO Handle error result

        return dir;
    }();

    server: HANDLE;
    objectAttributes.RootDirectory = pipeDirectory;
    result := NtCreateNamedPipeFile(
        /* FileHandle        */ *server,
        /* DesiredAccess     */ serverDesiredAccess,
        /* ObjectAttributes  */ *objectAttributes,
        /* IoStatusBlock     */ *statusBlock,
        /* ShareAccess       */ serverShareAccess,
        /* CreateDisposition */ FILE_CREATE,
        /* CreateOptions     */ 0, // would be FILE_SYNCHRONOUS_IO_NONALERT for a synchronous pipe
        /* NamedPipeType     */ FILE_PIPE_BYTE_STREAM_TYPE,
        /* ReadMode          */ FILE_PIPE_BYTE_STREAM_MODE,
        /* CompletionMode    */ FILE_PIPE_QUEUE_OPERATION, // would be FILE_PIPE_COMPLETE_OPERATION for PIPE_NOWAIT
        /* MaximumInstances  */ 1,
        /* InboundQuota      */ xx bufferSize,
        /* OutboundQuota     */ xx bufferSize,
        /* DefaultTimeout    */ *timeout );

    // TODO Handle error result

    client: HANDLE;
    objectAttributes.RootDirectory = server;
    result = NtCreateFile(
        /* FileHandle        */ *client,
        /* DesiredAccess     */ clientDesiredAccess,
        /* ObjectAttributes  */ *objectAttributes,
        /* IoStatusBlock     */ *statusBlock,
        /* AllocationSize    */ null,
        /* FileAttributes    */ 0,
        /* ShareAccess       */ clientShareAccess,
        /* CreateDisposition */ FILE_OPEN,
        /* CreateOptions     */ FILE_NON_DIRECTORY_FILE, // would include FILE_SYNCHRONOUS_IO_NONALERT for a synchronous pipe
        /* EaBuffer          */ null,
        /* EaLength          */ 0 );

    // TODO Handle error result

    clientHandleOut.* = client;
    serverHandleOut.* = server;



    event := CreateEventW( NULL, 0, 0, NULL );
    if event == null
    {
        error_code, error_string := System.get_error_value_and_string();
        log_error( "Unable to create event for overlapped pipe: % %", error_code, error_string );
        return false;
    }

    // We allocate this dynamically because we need to pass a pointer to it to Windows and then the OS writes into it a some random point in the future.
    // If Process contains OVERLAPPED by value, it must never be moved or you get "funny" stack/memory corruption issues.
    overlappedOut.* = New( OVERLAPPED );
    overlappedOut.*.hEvent = event;

    return true;
}

//// Adapted from Windows Terminal code
PseudoConsole :: struct
{
    hSignal: HANDLE;
    hPtyReference: HANDLE;
    hConPtyProcess: HANDLE;
}
// The \Reference handle ensures that conhost keeps running by keeping the ConDrv server pipe open.
// After you've finished setting up your PTY via PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, this method may be called
// to release that handle, allowing conhost to shut down automatically once the last client has disconnected.
// You'll know when this happens, because a ReadFile() on the output pipe will return ERROR_BROKEN_PIPE.
ConptyReleasePseudoConsole :: ( hPC: HPCON ) -> HRESULT
{
    pPty := cast(*PseudoConsole) hPC;
    if pPty == null
        return E_INVALIDARG;

    if pPty.hPtyReference != null && pPty.hPtyReference != INVALID_HANDLE_VALUE
    {
        CloseHandle( pPty.hPtyReference );
        pPty.hPtyReference = null;
    }

    return S_OK;
}

IssueRead :: ( shell: *CmdPtyShellAsync ) -> bool
{
    result := ReadFile( shell.pipeHandle, NULL, 0, NULL, shell.pipeOverlapped );
    if result == .FALSE && GetLastError() != ERROR_IO_PENDING
        return false;

    return true;
}

ReadPipe :: ( shell: *CmdPtyShellAsync, buffer: [] u8 ) -> success: bool, bytesRead: int
{
    bytesRead: u32;
    bytesAvailable: u32;

    success := PeekNamedPipe( shell.pipeHandle, NULL, 0, NULL, *bytesAvailable, NULL ) != 0;
    if success && bytesAvailable
    {
        success = ReadFile( shell.pipeHandle, buffer.data, cast(u32) buffer.count, *bytesRead, NULL ) != 0;
        if success
            success = IssueRead( shell );
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



//// Win32 crap

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

STARTUPINFOEXW :: struct
{
    StartupInfo: STARTUPINFOW;
    lpAttributeList: *PROC_THREAD_ATTRIBUTE_LIST;
}

CreatePseudoConsole     :: ( size: COORD, input: HANDLE, output: HANDLE, flags: DWORD,
                             ret: *HPCON ) -> HRESULT #foreign kernel32;
// Only available on Windows 11 build 26100
// ReleasePseudoConsole    :: ( hPC: HPCON ) -> HRESULT #foreign kernel32;
ClosePseudoConsole      :: ( hPC: HPCON ) -> void #foreign kernel32;

InitializeProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, count: DWORD,
                                       flags: DWORD, size: *SIZE_T ) -> BOOL #foreign kernel32;
UpdateProcThreadAttribute :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, flags: DWORD,
                               attr: DWORD_PTR, value: *void, size: SIZE_T,
                               prev_ret: *void, size_ret: *SIZE_T ) -> BOOL #foreign kernel32;
DeleteProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST ) -> void #foreign kernel32;

NtCreateFile :: ( FileHandle: *HANDLE,
                  DesiredAccess: ACCESS_MASK,
                  ObjectAttributes: *OBJECT_ATTRIBUTES,
                  IoStatusBlock: *IO_STATUS_BLOCK,
                  AllocateSize: *LARGE_INTEGER,
                  FileAttributes: ULONG,
                  ShareAccess: ULONG,
                  CreateDisposition: ULONG,
                  CreateOptions: ULONG,
                  EaBuffer: *void,
                  EaLength: ULONG 
                ) -> NTSTATUS #foreign ntdll;
NtCreateNamedPipeFile :: ( FileHandle: *HANDLE,
                           DesiredAccess: ACCESS_MASK,
                           ObjectAttributes: *OBJECT_ATTRIBUTES,
                           IoStatusBlock: *IO_STATUS_BLOCK,
                           ShareAccess: ULONG,
                           CreateDisposition: ULONG,
                           CreateOptions: ULONG,
                           NamedPipeType: ULONG,
                           ReadMode: ULONG,
                           CompletionMode: ULONG,
                           MaximumInstances: ULONG,
                           InboundQuota: ULONG,
                           OutboundQuota: ULONG,
                           DefaultTimeout: *LARGE_INTEGER 
                         ) -> NTSTATUS #foreign ntdll;

