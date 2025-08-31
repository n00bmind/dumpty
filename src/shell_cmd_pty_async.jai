CmdPtyShellAsync :: struct
{
    #as using base: Shell;
    base.startProc              = CmdPtyShellStart;
    // base.shutdownProc           = CmdPtyShellShutdown;
    // base.writeProc              = CmdPtyShellWrite;
    // base.readProc               = CmdPtyShellRead;
    // base.getWaitableHandlesProc = CmdPtyShellGetWaitableHandles;

    processInfo: PROCESS_INFORMATION;
    consoleHandle: HPCON;
    shellPipeHandle: HANDLE;
    eof: bool;
}


#scope_file

#import "Windows";
#import "Windows_Utf8";

// https://github.com/microsoft/terminal/pull/17510/files/d3ee58b9fce08b50b1d307ebc012850966ef6b24..cc31a596699d5f1133eec822746b956f0218a5cb#diff-4c3ba54e8baad8805f981e9e919b632ce7656cd152586a1a3974227b866362db
// https://github.com/PKRoma/Terminal/commit/d68c6a5e7a8059678828e2c68f7b94f9736b36b5
// https://github.com/microsoft/terminal/pull/17510/files

CmdPtyShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdPtyShellAsync = xx base;

    // Since we're using async IO, we can use a single duplex pipe for reading AND writing
    // TODO Play with the buffer size here
    clientHandle :HANDLE;
    if( !CreateOverlappedPipe( PIPE_ACCESS_DUPLEX, 128 * 1024, *clientHandle, *shell.shellPipeHandle ) )
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

    // TODO See CreateEventW and issue_read() in Process/windows.jai

    return true;
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
CreateOverlappedPipe :: ( openMode: u32, bufferSize: int, clientHandle: *HANDLE, serverHandle: *HANDLE ) -> bool
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
        len: u16 = xx (byteCount / 2);
        path: UNICODE_STRING = .{ len, len, pathData };

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

    clientHandle.* = client;
    serverHandle.* = server;

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



NULL :: cast(*void) 0;
WCHAR :: u16;
USHORT :: u16;
ULONG :: u32;
ACCESS_MASK :: DWORD;
DWORD_PTR :: u64;
ULONG_PTR :: u64;
PWSTR :: *WCHAR;
HPCON :: *void;

PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE :: 131094;
OBJ_CASE_INSENSITIVE :: 0x00000040;
SYNCHRONIZE :: 0x00100000;
FILE_WRITE_ATTRIBUTES :: 0x100;
FILE_OPEN :: 0x00000001;
FILE_CREATE :: 0x00000002;
FILE_PIPE_BYTE_STREAM_TYPE :: 0x00000000;
FILE_PIPE_BYTE_STREAM_MODE :: 0x00000000;
FILE_PIPE_QUEUE_OPERATION :: 0x00000000;
FILE_NON_DIRECTORY_FILE :: 0x00000040;
FILE_SYNCHRONOUS_IO_NONALERT :: 0x00000020;

UNICODE_STRING :: struct
{
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PWSTR;
}

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

IO_STATUS_BLOCK :: struct
{
    union {
        Status: NTSTATUS;
        Pointer: *void;
    }
    Information: ULONG_PTR;
}

OBJECT_ATTRIBUTES :: struct
{
    Length: ULONG;
    RootDirectory: HANDLE;
    ObjectName: *UNICODE_STRING;
    Attributes: ULONG;
    SecurityDescriptor: *void;
    SecurityQualityOfService: *void;
}

kernel32 :: #system_library "kernel32";
ntdll :: #system_library "ntdll";

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

