
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
    // eof: bool;
}


#scope_file

#import "Windows";
// #import "Windows_Utf8";
// System :: #import "System";

#load "platform/win32.jai";

// TODO TODO Error handling
CmdHostedShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdHostedShell = xx base;

    CreateServerHandle( *shell.serverHandle, .FALSE );
    refHandle: HANDLE;
    CreateClientHandle( *refHandle, shell.serverHandle, "\\Reference", .FALSE );

    shell.inputEventHandle = CreateEventExW( 0, 0, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS );

    bytes: DWORD;
    serverInfo: CD_IO_SERVER_INFORMATION;
    serverInfo.InputAvailableEvent = shell.inputEventHandle;
    DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_SET_SERVER_INFORMATION, *serverInfo, size_of(CD_IO_SERVER_INFORMATION),
                     0, 0, *bytes, 0 );

    server.ioThreadHandle = CreateThread( 0, 0, ConsoleIoThread, 0, 0, 0 );

    // This should be enough for Conhost setup

    clientHandles: [3] HANDLE;
    CreateClientHandle( *clientHandles[0], shell.serverHandle, "\\Input", .TRUE );
    CreateClientHandle( *clientHandles[1], shell.serverHandle, "\\Output", .TRUE );
    DuplicateHandle( GetCurrentProcess(), clientHandles[1], GetCurrentProcess(), *clientHandles[2], 0, .TRUE,
                     DUPLICATE_SAME_ACCESS );

    si: STARTUPINFOEXW si;
    si.StartupInfo.cb = size_of(STARTUPINFOEXW);
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = clientHandles[0];
    si.StartupInfo.hStdOutput = clientHandles[1];
    si.StartupInfo.hStdError = clientHandles[2];

    attrSize: SIZE_T;
    InitializeProcThreadAttributeList( NULL, 2, 0, *attrSize );
    si.lpAttributeList = cast(LPPROC_THREAD_ATTRIBUTE_LIST) alloc( attrSize );
    InitializeProcThreadAttributeList( si.lpAttributeList, 2, 0, *attrSize );
    /*
    hr = UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, con, size_of(con), NULL, NULL);
    Assert(SUCCEEDED(hr));
    */
    UpdateProcThreadAttribute( si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_CONSOLE_REFERENCE, *refHandle, size_of(HANDLE),
                               NULL, NULL );
    UpdateProcThreadAttribute( si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, clientHandles,
                               size_of(type_of(clientHandles)), NULL, NULL );

    cmd := WideStrTmp( "cmd.exe" );
    // cmd := WideStrTmp( "C:\\Windows\\System32\\cmd.exe" );

    pi: PROCESS_INFORMATION;
    ok := CreateProcessW( NULL, cmd, NULL, NULL, TRUE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, *si.StartupInfo, *pi );
    // Assert(ok);

    CloseHandle( pi.hThread );
    // TODO Surely we wanna monitor this to figure out if the process was killed?
    CloseHandle( pi.hProcess );
    CloseHandle( refHandle );
    CloseHandle( clientHandles[0] );
    CloseHandle( clientHandles[1] );
    CloseHandle( clientHandles[2] );
}
