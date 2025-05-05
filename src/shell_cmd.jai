ShellState :: struct
{

}


// TODO Investigate using Job Objects on windows (https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
// so that any child processes we crate here are auto assigned to the same job object
// Investigate whether that would cause any child processes to be killed when the parent process dies for whatever reason
StartShell :: ( process: *Process ) -> bool
{
    // TODO Do we need to cache / process this?
    workingDir := get_working_directory();

    success := create_process( process, "cmd.exe",
                               working_directory = workingDir,
                               capture_and_return_output = true,
                               arg_quoting = Process_Argument_Quoting.NEVER_QUOTE );

    if !success
        // TODO Diagnostics
        return false;

    return true;
}

ExecuteShellCommand :: ( process: *Process, command: [] u8 ) -> bool
{
    result, bytesWritten := write_to_process( process, command );
    assert( bytesWritten == command.count, "Couldn't write full command" );
    return result;
}


ExecuteBuiltinCommand :: ( process: *Process, command: [] u8, appState: *AppState ) -> bool
{
    Reset( *appState.builtinProcess );

    // Extract command
    found, cmd, args := split_from_left( xx command, #char " " );

    // TODO builtins table
    if cmd == "#run"
    {
        cmdArgs := break_command_into_strings( args );
        success := create_process( process, ..cmdArgs,
                                   working_directory = get_working_directory(),
                                   capture_and_return_output = true,
                                   arg_quoting = Process_Argument_Quoting.NEVER_QUOTE );

        // TODO Diagnostics
        return success;
    }
    else
    {
        AppendToSourceBuffer( *appState.sourceBuffer, tprint( "<<replr>> Unknown builtin: %\n", cmd ) );
        return true;
    }
}


WriteToProcess :: ( process: *Process, str: string ) -> bool
{
    result, bytesWritten := write_to_process( process, xx str );
    assert( bytesWritten == str.count, "Couldn't write full string" );
    return result;
}


// timeoutMs == -1 means wait forever
// timeoutMs == 0 means dont wait at all
WaitForAllOpenHandles :: ( appState: *AppState, timeoutMs := -1 ) -> bool
{
#if OS == .WINDOWS
{
    handles: [4] HANDLE = ---;
    handleCount: u32 = 0;

    if IsRunning( appState.builtinProcess )
    {
        if !appState.builtinProcess.output.eof
        {
            handles[handleCount] = appState.builtinProcess.output.overlapped.hEvent;
            handleCount += 1;
        }
        if !appState.builtinProcess.error.eof
        {
            handles[handleCount] = appState.builtinProcess.error.overlapped.hEvent;
            handleCount += 1;
        }
    }

    if IsRunning( appState.shellProcess )
    {
        if !appState.shellProcess.output.eof
        {
            handles[handleCount] = appState.shellProcess.output.overlapped.hEvent;
            handleCount += 1;
        }
        if !appState.shellProcess.error.eof
        {
            handles[handleCount] = appState.shellProcess.error.overlapped.hEvent;
            handleCount += 1;
        }
    }

    timeout := INFINITE;
    if timeoutMs >= 0
        timeout = cast(u32) timeoutMs;

    result := MsgWaitForMultipleObjects( handleCount, handles.data, .FALSE, timeout, QS_ALLINPUT );

    if result >= WAIT_ABANDONED_0 && result != WAIT_TIMEOUT
    {
        // TODO Logs / diagnotics
        log_error("Unable to read command's output.\n");
        return false;
    }
    // else
    // {
    //     print( "MsgWaitForMultipleObjects result: %\n", result );
    // }
}
else
{
    #assert( false && "Implement me" );
}
    
    return true;
}

ReadProcessOutput :: ( process: *Process, sourceBuffer: *SourceBuffer ) -> bool, Process_Result
{
    absStartP := sourceBuffer.absoluteHeadPos;

    outBytes, errBytes: s64;
    if !process.output.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success: bool;
        success, outBytes = read_pipe( *process.output, range );

        if outBytes
            CommitWrite( sourceBuffer, outBytes );
    }
    if !process.error.eof
    {
        range := GetNextWriteableRange( sourceBuffer );

        success: bool;
        success, errBytes = read_pipe( *process.error, range );

        if errBytes
            CommitWrite( sourceBuffer, errBytes );
    }

    totalBytes := outBytes + errBytes;
    if totalBytes > 0
        ParseLines( sourceBuffer, absStartP, totalBytes );


    success := true;
    result: Process_Result = .{ type = .STILL_RUNNING };
    // No more output, so check if it's been killed
    if process.output.eof && process.error.eof
    {
        success, result = get_process_result( process );
        if success
        {
            if result.type == .STILL_RUNNING
                return true, result;
        }
        else
        {
            error_code, error_string := get_error_value_and_string();
            // TODO Diagnostics
            //log_error( "Couldn’t get process result for command \"%\": % %", get_quoted_command_string(args), error_code, error_string );
            kill_process( process );
            result = .{type = .EXITED, exit_code = 1};
        }

        return false, result;
    }

    return true, result;
}

#scope_file

#if OS == .WINDOWS
{
    #import "Windows";

    WAIT_ABANDONED_0 :: 0x00000080;

    kernel32 :: #system_library "kernel32";
    user32   :: #system_library "user32";
    MsgWaitForMultipleObjects :: ( nCount: DWORD, lpHandles: *HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD, dwWakeMask: DWORD ) -> DWORD #foreign user32;

    QS_KEY            :: 0x0001;
    QS_MOUSEMOVE      :: 0x0002;
    QS_MOUSEBUTTON    :: 0x0004;
    QS_MOUSE          :: (QS_MOUSEMOVE | QS_MOUSEBUTTON);
    QS_POSTMESSAGE    :: 0x0008;
    QS_TIMER          :: 0x0010;
    QS_PAINT          :: 0x0020;
    QS_SENDMESSAGE    :: 0x0040;
    QS_HOTKEY         :: 0x0080;
    QS_ALLPOSTMESSAGE :: 0x0100;
    QS_RAWINPUT       :: 0x0400;
    QS_TOUCH          :: 0x0800;
    QS_POINTER        :: 0x1000;
    QS_INPUT          :: (QS_MOUSE     | QS_KEY         | QS_RAWINPUT | QS_TOUCH | QS_POINTER);
    QS_ALLEVENTS      :: (QS_INPUT     | QS_POSTMESSAGE | QS_TIMER    | QS_PAINT | QS_HOTKEY);
    QS_ALLINPUT       :: (QS_ALLEVENTS | QS_SENDMESSAGE);
}
