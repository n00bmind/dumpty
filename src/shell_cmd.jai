CmdShell :: struct
{
    #as using base: Shell;
    base.startProc              = CmdShellStart;
    base.shutdownProc           = CmdShellShutdown;
    base.writeProc              = CmdShellWrite;
    base.readProc               = CmdShellRead;
    base.getWaitableHandlesProc = CmdShellGetWaitableHandles;

    process: Process;
}


#scope_file

// TODO Investigate using Job Objects on windows (https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
// so that any child processes we create here are auto assigned to the same job object
// which would cause any child processes to be killed when the parent process dies for whatever reason
CmdShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdShell = xx base;

    // TODO This doesnt seem to have any effect.. presumably because intercepting VT code is something *conhost* would do?
    #if 0
    {
        WinConMode: DWORD;
        EnableProcessedOutput :: 0x0001;
        EnableVirtualTerminalProcessing :: 0x0004;

        hConsole := GetStdHandle( STD_OUTPUT_HANDLE );
        GetConsoleMode( hConsole, *WinConMode );
        SetConsoleMode( hConsole, WinConMode | EnableProcessedOutput | EnableVirtualTerminalProcessing );
        // TODO There's also a flag for enabling VT *input*
        // https://superuser.com/a/1687688/1026920
    }

    // TODO Do we need to cache / process this?
    workingDir := get_working_directory();


    // TODO Additionally to this, review what refterm does about redirecting/cloning the stdin / stdout handles
    // and see if we can convince 'ls --color=auto' that it is indeed connected to a terminal (same for jai compiler)
    // (also, investigate possible values for the %TERM% variable.. what does WSL set this to?)


    Init( *shell.process );
    // cmdPath := "C:\\windows\\system32\\cmd.exe";
    success := create_process( *shell.process, "cmd.exe",
                               working_directory = workingDir,
                               capture_and_return_output = true,
                               arg_quoting = Process_Argument_Quoting.NEVER_QUOTE );

    if !success
        // TODO Diagnostics
        return false;

    return true;
}

CmdShellShutdown :: ( base: *Shell )
{
    shell: *CmdShell = xx base;
    if IsRunning( shell.process )
        Shutdown( *shell.process );
}


CmdShellWrite :: ( base: *Shell, str: string ) -> bool
{
    shell: *CmdShell = xx base;
    result, bytesWritten := write_to_process( *shell.process, xx str );
    assert( bytesWritten == str.count, "Couldn't write full string" );
    return result;
}

CmdShellRead :: ( base: *Shell, sourceBuffer: *SourceBuffer ) -> Process_Result, s64
{
    shell: *CmdShell = xx base;

    success: bool;
    outBytes, errBytes: s64;
    if !shell.process.output.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success, outBytes = read_pipe( *shell.process.output, range );

        if outBytes
            CommitWrite( sourceBuffer, outBytes );
    }
    if !shell.process.error.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success, errBytes = read_pipe( *shell.process.error, range );

        if errBytes
            CommitWrite( sourceBuffer, errBytes );
    }

    totalBytes := outBytes + errBytes;

    result: Process_Result = .{ type = .STILL_RUNNING };
    // No more output, so check if it's been killed
    if shell.process.output.eof && shell.process.error.eof
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
CmdShellGetWaitableHandles :: ( base: *Shell, handles: [] HANDLE, handleCount: *u32 )
{
    shell: *CmdShell = xx base;

    if IsRunning( shell.process )
    {
        if !shell.process.output.eof
        {
            handles[handleCount.*] = shell.process.output.overlapped.hEvent;
            handleCount.* += 1;
        }
        if !shell.process.error.eof
        {
            handles[handleCount.*] = shell.process.error.overlapped.hEvent;
            handleCount.* += 1;
        }
    }
}


