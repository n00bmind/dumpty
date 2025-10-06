
//// Most of this adapted from https://github.com/jfhs/handterm

CmdHostedShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdHostedShellStart;
    // base.shutdownProc           = CmdHostedShellShutdown;
    // base.writeProc              = CmdHostedShellWrite;
    base.readProc               = CmdHostedShellRead;
    // base.getWaitableHandlesProc = CmdHostedShellGetWaitableHandles;

    consoleControl : #type ( Command: CONSOLECONTROL, Information: PVOID, Length: DWORD ) -> NTSTATUS #c_call;
    sourceBuffer: *SourceBuffer;
    lastSourceAbsP: s64;

    serverHandle: HANDLE;
    ioThreadHandle: HANDLE;
    inputEventHandle: HANDLE;
    // processInfo: PROCESS_INFORMATION;
    // consoleHandle: HPCON;
    // pipeHandle: HANDLE;
    // pipeOverlapped: *OVERLAPPED;

    input_console_mode: ULONG = ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_MOUSE_INPUT
                              | ENABLE_INSERT_MODE | ENABLE_EXTENDED_FLAGS | ENABLE_AUTO_POSITION;
    output_console_mode: ULONG = ENABLE_PROCESSED_OUTPUT | ENABLE_WRAP_AT_EOL_OUTPUT;
    input_cp: UINT;
    output_cp: UINT;

    // Incoming data from the shell will be in utf16, so we cant avoid (at least) a copy + conversion
    // (ansi requires *2* conversions, first to utf16 and then to utf8)
    // TODO Unless the CP is utf8 already!
    stagingBuffer: [] u8;
    outputBuffer: [] u8;
    outputByteCount: s64;

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

    assert( shell.sourceBuffer && "Need a SourceBuffer!" );

    shell.consoleControl = xx GetProcAddress( LoadLibraryExA( "user32.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32 ),
                                              "ConsoleControl" );
    assert( shell.consoleControl != null && "Failed retrieving entrypoint 'ConsoleControl' from user32.dll" );

    // TODO 
    shell.outputBuffer = NewArray( 1024 * 1024, u8 );

    shell.input_cp = GetOEMCP();
    shell.output_cp = GetOEMCP();

    CreateServerHandle( *shell.serverHandle, .FALSE );
    refHandle: HANDLE;
    CreateClientHandle( *refHandle, shell.serverHandle, "\\Reference", .FALSE );

    shell.inputEventHandle = CreateEventExW( NULL, NULL, CREATE_EVENT_MANUAL_RESET, EVENT_ALL_ACCESS );

    bytes: DWORD;
    serverInfo: CD_IO_SERVER_INFORMATION;
    serverInfo.InputAvailableEvent = shell.inputEventHandle;
    ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_SET_SERVER_INFORMATION, *serverInfo,
                           size_of(CD_IO_SERVER_INFORMATION), NULL, 0, *bytes, NULL );
    if !ok
    {
        log_error( "CONDRV_SET_SERVER_INFORMATION failed: %\n", get_error_value_and_string() );
        return false;
    }

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
    ok = CreateProcessW( NULL, cmd, NULL, NULL, .TRUE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, *si.StartupInfo, *pi );
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

        // Read next command and optionally send result of the last one
        ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_IO, ifx send_io_complete then *io_complete else null,
                               xx ifx send_io_complete size_of(CD_IO_COMPLETE) else 0, *ReceiveMsg, size_of(CONSOLE_API_MSG),
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
                    push_context
                    {
                        log_error( "CONDRV_READ_IO failed: %\n", get_error_string( err ) );
                    }
                    return 1;
                }
            }
        }

        // We got some command

        send_io_complete = false;
        memset( *io_complete, 0, size_of(CD_IO_COMPLETE) );
        io_complete.Identifier = ReceiveMsg.Descriptor.Identifier;

        // Looks like these are just for ourself
        INPUT_HANDLE  :: 123;
        OUTPUT_HANDLE :: 456;


        if ReceiveMsg.Descriptor.Function ==
        {
            case CONSOLE_IO_CONNECT;
            {
                data: CONSOLE_SERVER_MSG;

                op: CD_IO_OPERATION;
                op.Identifier = ReceiveMsg.Descriptor.Identifier;
                op.Buffer.Offset = 0;
                op.Buffer.Data = *data;
                op.Buffer.Size = size_of(CONSOLE_SERVER_MSG);

                ok = DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_INPUT, *op, size_of(CD_IO_OPERATION), NULL, 0,
                                      *BytesRead, NULL );
                if !ok
                    push_context
                    {
                        log_error( "CONDRV_READ_INPUT failed: %\n", get_error_value_and_string() );
                        return 1;
                    }

                    // TODO Register process info
                // Assert(process_count < sizeof(processes) / sizeof(processes[0]));
                // processes[process_count++] = (HANDLE)ReceiveMsg.Descriptor.Process;
                //
                     // TODO Set window title
                // if (data.Title && process_count == 1) {
                //     memcpy(console_title, data.Title, min((size_t)data.TitleLength + 1, sizeof(console_title)));
                //     console_title[sizeof(console_title) / sizeof(console_title[0]) - 1] = 0;
                // }

                if data.ConsoleApp
                {
                    cpi: CONSOLE_PROCESS_INFO;
                    cpi.dwProcessID = cast(DWORD) ReceiveMsg.Descriptor.Process;
                    cpi.dwFlags = CPI_NEWPROCESSWINDOW;

                    status := shell.consoleControl( .ConsoleNotifyConsoleApplication, *cpi, size_of(CONSOLE_PROCESS_INFO) );
                    if status != STATUS_SUCCESS
                        push_context
                        {
                            // TODO https://stackoverflow.com/questions/78683179/which-api-returns-the-message-for-ntstatus
                            log_error( "ConsoleControl failed: %\n", formatInt( status , base=16 ) );
                            return 1;
                        }
                }
                // todo: allocate new console if not created before
                // todo: notify OS that app is foreground
                // todo: create IO handles?

                // Reply with success
                connect_info: CD_CONNECTION_INFORMATION;
                connect_info.Input = INPUT_HANDLE;
                connect_info.Output = OUTPUT_HANDLE;
                connect_info.Process = ReceiveMsg.Descriptor.Process;

                io_complete.IoStatus.Status = STATUS_SUCCESS;
                io_complete.IoStatus.Information = size_of(CD_CONNECTION_INFORMATION);
                io_complete.Write.Data = *connect_info;
                io_complete.Write.Size = size_of(CD_CONNECTION_INFORMATION);
                ok = DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_COMPLETE_IO, *io_complete, size_of(CD_IO_COMPLETE),
                                      NULL, 0, *BytesRead, NULL );
                if !ok
                    push_context
                    {
                        log_error( "CONDRV_COMPLETE_IO failed: %\n", get_error_value_and_string() );
                        return 1;
                    }
            }

            // TODO 
            // case CONSOLE_IO_DISCONNECT;
            // case CONSOLE_IO_CREATE_OBJECT;
            // case CONSOLE_IO_RAW_READ;

            case CONSOLE_IO_RAW_WRITE;
            {
                send_io_complete = true;
                if ReceiveMsg.Descriptor.Object == OUTPUT_HANDLE
                {
                    memset( *ReceiveMsg.u.consoleMsgL1.WriteConsole, 0, size_of(CONSOLE_WRITECONSOLE_MSG) );
                    // Required for Wait blocks to identify the right callback.
                    ReceiveMsg.msgHeader.ApiNumber = API_NUMBER_WRITECONSOLE;
                    ReceiveMsg.msgHeader.ApiDescriptorSize = 0;

                    status := HandleWriteMessage( shell, *ReceiveMsg, *io_complete );
                    // TODO There's a whole thing with a 'ReplyPending' state that can be returned from
                    // ApiDispatchers::ServerWriteConsole, but I dont think we care about any of that crap?
                    /*
                    if (hr == STATUS_TIMEOUT) {
                        send_io_complete = false;
                        delayed_io_msg = ReceiveMsg;
                        has_delayed_io_msg = true;
                    } else {*/
                    io_complete.IoStatus.Status = status;
                    //}
                }
                // else
                // TODO Shouldnt we at least indicate failure in the response?

            }

            case CONSOLE_IO_USER_DEFINED;
            {
                LayerNumber: ULONG = (ReceiveMsg.msgHeader.ApiNumber >> 24) - 1;
                ApiNumber: ULONG = ReceiveMsg.msgHeader.ApiNumber & 0xffffff;

                // Default is reply with failure
                send_io_complete = true;
                io_complete.IoStatus.Status = STATUS_UNSUCCESSFUL;
                io_complete.Write.Data = *ReceiveMsg.u;
                io_complete.Write.Size = ReceiveMsg.msgHeader.ApiDescriptorSize;

                if LayerNumber ==
                {
                    case 0;
                    {
                        l1_type := cast(CONSOLE_L1_API_TYPE) ApiNumber;
                        if l1_type ==
                        {
                            // TODO 
                            
                            // case Api_GetConsoleCP;
                            // {
                            //     getcp_msg := *ReceiveMsg.u.consoleMsgL1.GetConsoleCP;
                            //     getcp_msg.CodePage = ifx getcp_msg.Output then output_cp else input_cp;
                            //
                            //     io_complete.IoStatus.Status = STATUS_SUCCESS;
                            // }
                            case .Api_GetConsoleMode;
                            {
                                get_console_msg: *CONSOLE_MODE_MSG = *ReceiveMsg.u.consoleMsgL1.GetConsoleMode;

                                get_console_msg.Mode = ifx ReceiveMsg.Descriptor.Object == INPUT_HANDLE
                                                       then shell.input_console_mode else shell.output_console_mode;
                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

                            case .Api_GetConsoleLangId;
                                // This is now unsupported, except for CJK languages
                                // TODO See GetConsoleLangId in terminal/src/host/srvinit.cpp
                                io_complete.IoStatus.Status = STATUS_NOT_SUPPORTED;

                            case;
                                push_context
                                {
                                    log_warn( "Unhandled L1 request %\n", ApiNumber );
                                }
                        }
                    }
                    case 1;
                    {
                        l2_type := cast(CONSOLE_L2_API_TYPE) ApiNumber;
                        if l2_type ==
                        {
                            // TODO 

                            case;
                                push_context
                                {
                                    log_warn( "Unhandled L2 request %\n", ApiNumber );
                                }
                        }
                    }
                    case 2;
                    {
                        l3_type := cast(CONSOLE_L3_API_TYPE) ApiNumber;
                        if l3_type ==
                        {
                            // TODO 

                            case;
                                push_context
                                {
                                    log_warn( "Unhandled L3 request %\n", ApiNumber );
                                }
                        }
                    }

                    case;
                        push_context
                        {
                            log_error( "Unknown layer % request %\n", LayerNumber, ApiNumber );
                        }
                }
            }

            case;
                push_context
                {
                    log_warn( "Unhandled CONDRV_READ_IO msg: %\n", ReceiveMsg.Descriptor.Function );
                }
        }
    }

    return 0;
}

HandleWriteMessage :: ( shell: *CmdHostedShell, ReceiveMsg: *CONSOLE_API_MSG, io_complete: *CD_IO_COMPLETE ) -> NTSTATUS #c_call
{
    write_msg := *ReceiveMsg.u.consoleMsgL1.WriteConsole;

    // no offset with raw requests
    readOffset := cast(ULONG) (ifx ReceiveMsg.Descriptor.Function == CONSOLE_IO_RAW_WRITE
                               then 0 else ReceiveMsg.msgHeader.ApiDescriptorSize + size_of(CONSOLE_MSG_HEADER));
    totalBytes := ReceiveMsg.Descriptor.InputSize - readOffset;

    #if false
    {
        read_op: CD_IO_OPERATION;
        read_op.Identifier = ReceiveMsg.Descriptor.Identifier;
        read_op.Buffer.Offset = readOffset;
        // TODO TODO TODO This is crap obvs
        read_op.Buffer.Data = shell.outputBuffer.data;
        read_op.Buffer.Size = totalBytes;

        bytesRead: DWORD;
        ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_INPUT, *read_op, size_of(CD_IO_OPERATION), NULL, 0,
        *bytesRead, NULL );
        if !ok
        push_context
        {
            log_error( "CONDRV_READ_INPUT failed: %\n", get_error_value_and_string() );
            return STATUS_UNSUCCESSFUL;
        }
    }

    writtenBytes: ULONG;
    // TODO Write a simple cmdline app to test the various console output methods together with codepages etc
    // TODO Add CP handling to splat2 to benchmark the 3 branches here?
    if write_msg.Unicode
    {
        // TODO Convert to utf8

    }
    else
    {
        // TODO Investigate if there's a way to force set a utf8 codepage at the shell (cmd) level, so all spawned apps use that
        // if shell.output_cp == CP_UTF8
        {
            // TODO Get some stats going for how many bytes per sec. the IO thread is actually filling here
            // TODO Try to figure out a way to easily determine whether any bottlenecks are in the shell or our parsing

            // success, outBytes = ReadPipe( shell, range );
            ok := BOOL.TRUE;
            while writtenBytes < totalBytes && ok
            {
                // TODO Atomics!
                range: [] u8;
                push_context
                {
                    range = GetNextWriteableRange( shell.sourceBuffer );
                }

                read_op: CD_IO_OPERATION;
                read_op.Identifier = ReceiveMsg.Descriptor.Identifier;
                read_op.Buffer.Offset = readOffset;
                read_op.Buffer.Data = range.data;
                read_op.Buffer.Size = totalBytes - writtenBytes;

                bytesRead: DWORD;
                ok = DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_INPUT, *read_op, size_of(CD_IO_OPERATION), NULL,
                                      0, *bytesRead, NULL );
                if ok
                {
                    if bytesRead
                    {
                        // TODO TODO TODO Ensure we write a line terminator, but dont commit it so its overwritten next time
                        // If we dont do this ParseLines will freak out because it doesnt know where to end!?
                        // That's not making a lot of sense though.. How did this even work with other shells then?
                        // range[ bytesRead ] = 10;

                        push_context
                        {
                            CommitWrite( shell.sourceBuffer, xx bytesRead );
                        }
                        writtenBytes += bytesRead;
                    }
                }
                else
                    push_context
                    {
                        log_error( "CONDRV_READ_INPUT failed: %\n", get_error_value_and_string() );
                        return STATUS_UNSUCCESSFUL;
                    }
            }
        }
        // else
        {
            // TODO Ansi mode requires DOUBLE conversion, first to utf16 (using the current output codepage) and then to utf8

        }
    }

    write_msg.NumBytes = writtenBytes;
    io_complete.IoStatus.Information = writtenBytes;
    return STATUS_SUCCESS;
}


CmdHostedShellRead :: ( base: *Shell, sourceBuffer: *SourceBuffer ) -> Process_Result, s64
{
    shell: *CmdHostedShell = xx base;

    totalBytes := 0;
    result: Process_Result = .{ type = .STILL_RUNNING };

    if shell.eof
    {
        // TODO Sync exit code with IO thread
        result = .{type = .EXITED, exit_code = -1};
        return result, totalBytes;
    }

    // TODO Atomics!
    // absStartP := shell.sourceBuffer.absoluteHeadPos;
    // totalBytes = absStartP - shell.lastSourceAbsP;
    // shell.lastSourceAbsP = absStartP;

    return result, totalBytes;
}
