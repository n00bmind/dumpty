
//// Most of this adapted from https://github.com/jfhs/handterm

CmdHostedShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdHostedShellStart;
    // base.shutdownProc           = CmdHostedShellShutdown;
    // base.writeProc              = CmdHostedShellWrite;
    base.writeEvProc            = CmdHostedShellWriteEv;
    base.readProc               = CmdHostedShellRead;
    // base.getWaitableHandlesProc = CmdHostedShellGetWaitableHandles;

    consoleControl : #type ( Command: CONSOLECONTROL, Information: PVOID, Length: DWORD ) -> NTSTATUS #c_call;

    // TODO This probably needs looser coupling, like a "platform API" of sorts
    // While we're still WIP let's give it unrestricted access to everything..
    appState: *AppState;
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
    // (ansi codepages require *2* conversions, first to utf16 and then to utf8)
    stagingBuffer: [..] u8;
    outputBuffer: [..] u8;

    // TODO Just make this a growable array?
    inputEvents: [8192] KeyEvent;
    // TODO Atomics
    absInputsReadPos: s64;
    absInputsWritePos: s64;

    // TODO Rename to 'pendingInputMsg'
    delayed_io_msg: CONSOLE_API_MSG;

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

    assert( shell.appState && "Need access to the AppState!" );

    shell.consoleControl = xx GetProcAddress( LoadLibraryExA( "user32.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32 ),
                                              "ConsoleControl" );
    assert( shell.consoleControl != null && "Failed retrieving entrypoint 'ConsoleControl' from user32.dll" );

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
        // Read next command and optionally send result of the last one
        ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_IO,
                               ifx send_io_complete then *io_complete else null,
                               xx ifx send_io_complete size_of(CD_IO_COMPLETE) else 0,
                               *ReceiveMsg, size_of(CONSOLE_API_MSG), *BytesRead, NULL );

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
                    // TODO So, since we're passing a fake empty msg here, this means raw writes will always
                    // be interpreted as ansi.. is that even right?
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
                // User defined msgs that query for info get back a msg of the corresponding type here
                // TODO Rename ReceiveMsg to ioMsg
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
                            
                            case .Api_GetConsoleCP;
                            {
                                msg := *ReceiveMsg.u.consoleMsgL1.GetConsoleCP;
                                msg.CodePage = ifx msg.Output then shell.output_cp else shell.input_cp;

                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

                            case .Api_GetConsoleMode;
                            {
                                msg: *CONSOLE_MODE_MSG = *ReceiveMsg.u.consoleMsgL1.GetConsoleMode;

                                msg.Mode = ifx ReceiveMsg.Descriptor.Object == INPUT_HANDLE
                                           then shell.input_console_mode else shell.output_console_mode;
                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

                            case .Api_SetConsoleMode;
                            {
                                msg: *CONSOLE_MODE_MSG = *ReceiveMsg.u.consoleMsgL1.SetConsoleMode;

                                if ReceiveMsg.Descriptor.Object == INPUT_HANDLE
                                    shell.input_console_mode = msg.Mode;
                                else
                                    shell.output_console_mode = msg.Mode;

                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

                            case .Api_ReadConsole;
                            {
                                if ReceiveMsg.Descriptor.Object == INPUT_HANDLE
                                {
                                    status := HandleReadMessage( shell, *ReceiveMsg, *io_complete );
                                    if status == STATUS_TIMEOUT
                                    {
                                        // Cannot immediately return a response here unless we actually have some data to return
                                        send_io_complete = false;
                                        // Store the current msg for processing as new input comes in
                                        shell.delayed_io_msg = ReceiveMsg;
                                        // has_delayed_io_msg = true;
                                    }
                                    else
                                    {
                                        io_complete.IoStatus.Status = status;
                                    }
                                }
                            }

                            case .Api_WriteConsole;
                            {
                                if ReceiveMsg.Descriptor.Object == OUTPUT_HANDLE
                                {
                                    status := HandleWriteMessage( shell, *ReceiveMsg, *io_complete );
                                    io_complete.IoStatus.Status = status;
                                }
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

                            case .Api_GetConsoleScreenBufferInfo;
                            {
                                msg: *CONSOLE_SCREENBUFFERINFO_MSG = *ReceiveMsg.u.consoleMsgL2.GetConsoleScreenBufferInfo;
                                state := shell.appState.renderer;
                                cursor := *state.lastCursor;

                                // TODO Create a tester to ensure we're sending the correct info (in particular, srWindow?)
                                // https://learn.microsoft.com/en-us/windows/console/console-screen-buffer-info-str
                                // TODO Scroll pos / attributes?
                                msg.FullscreenSupported = .FALSE;
                                msg.CursorPosition = .{ xx cursor.x, xx cursor.y };
                                msg.MaximumWindowSize = .{ xx state.cellCount.x, xx state.cellCount.y };
                                msg.Size = .{ xx state.cellCount.x, xx state.cellCount.y };
                                msg.CurrentWindowSize = .{ xx state.cellCount.x, xx state.cellCount.y };
                                msg.ScrollPosition.x = 0;
                                msg.ScrollPosition.y = 0;
                                msg.Attributes = 0;
                                msg.PopupAttributes = 0;
                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

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

                            case .Api_GetConsoleWindow;
                            {
                                msg: *CONSOLE_GETCONSOLEWINDOW_MSG = *ReceiveMsg.u.consoleMsgL3.GetConsoleWindow;
                                msg.hwnd = shell.appState.renderer.window;
                                io_complete.IoStatus.Status = STATUS_SUCCESS;
                            }

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

HandleReadMessage :: ( shell: *CmdHostedShell, ReceiveMsg: *CONSOLE_API_MSG, io_complete: *CD_IO_COMPLETE ) -> NTSTATUS #c_call
{
    line_mode_enabled := shell.input_console_mode & ENABLE_LINE_INPUT;

     // TODO Atomics / lock
    readPos := shell.absInputsReadPos % shell.inputEvents.count;
    writePos := shell.absInputsWritePos % shell.inputEvents.count;

    // Nothing to read
    if readPos == writePos
        return STATUS_TIMEOUT;

    read_msg: *CONSOLE_READCONSOLE_MSG = *ReceiveMsg.u.consoleMsgL1.ReadConsole;

    // TODO Check Terminal code to figure out what this is about
    if read_msg.InitialNumBytes
        return STATUS_NOT_SUPPORTED;

    write_op: CD_IO_OPERATION;
    write_op.Identifier = ReceiveMsg.Descriptor.Identifier;
    // no offset with raw requests
    write_op.Buffer.Offset = ifx ReceiveMsg.Descriptor.Function == CONSOLE_IO_RAW_READ
                             then 0 else ReceiveMsg.msgHeader.ApiDescriptorSize;

    return STATUS_SUCCESS;
}

// TODO Should we just push a context before calling in here?
// Would be interesting to compare if there's any kind of measurable speed difference?
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

    // TODO Review if we want / need to do anything for these flags:
    // ENABLE_VIRTUAL_TERMINAL_PROCESSING
    // ENABLE_PROCESSED_OUTPUT
    // ENABLE_WRAP_AT_EOL_OUTPUT

    writtenBytes: ULONG;
    // TODO Write a simple cmdline app to test the various console output methods together with codepages etc
    // TODO Add CP handling to splat2 to benchmark the 3 branches here?
    if write_msg.Unicode
    {
        // TODO Investigate faster conversion functions
        // https://learn.microsoft.com/en-us/windows/win32/devnotes/rtlunicodetoutf8n
        // https://doxygen.reactos.org/d0/d25/host_2wine_2unicode_8h.html#a4ebb1e7521c31f253a6ffff808adc668

        // Copy to staging buffer
        push_context
        {
            array_resize( *shell.stagingBuffer, totalBytes, false ); // Don't init the new range
        }

        read_op: CD_IO_OPERATION;
        read_op.Identifier = ReceiveMsg.Descriptor.Identifier;
        read_op.Buffer.Offset = readOffset;
        read_op.Buffer.Data = shell.stagingBuffer.data;
        read_op.Buffer.Size = totalBytes;

        bytesRead: DWORD;
        ok := DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_INPUT, *read_op, size_of(CD_IO_OPERATION), NULL,
                               0, *bytesRead, NULL );

        if !ok || bytesRead < totalBytes
            push_context
            {
                log_error( "CONDRV_READ_INPUT failed: %\n", get_error_value_and_string() );
                return STATUS_UNSUCCESSFUL;
            }

        // Convert to utf8
        // TODO Convert directly into the final SourceBuffer location, using something like GetContiguousView
        // Here we're writing though.. so we'll need an extra post-copy step when the length straddles the end of the buffer
        totalChars := totalBytes / 2;
        // Worst case is 3 utf8 code units (bytes) per utf16 code unit ("char")
        maxRequiredBytes := totalChars * 3;
        push_context
        {
            assert( totalBytes & 1 == 0 && "Incoming utf16 byte length is not divisible by 2" );
            array_resize( *shell.outputBuffer, maxRequiredBytes, false ); // Don't init the new range
        }

        writtenBytes = xx WideCharToMultiByte( CP_UTF8, 0, xx shell.stagingBuffer.data, xx totalChars,
                                               shell.outputBuffer.data, xx maxRequiredBytes, NULL, NULL );

        if !writtenBytes
            push_context
            {
                log_error( "WideCharToMultiByte failed: %\n", get_error_value_and_string() );
                return STATUS_UNSUCCESSFUL;
            }

        // Finally copy to SourceBuffer
        // TODO Atomics!
        range: [] u8;
        push_context
        {
            range = GetNextWriteableRange( *shell.appState.sourceBuffer );
        }

        // FIXME Ensure returned range can hold writtenBytes! It's just easier to do the GetContiguousView thing though..
        memcpy( range.data, shell.outputBuffer.data, writtenBytes );
        push_context
        {
            CommitWrite( *shell.appState.sourceBuffer, xx writtenBytes );
        }
    }
    else
    {
        // TODO Investigate if there's a way to force set a utf8 codepage at the shell (cmd) level, so all spawned apps use that
        // (surprise surprise.. look like this is a bit of a minefield: https://stackoverflow.com/a/57134096/2151254)

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
                    range = GetNextWriteableRange( *shell.appState.sourceBuffer );
                }

                read_op: CD_IO_OPERATION;
                read_op.Identifier = ReceiveMsg.Descriptor.Identifier;
                read_op.Buffer.Offset = readOffset;
                read_op.Buffer.Data = range.data;
                read_op.Buffer.Size = cMin( totalBytes - writtenBytes, cast(u32) range.count );

                bytesRead: DWORD;
                ok = DeviceIoControl( shell.serverHandle, IOCTL_CONDRV_READ_INPUT, *read_op, size_of(CD_IO_OPERATION), NULL,
                                      0, *bytesRead, NULL );
                if ok
                {
                    if bytesRead
                    {
                        push_context
                        {
                            CommitWrite( *shell.appState.sourceBuffer, xx bytesRead );
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

CmdHostedShellWriteEv :: ( base: *Shell, event: KeyEvent ) -> bool
{
    shell: *CmdHostedShell = xx base;

    // TODO Atomics
    // TODO There's no atomic way to both increment this counter while also ensuring we havent overflowed the inputEvents
    // and hence we're writing to a position that's being concurrently read or whatever..
    // Also, what's the strategy for really long lines here?
    // So this probably requires a mutex!
    writePos := shell.absInputsWritePos % shell.inputEvents.count;
    shell.absInputsWritePos += 1;

    shell.inputEvents[writePos] = event;

    // TODO We're also supposed to call this on every buffer resize event
    SetEvent( shell.inputEventHandle );

    return true;
}
