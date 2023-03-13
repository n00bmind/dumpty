ShellState :: struct
{

}


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

ReadShellOutput :: ( process: *Process, sourceBuffer: *SourceBuffer ) -> bool, Process_Result
{
    // TODO Do this properly without copies (call read_pipe directly)
    outBuffer: [1024] u8;
    errBuffer: [1024] u8;
    // TODO Eventually we need to wait on multiple objects instead of polling/sleeping
    // (which sadly means we'll need to go full platform-dependant I think)
    success, output_bytes, error_bytes
        := read_from_process( process, outBuffer, errBuffer, timeout_ms = 10 );

    // FIXME There's no real way to correctly interleave these as we have no way of knowing what was written when..
    // I suppose for this we'd need the full-on integration that jfhs was implementing on his project?
    if output_bytes
    {
        out: string = ---;
        out.data = outBuffer.data;
        out.count = output_bytes;
        AppendToSourceBuffer( sourceBuffer, out );
    }

    if error_bytes
    {
        out: string = ---;
        out.data = errBuffer.data;
        out.count = error_bytes;
        AppendToSourceBuffer( sourceBuffer, out );
    }

    result: Process_Result;
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

