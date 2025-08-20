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
    shellPipeHandle: HANDLE;
    eof: bool;
}


#scope_file

#import "Windows";

// https://github.com/microsoft/terminal/pull/17510/files/d3ee58b9fce08b50b1d307ebc012850966ef6b24..cc31a596699d5f1133eec822746b956f0218a5cb#diff-4c3ba54e8baad8805f981e9e919b632ce7656cd152586a1a3974227b866362db
// https://github.com/PKRoma/Terminal/commit/d68c6a5e7a8059678828e2c68f7b94f9736b36b5
// https://github.com/microsoft/terminal/pull/17510/files

CmdPtyShellStart :: ( base: *Shell ) -> bool
{
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
    pipeDirectory := () -> HFILE
    {
        path: UNICODE_STRING = L"\\Device\\NamedPipe\\";

        dirAttributes: OBJECT_ATTRIBUTES = .{
            Length = size_of(OBJECT_ATTRIBUTES),
            ObjectName = *path,
        };

        dir: HFILE;
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
            /* EaLength          */ 0) );

        // TODO Handle error result

        return dir;
    }();

    server: HFILE;
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
        /* InboundQuota      */ bufferSize,
        /* OutboundQuota     */ bufferSize,
        /* DefaultTimeout    */ *timeout) );

    // TODO Handle error result

    client: HFILE;
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
        /* EaLength          */ 0) );

    // TODO Handle error result

    // TODO HANDLEs are internally just 32-bit integers so we should be able to write our HFILEs in there directly?
    // TODO Should we just use the HFILEs throughout?
    (cast(*s32) clientHandle).* = client;
    (cast(*s32) serverHandle).* = server;

    return true;
}
