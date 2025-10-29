
//// References:
// https://github.com/jfhs/handterm
// https://github.com/microsoft/terminal
//


/*
Copyright (c) Microsoft Corporation. All rights reserved.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/*++

Copyright (c) Microsoft Corporation. All rights reserved.
Licensed under the MIT license.

Module Name:

    condrv.h

Abstract:

    This module contains the declarations shared by the console driver and the
    user-mode components that use it.

Author:

    Wedson Almeida Filho (wedsonaf) 24-Sep-2009

Environment:

    Kernel and user modes.

--*/

//
// Messages that can be received by servers, used in CD_IO_DESCRIPTOR::Function.
//

CONSOLE_IO_CONNECT        :: 0x01;
CONSOLE_IO_DISCONNECT     :: 0x02;
CONSOLE_IO_CREATE_OBJECT  :: 0x03;
CONSOLE_IO_CLOSE_OBJECT   :: 0x04;
CONSOLE_IO_RAW_WRITE      :: 0x05;
CONSOLE_IO_RAW_READ       :: 0x06;
CONSOLE_IO_USER_DEFINED   :: 0x07;
CONSOLE_IO_RAW_FLUSH      :: 0x08;

//
// Header of all IOs submitted to a server.
//

CD_IO_DESCRIPTOR :: struct
{
    Identifier: LUID;
    Process: ULONG_PTR;
    Object: ULONG_PTR;
    Function: ULONG;
    InputSize: ULONG;
    OutputSize: ULONG;
    Reserved: ULONG;
}

//
// Types of objects, used in CREATE_OBJECT_INFORMATION::ObjectType.
//

CD_IO_OBJECT_TYPE_CURRENT_INPUT   :: 0x01;
CD_IO_OBJECT_TYPE_CURRENT_OUTPUT  :: 0x02;
CD_IO_OBJECT_TYPE_NEW_OUTPUT      :: 0x03;
CD_IO_OBJECT_TYPE_GENERIC         :: 0x04;

//
// Payload of the CONSOLE_IO_CREATE_OBJECT io.
//

CD_CREATE_OBJECT_INFORMATION :: struct
{
    ObjectType: ULONG;
    ShareMode: ULONG;
    DesiredAccess: ACCESS_MASK;
}

// //
// // Create EA buffers.
// //
//
// #define CD_BROKER_EA_NAME "broker"
// #define CD_SERVER_EA_NAME "server"
// #define CD_ATTACH_EA_NAME "attach"
//
// typedef struct _CD_CREATE_SERVER {
//     HANDLE BrokerHandle;
//     LUID BrokerRequest;
// } CD_CREATE_SERVER, *PCD_CREATE_SERVER;
//
// typedef struct _CD_ATTACH_INFORMATION {
//     HANDLE ProcessId;
// } CD_ATTACH_INFORMATION, *PCD_ATTACH_INFORMATION;
//
// typedef struct _CD_ATTACH_INFORMATION64 {
//     PVOID64 ProcessId;
// } CD_ATTACH_INFORMATION64, *PCD_ATTACH_INFORMATION64;

//
// Information passed to the driver by a server when a connection is accepted.
//

CD_CONNECTION_INFORMATION :: struct
{
    Process: ULONG_PTR;
    Input: ULONG_PTR;
    Output: ULONG_PTR;
}

// //
// // Ioctls.
// //
//
// typedef struct _CD_IO_BUFFER {
//     ULONG Size;
//     PVOID Buffer;
// } CD_IO_BUFFER, *PCD_IO_BUFFER;
//
// typedef struct _CD_IO_BUFFER64 {
//     ULONG Size;
//     PVOID64 Buffer;
// } CD_IO_BUFFER64, *PCD_IO_BUFFER64;
//
// typedef struct _CD_USER_DEFINED_IO {
//     HANDLE Client;
//     ULONG InputCount;
//     ULONG OutputCount;
//     CD_IO_BUFFER Buffers[ANYSIZE_ARRAY];
// } CD_USER_DEFINED_IO, *PCD_USER_DEFINED_IO;
//
// typedef struct _CD_USER_DEFINED_IO64 {
//     PVOID64 Client;
//     ULONG InputCount;
//     ULONG OutputCount;
//     CD_IO_BUFFER64 Buffers[ANYSIZE_ARRAY];
// } CD_USER_DEFINED_IO64, *PCD_USER_DEFINED_IO64;

CD_IO_BUFFER_DESCRIPTOR :: struct
{
    Data: *void;
    Size: ULONG;
    Offset: ULONG;
}

CD_IO_COMPLETE :: struct
{
    Identifier: LUID;
    IoStatus: IO_STATUS_BLOCK;
    Write: CD_IO_BUFFER_DESCRIPTOR;
}

CD_IO_OPERATION :: struct
{
    Identifier: LUID;
    Buffer: CD_IO_BUFFER_DESCRIPTOR;
}

CD_IO_SERVER_INFORMATION :: struct
{
    InputAvailableEvent: HANDLE;
}

// typedef struct _CD_IO_DISPLAY_SIZE {
//     ULONG Width;
//     ULONG Height;
// } CD_IO_DISPLAY_SIZE, *PCD_IO_DISPLAY_SIZE;
//
// typedef struct _CD_IO_CHARACTER {
//     WCHAR Character;
//     USHORT Attribute;
// } CD_IO_CHARACTER, *PCD_IO_CHARACTER;
//
// typedef struct _CD_IO_ROW_INFORMATION {
//     SHORT Index;
//     PCD_IO_CHARACTER Old;
//     PCD_IO_CHARACTER New;
// } CD_IO_ROW_INFORMATION, *PCD_IO_ROW_INFORMATION;
//
// typedef struct _CD_IO_CURSOR_INFORMATION {
//     USHORT Column;
//     USHORT Row;
//     ULONG Height;
//     BOOLEAN IsVisible;
// } CD_IO_CURSOR_INFORMATION, *PCD_IO_CURSOR_INFORMATION;
//
// typedef struct _CD_IO_FONT_SIZE {
//     ULONG Width;
//     ULONG Height;
// } CD_IO_FONT_SIZE, *PCD_IO_FONT_SIZE;

IOCTL_CONDRV_READ_IO :: #run CTL_CODE( FILE_DEVICE_CONSOLE, 1, METHOD_OUT_DIRECT, FILE_ANY_ACCESS );

IOCTL_CONDRV_COMPLETE_IO :: #run CTL_CODE( FILE_DEVICE_CONSOLE, 2, METHOD_NEITHER, FILE_ANY_ACCESS );

IOCTL_CONDRV_READ_INPUT :: #run CTL_CODE( FILE_DEVICE_CONSOLE, 3, METHOD_NEITHER, FILE_ANY_ACCESS );

// #define IOCTL_CONDRV_WRITE_OUTPUT \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 4, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_ISSUE_USER_IO \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 5, METHOD_OUT_DIRECT, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_DISCONNECT_PIPE \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 6, METHOD_NEITHER, FILE_ANY_ACCESS)

IOCTL_CONDRV_SET_SERVER_INFORMATION :: #run CTL_CODE( FILE_DEVICE_CONSOLE, 7, METHOD_NEITHER, FILE_ANY_ACCESS );

// #define IOCTL_CONDRV_GET_SERVER_PID \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 8, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_GET_DISPLAY_SIZE \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 9, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_UPDATE_DISPLAY \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 10, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_SET_CURSOR \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 11, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_ALLOW_VIA_UIACCESS \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 12, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_LAUNCH_SERVER \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 13, METHOD_NEITHER, FILE_ANY_ACCESS)
//
// #define IOCTL_CONDRV_GET_FONT_SIZE \
//     CTL_CODE(FILE_DEVICE_CONSOLE, 14, METHOD_NEITHER, FILE_ANY_ACCESS)
//


/*++

Copyright (c) Microsoft Corporation. All rights reserved.

Module Name:

    conmsgl1.h

Abstract:

    This include file defines the layer 1 message formats used to communicate
    between the client and server portions of the CONSOLE portion of the
    Windows subsystem.

Author:

    Therese Stowell (thereses) 10-Nov-1990

Revision History:

    Wedson Almeida Filho (wedsonaf) 23-May-2010
        Modified the messages for use with the console driver.

--*/

CONSOLE_FIRST_API_NUMBER :: ( Layer: u32 ) -> u32 #expand
{
    return (Layer << 24);
}

CONSOLE_SERVER_MSG :: struct
{
    IconId: ULONG;
    HotKey: ULONG;
    StartupFlags: ULONG;
    FillAttribute: USHORT;
    ShowWindow: USHORT;
    ScreenBufferSize: COORD;
    WindowSize: COORD;
    WindowOrigin: COORD;
    ProcessGroupId: ULONG;
    ConsoleApp: BOOLEAN;
    WindowVisible: BOOLEAN;
    TitleLength: USHORT;
    Title: [MAX_PATH + 1] WCHAR;
    ApplicationNameLength: USHORT;
    ApplicationName: [128] WCHAR;
    CurrentDirectoryLength: USHORT;
    CurrentDirectory: [MAX_PATH + 1] WCHAR;
}

// typedef struct _CONSOLE_BROKER_DATA {
//     WCHAR DesktopName[MAX_PATH];
// } CONSOLE_BROKER_MSG, * PCONSOLE_BROKER_MSG;

CONSOLE_GETCP_MSG :: struct
{
    CodePage: ULONG;
    Output: BOOLEAN;
}

CONSOLE_MODE_MSG :: struct
{
    Mode: ULONG;
}

CONSOLE_GETNUMBEROFINPUTEVENTS_MSG :: struct
{
    ReadyEvents: ULONG;
}

CONSOLE_GETCONSOLEINPUT_MSG :: struct
{
    NumRecords: ULONG;
    Flags: USHORT;
    Unicode: BOOLEAN;
}

CONSOLE_READCONSOLE_MSG :: struct
{
    Unicode: BOOLEAN;
    ProcessControlZ: BOOLEAN;
    ExeNameLength: USHORT;
    InitialNumBytes: ULONG;
    CtrlWakeupMask: ULONG;
    ControlKeyState: ULONG;
    NumBytes: ULONG;
}

CONSOLE_WRITECONSOLE_MSG :: struct
{
    NumBytes: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_LANGID_MSG :: struct
{
    LangId: LANGID;
}

CONSOLE_MAPBITMAP_MSG :: struct
{
    Mutex: HANDLE;
    Bitmap: PVOID;
}

CONSOLE_MAPBITMAP_MSG64 :: struct
{
    Mutex: PVOID64;
    Bitmap: PVOID64;
}

CONSOLE_API_NUMBER_L1 :: enum
{
    ConsolepGetCP :: #run CONSOLE_FIRST_API_NUMBER(1);
    ConsolepGetMode;
    ConsolepSetMode;
    ConsolepGetNumberOfInputEvents;
    ConsolepGetConsoleInput;
    ConsolepReadConsole;
    ConsolepWriteConsole;
    ConsolepNotifyLastClose;
    ConsolepGetLangId;
    ConsolepMapBitmap;
}

CONSOLE_MSG_HEADER :: struct
{
    ApiNumber: ULONG;
    ApiDescriptorSize: ULONG;
}

CONSOLE_MSG_BODY_L1 :: union
{
    GetConsoleCP: CONSOLE_GETCP_MSG;
    GetConsoleMode: CONSOLE_MODE_MSG;
    SetConsoleMode: CONSOLE_MODE_MSG;
    GetNumberOfConsoleInputEvents: CONSOLE_GETNUMBEROFINPUTEVENTS_MSG;
    GetConsoleInput: CONSOLE_GETCONSOLEINPUT_MSG;
    ReadConsole: CONSOLE_READCONSOLE_MSG;
    WriteConsole: CONSOLE_WRITECONSOLE_MSG;
    GetConsoleLangId: CONSOLE_LANGID_MSG;

#if false // defined(BUILD_WOW6432) && !defined(BUILD_WOW3232)
    MapBitmap: CONSOLE_MAPBITMAP_MSG64;
else 
    MapBitmap: CONSOLE_MAPBITMAP_MSG;
}

// #ifndef __cplusplus
// typedef struct _CONSOLE_MSG_L1 {
//     CONSOLE_MSG_HEADER Header;
//     union {
//         CONSOLE_MSG_BODY_L1;
//     } u;
// } CONSOLE_MSG_L1, * PCONSOLE_MSG_L1;
// #else
// typedef struct _CONSOLE_MSG_L1 :
//     public CONSOLE_MSG_HEADER
// {
//     CONSOLE_MSG_BODY_L1 u;
// } CONSOLE_MSG_L1, * PCONSOLE_MSG_L1;
// #endif // __cplusplus
//
    // TODO Compare against terminal/src/server/ApiSorter.cpp
    // NOTE Seems to duplicate CONSOLE_API_NUMBER_L1 above
CONSOLE_L1_API_TYPE :: enum
{
    Api_GetConsoleCP;
    Api_GetConsoleMode;
    Api_SetConsoleMode;
    Api_GetNumberOfCOnsoleInputEvents;
    Api_GetConsoleInput;
    Api_ReadConsole;
    Api_WriteConsole;
    Api_ServerConsoleNotifyLastChance;
    Api_GetConsoleLangId;
    Api_ConsoleMapBitmap;
}



/*++

Copyright (c) Microsoft Corporation. All rights reserved.

Module Name:

    conmsgl2.h

Abstract:

    This include file defines the layer 2 message formats used to communicate
    between the client and server portions of the CONSOLE portion of the
    Windows subsystem.

Author:

    Therese Stowell (thereses) 10-Nov-1990

Revision History:

    Wedson Almeida Filho (wedsonaf) 23-May-2010
        Modified the messages for use with the console driver.

--*/

CONSOLE_CREATESCREENBUFFER_MSG :: struct
{
    Flags: ULONG;
    BitmapInfoLength: ULONG;
    Usage: ULONG;
}

CONSOLE_ASCII             :: 0x1;
CONSOLE_REAL_UNICODE      :: 0x2;
CONSOLE_ATTRIBUTE         :: 0x3;
CONSOLE_FALSE_UNICODE     :: 0x4;

CONSOLE_FILLCONSOLEOUTPUT_MSG :: struct
{
    WriteCoord: COORD;
    ElementType: ULONG;
    Element: USHORT;
    Length: ULONG;
}

CONSOLE_CTRLEVENT_MSG :: struct
{
    CtrlEvent: ULONG;
    ProcessGroupId: ULONG;
}

CONSOLE_SETCP_MSG :: struct
{
    CodePage: ULONG;
    Output: BOOLEAN;
}

CONSOLE_GETCURSORINFO_MSG :: struct
{
    CursorSize: ULONG;
    Visible: BOOLEAN;
}

CONSOLE_SETCURSORINFO_MSG :: struct
{
    CursorSize: ULONG;
    Visible: BOOLEAN;
}

CONSOLE_SCREENBUFFERINFO_MSG :: struct
{
    Size: COORD;
    CursorPosition: COORD;
    ScrollPosition: COORD;
    Attributes: USHORT;
    CurrentWindowSize: COORD;
    MaximumWindowSize: COORD;
    PopupAttributes: USHORT;
    FullscreenSupported: BOOLEAN;
    ColorTable: [16] DWORD; // COLORREF
}

CONSOLE_SETSCREENBUFFERSIZE_MSG :: struct
{
    Size: COORD;
}

CONSOLE_SETCURSORPOSITION_MSG :: struct
{
    CursorPosition: COORD;
}

CONSOLE_GETLARGESTWINDOWSIZE_MSG :: struct
{
    Size: COORD;
}

CONSOLE_SCROLLSCREENBUFFER_MSG :: struct
{
    ScrollRectangle: SMALL_RECT;
    ClipRectangle: SMALL_RECT;
    Clip: BOOLEAN;
    Unicode: BOOLEAN;
    DestinationOrigin: COORD;
    Fill: CHAR_INFO;
}

CONSOLE_SETTEXTATTRIBUTE_MSG :: struct
{
    Attributes: USHORT;
}

CONSOLE_SETWINDOWINFO_MSG :: struct
{
    Absolute: BOOLEAN;
    Window: SMALL_RECT;
}

CONSOLE_READCONSOLEOUTPUTSTRING_MSG :: struct
{
    ReadCoord: COORD;
    StringType: ULONG;
    NumRecords: ULONG;
}

CONSOLE_WRITECONSOLEINPUT_MSG :: struct
{
    NumRecords: ULONG;
    Unicode: BOOLEAN;
    Append: BOOLEAN;
}

CONSOLE_WRITECONSOLEOUTPUTSTRING_MSG :: struct
{
    WriteCoord: COORD;
    StringType: ULONG;
    NumRecords: ULONG;
}

CONSOLE_WRITECONSOLEOUTPUT_MSG :: struct
{
    CharRegion: SMALL_RECT;
    Unicode: BOOLEAN;
}

CONSOLE_READCONSOLEOUTPUT_MSG :: struct
{
    CharRegion: SMALL_RECT;
    Unicode: BOOLEAN;
}

CONSOLE_GETTITLE_MSG :: struct
{
    TitleLength: ULONG;
    Unicode: BOOLEAN;
    Original: BOOLEAN;
}

CONSOLE_SETTITLE_MSG :: struct
{
    Unicode: BOOLEAN;
}

CONSOLE_API_NUMBER_L2 :: enum
{
    ConsolepFillConsoleOutput :: #run CONSOLE_FIRST_API_NUMBER(2);
    ConsolepGenerateCtrlEvent;
    ConsolepSetActiveScreenBuffer;
    ConsolepFlushInputBuffer;
    ConsolepSetCP;
    ConsolepGetCursorInfo;
    ConsolepSetCursorInfo;
    ConsolepGetScreenBufferInfo;
    ConsolepSetScreenBufferInfo;
    ConsolepSetScreenBufferSize;
    ConsolepSetCursorPosition;
    ConsolepGetLargestWindowSize;
    ConsolepScrollScreenBuffer;
    ConsolepSetTextAttribute;
    ConsolepSetWindowInfo;
    ConsolepReadConsoleOutputString;
    ConsolepWriteConsoleInput;
    ConsolepWriteConsoleOutput;
    ConsolepWriteConsoleOutputString;
    ConsolepReadConsoleOutput;
    ConsolepGetTitle;
    ConsolepSetTitle;
}

CONSOLE_MSG_BODY_L2 :: union
{
    GenerateConsoleCtrlEvent: CONSOLE_CTRLEVENT_MSG;
    FillConsoleOutput: CONSOLE_FILLCONSOLEOUTPUT_MSG;
    SetConsoleCP: CONSOLE_SETCP_MSG;
    GetConsoleCursorInfo: CONSOLE_GETCURSORINFO_MSG;
    SetConsoleCursorInfo: CONSOLE_SETCURSORINFO_MSG;
    GetConsoleScreenBufferInfo: CONSOLE_SCREENBUFFERINFO_MSG;
    SetConsoleScreenBufferInfo: CONSOLE_SCREENBUFFERINFO_MSG;
    SetConsoleScreenBufferSize: CONSOLE_SETSCREENBUFFERSIZE_MSG;
    SetConsoleCursorPosition: CONSOLE_SETCURSORPOSITION_MSG;
    GetLargestConsoleWindowSize: CONSOLE_GETLARGESTWINDOWSIZE_MSG;
    ScrollConsoleScreenBuffer: CONSOLE_SCROLLSCREENBUFFER_MSG;
    SetConsoleTextAttribute: CONSOLE_SETTEXTATTRIBUTE_MSG;
    SetConsoleWindowInfo: CONSOLE_SETWINDOWINFO_MSG;
    ReadConsoleOutputString: CONSOLE_READCONSOLEOUTPUTSTRING_MSG;
    WriteConsoleInput: CONSOLE_WRITECONSOLEINPUT_MSG;
    WriteConsoleOutputString: CONSOLE_WRITECONSOLEOUTPUTSTRING_MSG;
    WriteConsoleOutput: CONSOLE_WRITECONSOLEOUTPUT_MSG;
    ReadConsoleOutput: CONSOLE_READCONSOLEOUTPUT_MSG;
    SetConsoleTitle: CONSOLE_SETTITLE_MSG;
    GetConsoleTitle: CONSOLE_GETTITLE_MSG;
}

// #ifndef __cplusplus
// typedef struct _CONSOLE_MSG_L2 {
//     CONSOLE_MSG_HEADER Header;
//     union {
//         CONSOLE_MSG_BODY_L2;
//     } u;
// } CONSOLE_MSG_L2, * PCONSOLE_MSG_L2;
// #else
// typedef struct _CONSOLE_MSG_L2 :
//     public CONSOLE_MSG_HEADER
// {
//     CONSOLE_MSG_BODY_L2 u;
// } CONSOLE_MSG_L2, * PCONSOLE_MSG_L2;
// #endif // __cplusplus
//
    // TODO Compare against terminal/src/server/ApiSorter.cpp
    // NOTE Seems to duplicate CONSOLE_API_NUMBER_L2 above
CONSOLE_L2_API_TYPE :: enum
{
    Api_FillConsoleOutput;
    Api_GenerateConsoleCtrlEvent;
    Api_SetConsoleActiveScreenBuffer;
    Api_FlushConsoleInputBuffer;
    Api_SetConsoleCP;
    Api_GetConsoleCursorInfo;
    Api_SetConsoleCursorInfo;
    Api_GetConsoleScreenBufferInfo;
    Api_SetConsoleScreenBufferInfo;
    Api_SetConsoleScreenBufferSize;
    Api_SetConsoleCursorPosition;
    Api_GetLargestConsoleWindowSize;
    Api_ScrollConsoleScreenBuffer;
    Api_SetConsoleTextAttribute;
    Api_SetConsoleWindowInfo;
    Api_ReadConsoleOutputString;
    Api_WriteConsoleInput;
    Api_WriteConsoleOutput;
    Api_WriteConsoleOutputString;
    Api_ReadConsoleOutput;
    Api_GetConsoleTitle;
    Api_SetConsoleTitle;
}



/*++

Copyright (c) 1985 - 1999, Microsoft Corporation

Module Name:

    conmsgl3.h

Abstract:

    This include file defines the message formats used to communicate
    between the client and server portions of the CONSOLE portion of the
    Windows subsystem.

Author:

    Therese Stowell (thereses) 10-Nov-1990

Revision History:

    Wedson Almeida Filho (wedsonaf) 23-May-2010
        Modified the messages for use with the console driver.

--*/

CONSOLE_GETNUMBEROFFONTS_MSG :: struct
{
    NumberOfFonts: ULONG;
}

CONSOLE_GETSELECTIONINFO_MSG :: struct
{
    SelectionInfo: CONSOLE_SELECTION_INFO;
}

CONSOLE_GETMOUSEINFO_MSG :: struct
{
    NumButtons: ULONG;
}

CONSOLE_GETFONTINFO_MSG :: struct
{
    MaximumWindow: BOOLEAN;
    NumFonts: ULONG;  // this value is valid even for error cases
}

CONSOLE_GETFONTSIZE_MSG :: struct
{
    FontIndex: ULONG;
    FontSize: COORD;
}

CONSOLE_CURRENTFONT_MSG :: struct
{
    MaximumWindow: BOOLEAN;
    FontIndex: ULONG;
    FontSize: COORD;
    FontFamily: ULONG;
    FontWeight: ULONG;
    FaceName: [LF_FACESIZE] WCHAR;
}

CONSOLE_SETFONT_MSG :: struct
{
    FontIndex: ULONG;
}

CONSOLE_SETICON_MSG :: struct
{
    hIcon: HICON;
}

CONSOLE_SETICON_MSG64 :: struct
{
    hIcon: PVOID64;
}

CONSOLE_ADDALIAS_MSG :: struct
{
    SourceLength: USHORT;
    TargetLength: USHORT;
    ExeLength: USHORT;
    Unicode: BOOLEAN;
}

CONSOLE_GETALIAS_MSG :: struct
{
    SourceLength: USHORT;
    TargetLength: USHORT;
    ExeLength: USHORT;
    Unicode: BOOLEAN;
}

CONSOLE_GETALIASESLENGTH_MSG :: struct
{
    AliasesLength: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_GETALIASEXESLENGTH_MSG :: struct
{
    AliasExesLength: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_GETALIASES_MSG :: struct
{
    Unicode: BOOLEAN;
    AliasesBufferLength: ULONG;
}

CONSOLE_GETALIASEXES_MSG :: struct
{
    AliasExesBufferLength: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_EXPUNGECOMMANDHISTORY_MSG :: struct
{
    Unicode: BOOLEAN;
}

CONSOLE_SETNUMBEROFCOMMANDS_MSG :: struct
{
    NumCommands: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_GETCOMMANDHISTORYLENGTH_MSG :: struct
{
    CommandHistoryLength: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_GETCOMMANDHISTORY_MSG :: struct
{
    CommandBufferLength: ULONG;
    Unicode: BOOLEAN;
}

CONSOLE_INVALIDATERECT_MSG :: struct
{
    Rect: SMALL_RECT;
}

CONSOLE_VDM_MSG :: struct
{
    iFunction: ULONG;
    Bool: BOOLEAN;
    Point: POINT;
    Rect: RECT;
}

CONSOLE_SETCURSOR_MSG :: struct
{
    CursorHandle: HCURSOR;
}

CONSOLE_SETCURSOR_MSG64 :: struct
{
    CursorHandle: PVOID64;
}

CONSOLE_SHOWCURSOR_MSG :: struct
{
    bShow: BOOLEAN;
    DisplayCount: ULONG;
}

CONSOLE_MENUCONTROL_MSG :: struct
{
    CommandIdLow: ULONG;
    CommandIdHigh: ULONG;
    hMenu: HMENU;
}

CONSOLE_MENUCONTROL_MSG64 :: struct
{
    CommandIdLow: ULONG;
    CommandIdHigh: ULONG;
    hMenu: PVOID64;
}

CONSOLE_SETPALETTE_MSG :: struct
{
    hPalette: HPALETTE;
    dwUsage: ULONG;
}

CONSOLE_SETPALETTE_MSG64 :: struct
{
    hPalette: PVOID64;
    dwUsage: ULONG;
}

CONSOLE_SETDISPLAYMODE_MSG :: struct
{
    dwFlags: ULONG;
    ScreenBufferDimensions: COORD;
}

CONSOLE_REGISTERVDM_MSG :: struct
{
    RegisterFlags: ULONG;
    StartEvent: HANDLE;
    EndEvent: HANDLE;
    ErrorEvent: HANDLE;
    StateLength: ULONG;
    StateBuffer: PVOID;
    VDMBuffer: PVOID;
}

CONSOLE_REGISTERVDM_MSG64 :: struct
{
    RegisterFlags: ULONG;
    StartEvent: PVOID64;
    EndEvent: PVOID64;
    ErrorEvent: PVOID64;
    StateLength: ULONG;
    StateBuffer: PVOID64;
    VDMBuffer: PVOID64;
}

CONSOLE_GETHARDWARESTATE_MSG :: struct
{
    Resolution: COORD;
    FontSize: COORD;
}

CONSOLE_SETHARDWARESTATE_MSG :: struct
{
    Resolution: COORD;
    FontSize: COORD;
}

CONSOLE_GETDISPLAYMODE_MSG :: struct
{
    ModeFlags: ULONG;
}

CONSOLE_GETKEYBOARDLAYOUTNAME_MSG :: struct
{
    union {
        awchLayout: [9] WCHAR;
        achLayout: [9] u8;
    };
    bAnsi: BOOLEAN;
}

CONSOLE_SETKEYSHORTCUTS_MSG :: struct
{
    Set: BOOLEAN;
    ReserveKeys: BYTE;
}

CONSOLE_SETMENUCLOSE_MSG :: struct
{
    Enable: BOOLEAN;
}

CONSOLE_CHAR_TYPE_MSG :: struct
{
    coordCheck: COORD;
    dwType: ULONG;
}

CONSOLE_LOCAL_EUDC_MSG :: struct
{
    CodePoint: USHORT;
    FontSize: COORD;
}

CONSOLE_CURSOR_MODE_MSG :: struct
{
    Blink: BOOLEAN;
    DBEnable: BOOLEAN;
}

CONSOLE_REGISTEROS2_MSG :: struct
{
    fOs2Register: BOOLEAN;
}

CONSOLE_SETOS2OEMFORMAT_MSG :: struct
{
    fOs2OemFormat: BOOLEAN;
}

CONSOLE_NLS_MODE_MSG :: struct
{
    Ready: BOOLEAN;
    NlsMode: ULONG;
}

CONSOLE_GETCONSOLEWINDOW_MSG :: struct
{
    hwnd: HWND;
}

CONSOLE_GETCONSOLEWINDOW_MSG64 :: struct
{
    hwnd: PVOID64;
}

CONSOLE_GETCONSOLEPROCESSLIST_MSG :: struct
{
    dwProcessCount: ULONG;
}

CONSOLE_HISTORY_MSG :: struct
{
    HistoryBufferSize: ULONG;
    NumberOfHistoryBuffers: ULONG;
    dwFlags: ULONG;
}

CONSOLE_API_NUMBER_L3 :: enum
{
    ConsolepGetNumberOfFonts :: #run CONSOLE_FIRST_API_NUMBER(3);
    ConsolepGetMouseInfo;
    ConsolepGetFontInfo;
    ConsolepGetFontSize;
    ConsolepGetCurrentFont;
    ConsolepSetFont;
    ConsolepSetIcon;
    ConsolepInvalidateBitmapRect;
    ConsolepVDMOperation;
    ConsolepSetCursor;
    ConsolepShowCursor;
    ConsolepMenuControl;
    ConsolepSetPalette;
    ConsolepSetDisplayMode;
    ConsolepRegisterVDM;
    ConsolepGetHardwareState;
    ConsolepSetHardwareState;
    ConsolepGetDisplayMode;
    ConsolepAddAlias;
    ConsolepGetAlias;
    ConsolepGetAliasesLength;
    ConsolepGetAliasExesLength;
    ConsolepGetAliases;
    ConsolepGetAliasExes;
    ConsolepExpungeCommandHistory;
    ConsolepSetNumberOfCommands;
    ConsolepGetCommandHistoryLength;
    ConsolepGetCommandHistory;
    ConsolepSetKeyShortcuts;
    ConsolepSetMenuClose;
    ConsolepGetKeyboardLayoutName;
    ConsolepGetConsoleWindow;
    ConsolepCharType;
    ConsolepSetLocalEUDC;
    ConsolepSetCursorMode;
    ConsolepGetCursorMode;
    ConsolepRegisterOS2;
    ConsolepSetOS2OemFormat;
    ConsolepGetNlsMode;
    ConsolepSetNlsMode;
    ConsolepGetSelectionInfo;
    ConsolepGetConsoleProcessList;
    ConsolepGetHistory;
    ConsolepSetHistory;
    ConsolepSetCurrentFont;
}

CONSOLE_MSG_BODY_L3 :: union
{
    GetNumberOfConsoleFonts: CONSOLE_GETNUMBEROFFONTS_MSG;
    GetConsoleMouseInfo: CONSOLE_GETMOUSEINFO_MSG;
    GetConsoleFontInfo: CONSOLE_GETFONTINFO_MSG;
    GetConsoleFontSize: CONSOLE_GETFONTSIZE_MSG;
    GetCurrentConsoleFont: CONSOLE_CURRENTFONT_MSG;
    SetConsoleFont: CONSOLE_SETFONT_MSG;
    InvalidateConsoleBitmapRect: CONSOLE_INVALIDATERECT_MSG;
    VDMConsoleOperation: CONSOLE_VDM_MSG;
    ShowConsoleCursor: CONSOLE_SHOWCURSOR_MSG;
    SetConsoleDisplayMode: CONSOLE_SETDISPLAYMODE_MSG;
#if 0 // defined(BUILD_WOW6432)
{
    RegisterConsoleVDM: CONSOLE_REGISTERVDM_MSG64;
    SetConsoleCursor: CONSOLE_SETCURSOR_MSG64;
    SetConsoleIcon: CONSOLE_SETICON_MSG64;
    ConsoleMenuControl: CONSOLE_MENUCONTROL_MSG64;
    SetConsolePalette: CONSOLE_SETPALETTE_MSG64;
    GetConsoleWindow: CONSOLE_GETCONSOLEWINDOW_MSG64;
}
else
{
    RegisterConsoleVDM: CONSOLE_REGISTERVDM_MSG;
    SetConsoleCursor: CONSOLE_SETCURSOR_MSG;
    SetConsoleIcon: CONSOLE_SETICON_MSG;
    ConsoleMenuControl: CONSOLE_MENUCONTROL_MSG;
    SetConsolePalette: CONSOLE_SETPALETTE_MSG;
    GetConsoleWindow: CONSOLE_GETCONSOLEWINDOW_MSG;
}
    GetConsoleHardwareState: CONSOLE_GETHARDWARESTATE_MSG;
    SetConsoleHardwareState: CONSOLE_SETHARDWARESTATE_MSG;
    GetConsoleDisplayMode: CONSOLE_GETDISPLAYMODE_MSG;
    AddConsoleAliasW: CONSOLE_ADDALIAS_MSG;
    GetConsoleAliasW: CONSOLE_GETALIAS_MSG;
    GetConsoleAliasesLengthW: CONSOLE_GETALIASESLENGTH_MSG;
    GetConsoleAliasExesLengthW: CONSOLE_GETALIASEXESLENGTH_MSG;
    GetConsoleAliasesW: CONSOLE_GETALIASES_MSG;
    GetConsoleAliasExesW: CONSOLE_GETALIASEXES_MSG;
    ExpungeConsoleCommandHistoryW: CONSOLE_EXPUNGECOMMANDHISTORY_MSG;
    SetConsoleNumberOfCommandsW: CONSOLE_SETNUMBEROFCOMMANDS_MSG;
    GetConsoleCommandHistoryLengthW: CONSOLE_GETCOMMANDHISTORYLENGTH_MSG;
    GetConsoleCommandHistoryW: CONSOLE_GETCOMMANDHISTORY_MSG;
    SetConsoleKeyShortcuts: CONSOLE_SETKEYSHORTCUTS_MSG;
    SetConsoleMenuClose: CONSOLE_SETMENUCLOSE_MSG;
    GetKeyboardLayoutName: CONSOLE_GETKEYBOARDLAYOUTNAME_MSG;
    GetConsoleCharType: CONSOLE_CHAR_TYPE_MSG;
    SetConsoleLocalEUDC: CONSOLE_LOCAL_EUDC_MSG;
    SetConsoleCursorMode: CONSOLE_CURSOR_MODE_MSG;
    GetConsoleCursorMode: CONSOLE_CURSOR_MODE_MSG;
    RegisterConsoleOS2: CONSOLE_REGISTEROS2_MSG;
    SetConsoleOS2OemFormat: CONSOLE_SETOS2OEMFORMAT_MSG;
    GetConsoleNlsMode: CONSOLE_NLS_MODE_MSG;
    SetConsoleNlsMode: CONSOLE_NLS_MODE_MSG;
    GetConsoleSelectionInfo: CONSOLE_GETSELECTIONINFO_MSG;
    GetConsoleProcessList: CONSOLE_GETCONSOLEPROCESSLIST_MSG;
    SetCurrentConsoleFont: CONSOLE_CURRENTFONT_MSG;
    SetConsoleHistory: CONSOLE_HISTORY_MSG;
    GetConsoleHistory: CONSOLE_HISTORY_MSG;
}

// #ifndef __cplusplus
// typedef struct _CONSOLE_MSG_L3 {
//     CONSOLE_MSG_HEADER Header;
//     union {
//         CONSOLE_MSG_BODY_L3;
//     } u;
// } CONSOLE_MSG_L3, * PCONSOLE_MSG_L3;
// #else
// typedef struct _CONSOLE_MSG_L3 :
//     public CONSOLE_MSG_HEADER
// {
//     CONSOLE_MSG_BODY_L3 u;
// } CONSOLE_MSG_L3, * PCONSOLE_MSG_L3;
// #endif  // __cplusplus
//
    // TODO Compare against terminal/src/server/ApiSorter.cpp
    // NOTE Duplicates CONSOLE_API_NUMBER_L3 above
CONSOLE_L3_API_TYPE :: enum
{
    Api_GetNumberOfFonts;
    Api_GetNumberOfConsoleMouseButtons;
    Api_GetFontInfo;
    Api_GetConsoleFontSize;
    Api_GetCurrentConsoleFont;
    Api_SetFont;
    Api_SetIcon;
    Api_InvalidateRect;
    Api_VDM;
    Api_SetCursor;
    Api_ShowCursor;
    Api_MenuControl;
    Api_SetPalette;
    Api_SetConsoleDisplayMode;
    Api_RegisterVDM;
    Api_GetHardwareState;
    Api_SetHardwareState;
    Api_GetConsoleDisplayMode;
    Api_AddConsoleAlias;
    Api_GetConsoleAlias;
    Api_GetConsoleAliasesLength;
    Api_GetConsoleAliasExesLength;
    Api_GetConsoleAliases;
    Api_GetConsoleAliasExes;
    Api_ExpungeConsoleCommandHistory;
    Api_SetConsoleNumberOfCommands;
    Api_GetConsoleCommandHistoryLength;
    Api_GetConsoleCommandHistory;
    Api_SetKeyShortcuts;
    Api_MenuClose;
    Api_GetKeyboardLayoutName;
    Api_GetConsoleWindow;
    Api_CharType;
    Api_LocalEudc;
    Api_CursorMode;
    Api_CursorMode2;
    Api_RegisterOS2;
    Api_SetOS2OEMFormat;
    Api_NlsMode;
    Api_NlsMode2;
    Api_GetConsoleSelectionInfo;
    Api_GetConsoleProcessList;
    Api_GetConsoleHistory;
    Api_SetConsoleHistory;
    Api_SetConsoleCurrentFont;
}



/*++
Copyright (c) Microsoft Corporation
Licensed under the MIT license.

Module Name:
- conwinuserrefs.h

Abstract:
- Contains private definitions from WinUserK.h that we'll need to publish.
--*/

/* WinUserK */
/*
* Console window startup optimization.
*/

// TODO Seems to be exactly the same as handterm's ControlType below, however with some "reserved" stuff
CONSOLECONTROL :: enum
{
    Reserved1;
    ConsoleNotifyConsoleApplication;
    Reserved2;
    ConsoleSetCaretInfo;
    Reserved3;
    ConsoleSetForeground;
    ConsoleSetWindowOwner;
    ConsoleEndTask;
}

// //
// // CtrlFlags definitions
// //
// #define CONSOLE_CTRL_C_FLAG 0x00000001
// #define CONSOLE_CTRL_BREAK_FLAG 0x00000002
// #define CONSOLE_CTRL_CLOSE_FLAG 0x00000004
//
// #define CONSOLE_CTRL_LOGOFF_FLAG 0x00000010
// #define CONSOLE_CTRL_SHUTDOWN_FLAG 0x00000020
//
// typedef struct _CONSOLEENDTASK
// {
//     HANDLE ProcessId;
//     HWND hwnd;
//     ULONG ConsoleEventCode;
//     ULONG ConsoleFlags;
// } CONSOLEENDTASK, *PCONSOLEENDTASK;
//
// typedef struct _CONSOLEWINDOWOWNER
// {
//     HWND hwnd;
//     ULONG ProcessId;
//     ULONG ThreadId;
// } CONSOLEWINDOWOWNER, *PCONSOLEWINDOWOWNER;
//
// typedef struct _CONSOLESETFOREGROUND
// {
//     HANDLE hProcess;
//     BOOL bForeground;
// } CONSOLESETFOREGROUND, *PCONSOLESETFOREGROUND;

/*
* Console window startup optimization.
*/
CPI_NEWPROCESSWINDOW :: 0x0001;

CONSOLE_PROCESS_INFO :: struct
{
    dwProcessID: DWORD;
    dwFlags: DWORD;
}

// typedef struct _CONSOLE_CARET_INFO
// {
//     HWND hwnd;
//     RECT rc;
// } CONSOLE_CARET_INFO, *PCONSOLE_CARET_INFO;

// NOTE Moved to CmdHostedShell
// ConsoleControl :: ( Command: CONSOLECONTROL, Information: PVOID, Length: DWORD ) -> NTSTATUS #foreign user32;


//// Misc

// // NOTE As declared by handterm
// typedef enum ControlType
// {
//     ConsoleSetVDMCursorBounds,
//     ConsoleNotifyConsoleApplication,
//     ConsoleFullscreenSwitch,
//     ConsoleSetCaretInfo,
//     ConsoleSetReserveKeys,
//     ConsoleSetForeground,
//     ConsoleSetWindowOwner,
//     ConsoleEndTask,
// } ControlType;

PROC_THREAD_ATTRIBUTE_HANDLE_LIST :: #run ProcThreadAttributeValue( 2, .FALSE, .TRUE, .FALSE );
PROC_THREAD_ATTRIBUTE_CONSOLE_REFERENCE :: #run ProcThreadAttributeValue( 10, .FALSE, .TRUE, .FALSE );

ProcThreadAttributeValue :: ( Number: DWORD, Thread: BOOL, Input: BOOL, Additive: BOOL ) -> DWORD_PTR #expand
{
    return cast(DWORD_PTR) ((Number & PROC_THREAD_ATTRIBUTE_NUMBER) |
        (ifx Thread   then PROC_THREAD_ATTRIBUTE_THREAD   else 0) |
        (ifx Input    then PROC_THREAD_ATTRIBUTE_INPUT    else 0) |
        (ifx Additive then PROC_THREAD_ATTRIBUTE_ADDITIVE else 0));
}

PROC_THREAD_ATTRIBUTE_NUMBER   :: 0x0000ffff;
PROC_THREAD_ATTRIBUTE_THREAD   :: 0x00010000;
PROC_THREAD_ATTRIBUTE_INPUT    :: 0x00020000;
PROC_THREAD_ATTRIBUTE_ADDITIVE :: 0x00040000;

CONSOLE_API_MSG :: struct
{
    Descriptor: CD_IO_DESCRIPTOR;
    union
    {
        struct
        {
            CreateObject: CD_CREATE_OBJECT_INFORMATION;
            CreateScreenBuffer: CONSOLE_CREATESCREENBUFFER_MSG;
        }
        struct
        {
            msgHeader: CONSOLE_MSG_HEADER;
            u: union
            {
                consoleMsgL1: CONSOLE_MSG_BODY_L1;
                consoleMsgL2: CONSOLE_MSG_BODY_L2;
                consoleMsgL3: CONSOLE_MSG_BODY_L3;
            }
        }
    }
}

// #define FG_ATTRS (FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY)
// #define BG_ATTRS (BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY)
// #define META_ATTRS (COMMON_LVB_LEADING_BYTE | COMMON_LVB_TRAILING_BYTE | COMMON_LVB_GRID_HORIZONTAL | COMMON_LVB_GRID_LVERTICAL | COMMON_LVB_GRID_RVERTICAL | COMMON_LVB_REVERSE_VIDEO | COMMON_LVB_UNDERSCORE)
//
// #define CONSOLE_READ_NOREMOVE   0x0001
// #define CONSOLE_READ_NOWAIT     0x0002
//
// // Used by TranslateMessageEx to purposefully return false to certain WM_KEYDOWN/WM_CHAR messages
// // TODO See usage and note in terminal/src/interactivity/win32/windowio.cpp
// #define TM_POSTCHARBREAKS 0x0002
//

//
// Define the various device type values.  Note that values used by Microsoft
// Corporation are in the range 0-32767, and 32768-65535 are reserved for use
// by customers.
//
FILE_DEVICE_CONSOLE :: 0x00000050;

//
// Macro definition for defining IOCTL and FSCTL function control codes.  Note
// that function codes 0-2047 are reserved for Microsoft Corporation, and
// 2048-4095 are reserved for customers.
//
CTL_CODE :: ( DeviceType: DWORD, Function: DWORD, Method: DWORD, Access: DWORD ) -> DWORD #expand
{
    return cast(DWORD) ((DeviceType << 16) | (Access << 14) | (Function << 2) | Method);
}

//
// Define the method codes for how buffers are passed for I/O and FS controls
//
METHOD_BUFFERED   :: 0;
METHOD_IN_DIRECT  :: 1;
METHOD_OUT_DIRECT :: 2;
METHOD_NEITHER    :: 3;


FILE_ANY_ACCESS :: 0;

CONSOLE_SELECTION_INFO :: struct
{
    dwFlags: DWORD;
    dwSelectionAnchor: COORD;
    srSelection: SMALL_RECT;
}

CHAR_INFO :: struct
{
    Char: union
    {
        UnicodeChar: WCHAR;
        AsciiChar: UCHAR;
    }
    Attributes: WORD;
}

LF_FACESIZE :: 32;

// NTSTATUS values
STATUS_SUCCESS                :: 0x0;
STATUS_TIMEOUT                :: 0x00000102;
STATUS_UNSUCCESSFUL           :: 0xC0000001;
STATUS_BUFFER_TOO_SMALL       :: 0xC0000023;
STATUS_SHARING_VIOLATION      :: 0xC0000043;
STATUS_INSUFFICIENT_RESOURCES :: 0xC000009A;
STATUS_ILLEGAL_FUNCTION       :: 0xC00000AF;
STATUS_PIPE_DISCONNECTED      :: 0xC00000B0;
STATUS_NOT_SUPPORTED          :: 0xC00000BB;
STATUS_NOT_FOUND              :: 0xC0000225;

/*
* Input mode flags
*/
ENABLE_PROCESSED_INPUT          :: 0x0001;
ENABLE_LINE_INPUT               :: 0x0002;
ENABLE_ECHO_INPUT               :: 0x0004;
ENABLE_WINDOW_INPUT             :: 0x0008;
ENABLE_MOUSE_INPUT              :: 0x0010;
ENABLE_INSERT_MODE              :: 0x0020;
ENABLE_QUICK_EDIT_MODE          :: 0x0040;
ENABLE_EXTENDED_FLAGS           :: 0x0080;
ENABLE_AUTO_POSITION            :: 0x0100;
ENABLE_VIRTUAL_TERMINAL_INPUT   :: 0x0200;
 
/*
 * Output mode flags
*/
ENABLE_PROCESSED_OUTPUT             :: 0x0001;
ENABLE_WRAP_AT_EOL_OUTPUT           :: 0x0002;
// ENABLE_VIRTUAL_TERMINAL_PROCESSING  :: 0x0004; // Already declared in Windows.jai
DISABLE_NEWLINE_AUTO_RETURN         :: 0x0008;
ENABLE_LVB_GRID_WORLDWIDE           :: 0x0010;
 
// These are required for wait routines to accurately identify which function is waited on and needs to be dispatched later.
// It's stored here so it can be easily aligned with the layer descriptions below.
// 0x01 stands for level 1 API (layers are 1-based)
// 0x000004 stands for the 5th one down in the layer structure (call IDs are 0-based)
API_NUMBER_GETCONSOLEINPUT :: 0x01000004;
API_NUMBER_READCONSOLE     :: 0x01000005;
API_NUMBER_WRITECONSOLE    :: 0x01000006;


// TODO https://doxygen.reactos.org/d8/d14/wincon_8h_source.html
// TODO https://doxygen.reactos.org/d1/d58/wincontypes_8h_source.html

