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
// Investigate whether that would cause any child processes to be killed when the parent process dies for whatever reason
CmdShellStart :: ( base: *Shell ) -> bool
{
    shell: *CmdShell = xx base;

    // TODO Do we need to cache / process this?
    workingDir := get_working_directory();

    Init( *shell.process );
    success := create_process( *shell.process, "cmd.exe",
                               working_directory = workingDir,
                               capture_and_return_output = true,
                               arg_quoting = Process_Argument_Quoting.NEVER_QUOTE );

    if !success
        // TODO Diagnostics
        return false;

    return true;
}

Restart :: ( base: *Shell ) -> bool
{
    shell: *CmdShell = xx base;

    deinit( *shell.process );
    return CmdShellStart( shell );
}

CmdShellShutdown :: ( base: *Shell )
{
    shell: *CmdShell = xx base;
    if IsRunning( shell.process )
        Shutdown( *shell.process );
}

IsRunning :: ( base: *Shell ) -> bool
{
    shell: *CmdShell = xx base;
    return IsRunning( shell.process );
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


