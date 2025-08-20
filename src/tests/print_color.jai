#import "Windows";
#import "Print_Color"()(USE_ANSI_CODES_ON_WINDOWS=true);

main :: ()
{
    #if 1
    {
        WinConMode: DWORD;
        EnableProcessedOutput :: 0x0001;
        EnableVirtualTerminalProcessing :: 0x0004;

        hConsole := GetStdHandle( STD_OUTPUT_HANDLE );
        GetConsoleMode( hConsole, *WinConMode );
        SetConsoleMode( hConsole, WinConMode | EnableProcessedOutput | EnableVirtualTerminalProcessing );
    }

    print_color( "Here's a nice message in yellow", color = .YELLOW );

}

