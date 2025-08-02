#import "Windows";
#import "Print_Color"()(USE_ANSI_CODES_ON_WINDOWS=true);

main :: ()
{
    #if 1
    {
        WinConMode: DWORD;
        EnableVirtualTerminalProcessing :: 0x0004;

        hConsole := GetStdHandle( STD_OUTPUT_HANDLE );
        GetConsoleMode( hConsole, *WinConMode );
        SetConsoleMode( hConsole, WinConMode | EnableVirtualTerminalProcessing );
    }
    // TODO Why am I not seeing any ansi codes in the output? Step through the parsing code
    print_color( "Here's a nice message in yellow", color = .YELLOW );

}

