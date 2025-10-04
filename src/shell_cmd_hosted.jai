
//// Most of this adapted from https://github.com/jfhs/handterm

CmdHostedShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdHostedShellStart;
    // base.shutdownProc           = CmdHostedShellShutdown;
    // base.writeProc              = CmdHostedShellWrite;
    // base.readProc               = CmdHostedShellRead;
    // base.getWaitableHandlesProc = CmdHostedShellGetWaitableHandles;

    serverHandle: HANDLE;
    ioThreadHandle: HANDLE;
    inputEventHandle: HANDLE;
    // processInfo: PROCESS_INFORMATION;
    // consoleHandle: HPCON;
    // pipeHandle: HANDLE;
    // pipeOverlapped: *OVERLAPPED;
    eof: bool;
}


#scope_file

#import "Windows";
// #import "Windows_Utf8";
// System :: #import "System";


// TODO TODO Error handling
CmdHostedShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdHostedShell = xx base;

    CreateServerHandle( *shell.serverHandle, .FALSE );
    refHandle: HANDLE;
    CreateClientHandle( *refHandle, shell.serverHandle, "\\Reference", .FALSE );

    shell.inputEventHandle = CreateEventExW( NULL, NULL, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS );

    bytes: DWORD;
    serverInfo: CD_IO_SERVER_INFORMATION;
    serverInfo.InputAvailableEvent = shell.inputEventHandle;
    DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_SET_SERVER_INFORMATION, *serverInfo, size_of(CD_IO_SERVER_INFORMATION),
                     NULL, 0, *bytes, NULL );

    shell.ioThreadHandle = CreateThread( NULL, 0, xx ConsoleIoThread, shell, 0, NULL );

    // This should be enough for Conhost setup

    clientHandles: [3] HANDLE;
    CreateClientHandle( *clientHandles[0], shell.serverHandle, "\\Input", .TRUE );
    CreateClientHandle( *clientHandles[1], shell.serverHandle, "\\Output", .TRUE );
    DuplicateHandle( GetCurrentProcess(), clientHandles[1], GetCurrentProcess(), *clientHandles[2], 0, .TRUE,
                     DUPLICATE_SAME_ACCESS );

    si: STARTUPINFOEXW;
    si.StartupInfo.cb = size_of(STARTUPINFOEXW);
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = clientHandles[0];
    si.StartupInfo.hStdOutput = clientHandles[1];
    si.StartupInfo.hStdError = clientHandles[2];

    attrSize: SIZE_T;
    InitializeProcThreadAttributeList( NULL, 2, 0, *attrSize );
    si.lpAttributeList = cast(PPROC_THREAD_ATTRIBUTE_LIST) alloc( xx attrSize );
    InitializeProcThreadAttributeList( si.lpAttributeList, 2, 0, *attrSize );
    /*
    hr = UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, con, size_of(con), NULL, NULL);
    Assert(SUCCEEDED(hr));
    */
    UpdateProcThreadAttribute( si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_CONSOLE_REFERENCE, *refHandle, size_of(HANDLE),
                               NULL, NULL );
    UpdateProcThreadAttribute( si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, clientHandles.data,
                               size_of(type_of(clientHandles)), NULL, NULL );

    cmd := WideStrTmp( "cmd.exe" );
    // cmd := WideStrTmp( "C:\\Windows\\System32\\cmd.exe" );

    pi: PROCESS_INFORMATION;
    ok := CreateProcessW( NULL, cmd, NULL, NULL, .TRUE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, *si.StartupInfo, *pi );
    // Assert(ok);

    CloseHandle( pi.hThread );
    // TODO Surely we wanna monitor this to figure out if the process was killed?
    CloseHandle( pi.hProcess );
    CloseHandle( refHandle );
    CloseHandle( clientHandles[0] );
    CloseHandle( clientHandles[1] );
    CloseHandle( clientHandles[2] );

    return true;
}

ConsoleIoThread :: ( lpParameter: *void ) -> DWORD #c_call
{
    shell: *CmdHostedShell = xx lpParameter;

    send_io_complete := false;
    io_complete: CD_IO_COMPLETE;
    ReceiveMsg: CONSOLE_API_MSG;
    BytesRead: DWORD;

    while !shell.eof
    {
        // TODO Check ConsoleIoThread in terminal/src/host/srvinit.cpp
        // if (ReplyMsg != nullptr)
        //     ReplyMsg->ReleaseMessageBuffers();

        ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_IO, ifx send_io_complete *io_complete else null,
                               ifx send_io_complete size_of(CD_IO_COMPLETE) else 0, *ReceiveMsg, size_of(CONSOLE_API_MSG),
                               *BytesRead, NULL );

        if !ok
        {
            // TODO Test all this HRESULT malarkey
            // hr := GetLastErrorAsHr();
            err := GetLastError();

            if err == ERROR_IO_PENDING
                WaitForSingleObjectEx( shell.serverHandle, 0, .FALSE );
            else
            {
                if err == ERROR_PIPE_NOT_CONNECTED
                {
                    shell.eof = true;
                    return 0;
                }
                else
                {
                    log_error( "CONDRV_READ_IO failed: %\n", get_error_string( err ) );
                    return 1;
                }
            }
        }

        // We got some command

        send_io_complete = false;
        memset( *io_complete, 0, size_of(CD_IO_COMPLETE) );
        io_complete.Identifier = ReceiveMsg.Descriptor.Identifier;

        log( "CONDRV_READ_IO msg: %\n", ReceiveMsg.Descriptor.Function );
        // if ReceiveMsg.Descriptor.Function ==
        // {
        //
        // }
    }

    return 0;
}
