
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

#pragma once


#define FILE_SYNCHRONOUS_IO_NONALERT            0x00000020

//
// Messages that can be received by servers, used in CD_IO_DESCRIPTOR::Function.
//

#define CONSOLE_IO_CONNECT        0x01
#define CONSOLE_IO_DISCONNECT     0x02
#define CONSOLE_IO_CREATE_OBJECT  0x03
#define CONSOLE_IO_CLOSE_OBJECT   0x04
#define CONSOLE_IO_RAW_WRITE      0x05
#define CONSOLE_IO_RAW_READ       0x06
#define CONSOLE_IO_USER_DEFINED   0x07
#define CONSOLE_IO_RAW_FLUSH      0x08

//
// Header of all IOs submitted to a server.
//

typedef struct _CD_IO_DESCRIPTOR {
    LUID Identifier;
    ULONG_PTR Process;
    ULONG_PTR Object;
    ULONG Function;
    ULONG InputSize;
    ULONG OutputSize;
    ULONG Reserved;
} CD_IO_DESCRIPTOR, *PCD_IO_DESCRIPTOR;

//
// Types of objects, used in CREATE_OBJECT_INFORMATION::ObjectType.
//

#define CD_IO_OBJECT_TYPE_CURRENT_INPUT   0x01
#define CD_IO_OBJECT_TYPE_CURRENT_OUTPUT  0x02
#define CD_IO_OBJECT_TYPE_NEW_OUTPUT      0x03
#define CD_IO_OBJECT_TYPE_GENERIC         0x04

//
// Payload of the CONSOLE_IO_CREATE_OBJECT io.
//

typedef struct _CD_CREATE_OBJECT_INFORMATION {
    ULONG ObjectType;
    ULONG ShareMode;
    ACCESS_MASK DesiredAccess;
} CD_CREATE_OBJECT_INFORMATION, *PCD_CREATE_OBJECT_INFORMATION;

//
// Create EA buffers.
//

#define CD_BROKER_EA_NAME "broker"
#define CD_SERVER_EA_NAME "server"
#define CD_ATTACH_EA_NAME "attach"

typedef struct _CD_CREATE_SERVER {
    HANDLE BrokerHandle;
    LUID BrokerRequest;
} CD_CREATE_SERVER, *PCD_CREATE_SERVER;

typedef struct _CD_ATTACH_INFORMATION {
    HANDLE ProcessId;
} CD_ATTACH_INFORMATION, *PCD_ATTACH_INFORMATION;

typedef struct _CD_ATTACH_INFORMATION64 {
    PVOID64 ProcessId;
} CD_ATTACH_INFORMATION64, *PCD_ATTACH_INFORMATION64;

//
// Information passed to the driver by a server when a connection is accepted.
//

typedef struct _CD_CONNECTION_INFORMATION {
    ULONG_PTR Process;
    ULONG_PTR Input;
    ULONG_PTR Output;
} CD_CONNECTION_INFORMATION, *PCD_CONNECTION_INFORMATION;

//
// Ioctls.
//

typedef struct _CD_IO_BUFFER {
    ULONG Size;
    PVOID Buffer;
} CD_IO_BUFFER, *PCD_IO_BUFFER;

typedef struct _CD_IO_BUFFER64 {
    ULONG Size;
    PVOID64 Buffer;
} CD_IO_BUFFER64, *PCD_IO_BUFFER64;

typedef struct _CD_USER_DEFINED_IO {
    HANDLE Client;
    ULONG InputCount;
    ULONG OutputCount;
    CD_IO_BUFFER Buffers[ANYSIZE_ARRAY];
} CD_USER_DEFINED_IO, *PCD_USER_DEFINED_IO;

typedef struct _CD_USER_DEFINED_IO64 {
    PVOID64 Client;
    ULONG InputCount;
    ULONG OutputCount;
    CD_IO_BUFFER64 Buffers[ANYSIZE_ARRAY];
} CD_USER_DEFINED_IO64, *PCD_USER_DEFINED_IO64;

typedef struct _CD_IO_BUFFER_DESCRIPTOR {
    PVOID Data;
    ULONG Size;
    ULONG Offset;
} CD_IO_BUFFER_DESCRIPTOR, *PCD_IO_BUFFER_DESCRIPTOR;

typedef struct _CD_IO_COMPLETE {
    LUID Identifier;
    IO_STATUS_BLOCK IoStatus;
    CD_IO_BUFFER_DESCRIPTOR Write;
} CD_IO_COMPLETE, *PCD_IO_COMPLETE;

typedef struct _CD_IO_OPERATION {
    LUID Identifier;
    CD_IO_BUFFER_DESCRIPTOR Buffer;
} CD_IO_OPERATION, *PCD_IO_OPERATION;

typedef struct _CD_IO_SERVER_INFORMATION {
    HANDLE InputAvailableEvent;
} CD_IO_SERVER_INFORMATION, *PCD_IO_SERVER_INFORMATION;

typedef struct _CD_IO_DISPLAY_SIZE {
    ULONG Width;
    ULONG Height;
} CD_IO_DISPLAY_SIZE, *PCD_IO_DISPLAY_SIZE;

typedef struct _CD_IO_CHARACTER {
    WCHAR Character;
    USHORT Attribute;
} CD_IO_CHARACTER, *PCD_IO_CHARACTER;

typedef struct _CD_IO_ROW_INFORMATION {
    SHORT Index;
    PCD_IO_CHARACTER Old;
    PCD_IO_CHARACTER New;
} CD_IO_ROW_INFORMATION, *PCD_IO_ROW_INFORMATION;

typedef struct _CD_IO_CURSOR_INFORMATION {
    USHORT Column;
    USHORT Row;
    ULONG Height;
    BOOLEAN IsVisible;
} CD_IO_CURSOR_INFORMATION, *PCD_IO_CURSOR_INFORMATION;

typedef struct _CD_IO_FONT_SIZE {
    ULONG Width;
    ULONG Height;
} CD_IO_FONT_SIZE, *PCD_IO_FONT_SIZE;

#define IOCTL_CONDRV_READ_IO \
    CTL_CODE(FILE_DEVICE_CONSOLE, 1, METHOD_OUT_DIRECT, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_COMPLETE_IO \
    CTL_CODE(FILE_DEVICE_CONSOLE, 2, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_READ_INPUT \
    CTL_CODE(FILE_DEVICE_CONSOLE, 3, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_WRITE_OUTPUT \
    CTL_CODE(FILE_DEVICE_CONSOLE, 4, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_ISSUE_USER_IO \
    CTL_CODE(FILE_DEVICE_CONSOLE, 5, METHOD_OUT_DIRECT, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_DISCONNECT_PIPE \
    CTL_CODE(FILE_DEVICE_CONSOLE, 6, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_SET_SERVER_INFORMATION \
    CTL_CODE(FILE_DEVICE_CONSOLE, 7, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_GET_SERVER_PID \
    CTL_CODE(FILE_DEVICE_CONSOLE, 8, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_GET_DISPLAY_SIZE \
    CTL_CODE(FILE_DEVICE_CONSOLE, 9, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_UPDATE_DISPLAY \
    CTL_CODE(FILE_DEVICE_CONSOLE, 10, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_SET_CURSOR \
    CTL_CODE(FILE_DEVICE_CONSOLE, 11, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_ALLOW_VIA_UIACCESS \
    CTL_CODE(FILE_DEVICE_CONSOLE, 12, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_LAUNCH_SERVER \
    CTL_CODE(FILE_DEVICE_CONSOLE, 13, METHOD_NEITHER, FILE_ANY_ACCESS)

#define IOCTL_CONDRV_GET_FONT_SIZE \
    CTL_CODE(FILE_DEVICE_CONSOLE, 14, METHOD_NEITHER, FILE_ANY_ACCESS)



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

#pragma once

#define CONSOLE_FIRST_API_NUMBER(Layer) \
    (Layer << 24) \

typedef struct _CONSOLE_SERVER_MSG {
    ULONG IconId;
    ULONG HotKey;
    ULONG StartupFlags;
    USHORT FillAttribute;
    USHORT ShowWindow;
    COORD ScreenBufferSize;
    COORD WindowSize;
    COORD WindowOrigin;
    ULONG ProcessGroupId;
    BOOLEAN ConsoleApp;
    BOOLEAN WindowVisible;
    USHORT TitleLength;
    WCHAR Title[MAX_PATH + 1];
    USHORT ApplicationNameLength;
    WCHAR ApplicationName[128];
    USHORT CurrentDirectoryLength;
    WCHAR CurrentDirectory[MAX_PATH + 1];
} CONSOLE_SERVER_MSG, * PCONSOLE_SERVER_MSG;

typedef struct _CONSOLE_BROKER_DATA {
    WCHAR DesktopName[MAX_PATH];
} CONSOLE_BROKER_MSG, * PCONSOLE_BROKER_MSG;

typedef struct _CONSOLE_GETCP_MSG {
    OUT ULONG CodePage;
    IN BOOLEAN Output;
} CONSOLE_GETCP_MSG, * PCONSOLE_GETCP_MSG;

typedef struct _CONSOLE_MODE_MSG {
    IN OUT ULONG Mode;
} CONSOLE_MODE_MSG, * PCONSOLE_MODE_MSG;

typedef struct _CONSOLE_GETNUMBEROFINPUTEVENTS_MSG {
    OUT ULONG ReadyEvents;
} CONSOLE_GETNUMBEROFINPUTEVENTS_MSG, * PCONSOLE_GETNUMBEROFINPUTEVENTS_MSG;

typedef struct _CONSOLE_GETCONSOLEINPUT_MSG {
    OUT ULONG NumRecords;
    IN USHORT Flags;
    IN BOOLEAN Unicode;
} CONSOLE_GETCONSOLEINPUT_MSG, * PCONSOLE_GETCONSOLEINPUT_MSG;

typedef struct _CONSOLE_READCONSOLE_MSG {
    IN BOOLEAN Unicode;
    IN BOOLEAN ProcessControlZ;
    IN USHORT ExeNameLength;
    IN ULONG InitialNumBytes;
    IN ULONG CtrlWakeupMask;
    OUT ULONG ControlKeyState;
    OUT ULONG NumBytes;
} CONSOLE_READCONSOLE_MSG, * PCONSOLE_READCONSOLE_MSG;

typedef struct _CONSOLE_WRITECONSOLE_MSG {
    OUT ULONG NumBytes;
    IN BOOLEAN Unicode;
} CONSOLE_WRITECONSOLE_MSG, * PCONSOLE_WRITECONSOLE_MSG;

typedef struct _CONSOLE_LANGID_MSG {
    OUT LANGID LangId;
} CONSOLE_LANGID_MSG, * PCONSOLE_LANGID_MSG;

typedef struct _CONSOLE_MAPBITMAP_MSG {
    OUT HANDLE Mutex;
    OUT PVOID Bitmap;
} CONSOLE_MAPBITMAP_MSG, * PCONSOLE_MAPBITMAP_MSG;

typedef struct _CONSOLE_MAPBITMAP_MSG64 {
    OUT PVOID64 Mutex;
    OUT PVOID64 Bitmap;
} CONSOLE_MAPBITMAP_MSG64, * PCONSOLE_MAPBITMAP_MSG64;

typedef enum _CONSOLE_API_NUMBER_L1 {
    ConsolepGetCP = CONSOLE_FIRST_API_NUMBER(1),
    ConsolepGetMode,
    ConsolepSetMode,
    ConsolepGetNumberOfInputEvents,
    ConsolepGetConsoleInput,
    ConsolepReadConsole,
    ConsolepWriteConsole,
    ConsolepNotifyLastClose,
    ConsolepGetLangId,
    ConsolepMapBitmap,
} CONSOLE_API_NUMBER_L1, * PCONSOLE_API_NUMBER_L1;

typedef struct _CONSOLE_MSG_HEADER {
    ULONG ApiNumber;
    ULONG ApiDescriptorSize;
} CONSOLE_MSG_HEADER, * PCONSOLE_MSG_HEADER;

typedef union _CONSOLE_MSG_BODY_L1 {
    CONSOLE_GETCP_MSG GetConsoleCP;
    CONSOLE_MODE_MSG GetConsoleMode;
    CONSOLE_MODE_MSG SetConsoleMode;
    CONSOLE_GETNUMBEROFINPUTEVENTS_MSG GetNumberOfConsoleInputEvents;
    CONSOLE_GETCONSOLEINPUT_MSG GetConsoleInput;
    CONSOLE_READCONSOLE_MSG ReadConsole;
    CONSOLE_WRITECONSOLE_MSG WriteConsole;
    CONSOLE_LANGID_MSG GetConsoleLangId;

#if defined(BUILD_WOW6432) && !defined(BUILD_WOW3232)

    CONSOLE_MAPBITMAP_MSG64 MapBitmap;

#else 

    CONSOLE_MAPBITMAP_MSG MapBitmap;

#endif

} CONSOLE_MSG_BODY_L1, * PCONSOLE_MSG_BODY_L1;

#ifndef __cplusplus
typedef struct _CONSOLE_MSG_L1 {
    CONSOLE_MSG_HEADER Header;
    union {
        CONSOLE_MSG_BODY_L1;
    } u;
} CONSOLE_MSG_L1, * PCONSOLE_MSG_L1;
#else
typedef struct _CONSOLE_MSG_L1 :
    public CONSOLE_MSG_HEADER
{
    CONSOLE_MSG_BODY_L1 u;
} CONSOLE_MSG_L1, * PCONSOLE_MSG_L1;
#endif // __cplusplus

    // TODO Compare against terminal/src/server/ApiSorter.cpp
// typedef enum CONSOLE_L1_API_TYPE {
//     Api_GetConsoleCP,
//     Api_GetConsoleMode,
//     Api_SetConsoleMode,
//     Api_GetNumberOfCOnsoleInputEvents,
//     Api_GetConsoleInput,
//     Api_ReadConsole,
//     Api_WriteConsole,
//     Api_ServerConsoleNotifyLastChance,
//     Api_GetConsoleLangId,
//     Api_ConsoleMapBitmap
// } CONSOLE_L1_API_TYPE;



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

#pragma once

typedef struct _CONSOLE_CREATESCREENBUFFER_MSG {
    IN ULONG Flags;
    IN ULONG BitmapInfoLength;
    IN ULONG Usage;
} CONSOLE_CREATESCREENBUFFER_MSG, * PCONSOLE_CREATESCREENBUFFER_MSG;

#define CONSOLE_ASCII             0x1
#define CONSOLE_REAL_UNICODE      0x2
#define CONSOLE_ATTRIBUTE         0x3
#define CONSOLE_FALSE_UNICODE     0x4

typedef struct _CONSOLE_FILLCONSOLEOUTPUT_MSG {
    IN COORD WriteCoord;
    IN ULONG ElementType;
    IN USHORT Element;
    IN OUT ULONG Length;
} CONSOLE_FILLCONSOLEOUTPUT_MSG, * PCONSOLE_FILLCONSOLEOUTPUT_MSG;

typedef struct _CONSOLE_CTRLEVENT_MSG {
    IN ULONG CtrlEvent;
    IN ULONG ProcessGroupId;
} CONSOLE_CTRLEVENT_MSG, * PCONSOLE_CTRLEVENT_MSG;

typedef struct _CONSOLE_SETCP_MSG {
    IN ULONG CodePage;
    IN BOOLEAN Output;
} CONSOLE_SETCP_MSG, * PCONSOLE_SETCP_MSG;

typedef struct _CONSOLE_GETCURSORINFO_MSG {
    OUT ULONG CursorSize;
    OUT BOOLEAN Visible;
} CONSOLE_GETCURSORINFO_MSG, * PCONSOLE_GETCURSORINFO_MSG;

typedef struct _CONSOLE_SETCURSORINFO_MSG {
    IN ULONG CursorSize;
    IN BOOLEAN Visible;
} CONSOLE_SETCURSORINFO_MSG, * PCONSOLE_SETCURSORINFO_MSG;

typedef struct _CONSOLE_SCREENBUFFERINFO_MSG {
    IN OUT COORD Size;
    IN OUT COORD CursorPosition;
    IN OUT COORD ScrollPosition;
    IN OUT USHORT Attributes;
    IN OUT COORD CurrentWindowSize;
    IN OUT COORD MaximumWindowSize;
    IN OUT USHORT PopupAttributes;
    IN OUT BOOLEAN FullscreenSupported;
    IN OUT COLORREF ColorTable[16];
} CONSOLE_SCREENBUFFERINFO_MSG, * PCONSOLE_SCREENBUFFERINFO_MSG;

typedef struct _CONSOLE_SETSCREENBUFFERSIZE_MSG {
    IN COORD Size;
} CONSOLE_SETSCREENBUFFERSIZE_MSG, * PCONSOLE_SETSCREENBUFFERSIZE_MSG;

typedef struct _CONSOLE_SETCURSORPOSITION_MSG {
    IN COORD CursorPosition;
} CONSOLE_SETCURSORPOSITION_MSG, * PCONSOLE_SETCURSORPOSITION_MSG;

typedef struct _CONSOLE_GETLARGESTWINDOWSIZE_MSG {
    OUT COORD Size;
} CONSOLE_GETLARGESTWINDOWSIZE_MSG, * PCONSOLE_GETLARGESTWINDOWSIZE_MSG;

typedef struct _CONSOLE_SCROLLSCREENBUFFER_MSG {
    IN SMALL_RECT ScrollRectangle;
    IN SMALL_RECT ClipRectangle;
    IN BOOLEAN Clip;
    IN BOOLEAN Unicode;
    IN COORD DestinationOrigin;
    IN CHAR_INFO Fill;
} CONSOLE_SCROLLSCREENBUFFER_MSG, * PCONSOLE_SCROLLSCREENBUFFER_MSG;

typedef struct _CONSOLE_SETTEXTATTRIBUTE_MSG {
    IN USHORT Attributes;
} CONSOLE_SETTEXTATTRIBUTE_MSG, * PCONSOLE_SETTEXTATTRIBUTE_MSG;

typedef struct _CONSOLE_SETWINDOWINFO_MSG {
    IN BOOLEAN Absolute;
    IN SMALL_RECT Window;
} CONSOLE_SETWINDOWINFO_MSG, * PCONSOLE_SETWINDOWINFO_MSG;

typedef struct _CONSOLE_READCONSOLEOUTPUTSTRING_MSG {
    IN COORD ReadCoord;
    IN ULONG StringType;
    OUT ULONG NumRecords;
} CONSOLE_READCONSOLEOUTPUTSTRING_MSG, * PCONSOLE_READCONSOLEOUTPUTSTRING_MSG;

typedef struct _CONSOLE_WRITECONSOLEINPUT_MSG {
    OUT ULONG NumRecords;
    IN BOOLEAN Unicode;
    IN BOOLEAN Append;
} CONSOLE_WRITECONSOLEINPUT_MSG, * PCONSOLE_WRITECONSOLEINPUT_MSG;

typedef struct _CONSOLE_WRITECONSOLEOUTPUTSTRING_MSG {
    IN COORD WriteCoord;
    IN ULONG StringType;
    OUT ULONG NumRecords;
} CONSOLE_WRITECONSOLEOUTPUTSTRING_MSG, * PCONSOLE_WRITECONSOLEOUTPUTSTRING_MSG;

typedef struct _CONSOLE_WRITECONSOLEOUTPUT_MSG {
    IN OUT SMALL_RECT CharRegion;
    IN BOOLEAN Unicode;
} CONSOLE_WRITECONSOLEOUTPUT_MSG, * PCONSOLE_WRITECONSOLEOUTPUT_MSG;

typedef struct _CONSOLE_READCONSOLEOUTPUT_MSG {
    IN OUT SMALL_RECT CharRegion;
    IN BOOLEAN Unicode;
} CONSOLE_READCONSOLEOUTPUT_MSG, * PCONSOLE_READCONSOLEOUTPUT_MSG;

typedef struct _CONSOLE_GETTITLE_MSG {
    OUT ULONG TitleLength;
    IN BOOLEAN Unicode;
    IN BOOLEAN Original;
} CONSOLE_GETTITLE_MSG, * PCONSOLE_GETTITLE_MSG;

typedef struct _CONSOLE_SETTITLE_MSG {
    IN BOOLEAN Unicode;
} CONSOLE_SETTITLE_MSG, * PCONSOLE_SETTITLE_MSG;

typedef enum _CONSOLE_API_NUMBER_L2 {
    ConsolepFillConsoleOutput = CONSOLE_FIRST_API_NUMBER(2),
    ConsolepGenerateCtrlEvent,
    ConsolepSetActiveScreenBuffer,
    ConsolepFlushInputBuffer,
    ConsolepSetCP,
    ConsolepGetCursorInfo,
    ConsolepSetCursorInfo,
    ConsolepGetScreenBufferInfo,
    ConsolepSetScreenBufferInfo,
    ConsolepSetScreenBufferSize,
    ConsolepSetCursorPosition,
    ConsolepGetLargestWindowSize,
    ConsolepScrollScreenBuffer,
    ConsolepSetTextAttribute,
    ConsolepSetWindowInfo,
    ConsolepReadConsoleOutputString,
    ConsolepWriteConsoleInput,
    ConsolepWriteConsoleOutput,
    ConsolepWriteConsoleOutputString,
    ConsolepReadConsoleOutput,
    ConsolepGetTitle,
    ConsolepSetTitle,
} CONSOLE_API_NUMBER_L2, * PCONSOLE_API_NUMBER_L2;

typedef union _CONSOLE_MSG_BODY_L2 {
    CONSOLE_CTRLEVENT_MSG GenerateConsoleCtrlEvent;
    CONSOLE_FILLCONSOLEOUTPUT_MSG FillConsoleOutput;
    CONSOLE_SETCP_MSG SetConsoleCP;
    CONSOLE_GETCURSORINFO_MSG GetConsoleCursorInfo;
    CONSOLE_SETCURSORINFO_MSG SetConsoleCursorInfo;
    CONSOLE_SCREENBUFFERINFO_MSG GetConsoleScreenBufferInfo;
    CONSOLE_SCREENBUFFERINFO_MSG SetConsoleScreenBufferInfo;
    CONSOLE_SETSCREENBUFFERSIZE_MSG SetConsoleScreenBufferSize;
    CONSOLE_SETCURSORPOSITION_MSG SetConsoleCursorPosition;
    CONSOLE_GETLARGESTWINDOWSIZE_MSG GetLargestConsoleWindowSize;
    CONSOLE_SCROLLSCREENBUFFER_MSG ScrollConsoleScreenBuffer;
    CONSOLE_SETTEXTATTRIBUTE_MSG SetConsoleTextAttribute;
    CONSOLE_SETWINDOWINFO_MSG SetConsoleWindowInfo;
    CONSOLE_READCONSOLEOUTPUTSTRING_MSG ReadConsoleOutputString;
    CONSOLE_WRITECONSOLEINPUT_MSG WriteConsoleInput;
    CONSOLE_WRITECONSOLEOUTPUTSTRING_MSG WriteConsoleOutputString;
    CONSOLE_WRITECONSOLEOUTPUT_MSG WriteConsoleOutput;
    CONSOLE_READCONSOLEOUTPUT_MSG ReadConsoleOutput;
    CONSOLE_SETTITLE_MSG SetConsoleTitle;
    CONSOLE_GETTITLE_MSG GetConsoleTitle;
} CONSOLE_MSG_BODY_L2, * PCONSOLE_MSG_BODY_L2;

#ifndef __cplusplus
typedef struct _CONSOLE_MSG_L2 {
    CONSOLE_MSG_HEADER Header;
    union {
        CONSOLE_MSG_BODY_L2;
    } u;
} CONSOLE_MSG_L2, * PCONSOLE_MSG_L2;
#else
typedef struct _CONSOLE_MSG_L2 :
    public CONSOLE_MSG_HEADER
{
    CONSOLE_MSG_BODY_L2 u;
} CONSOLE_MSG_L2, * PCONSOLE_MSG_L2;
#endif // __cplusplus

    // TODO Compare against terminal/src/server/ApiSorter.cpp
// typedef enum CONSOLE_L2_API_TYPE {
//     Api_FillConsoleOutput,
//     Api_GenerateConsoleCtrlEvent,
//     Api_SetConsoleActiveScreenBuffer,
//     Api_FlushConsoleInputBuffer,
//     Api_SetConsoleCP,
//     Api_GetConsoleCursorInfo,
//     Api_SetConsoleCursorInfo,
//     Api_GetConsoleScreenBufferInfo,
//     Api_SetConsoleScreenBufferInfo,
//     Api_SetConsoleScreenBufferSize,
//     Api_SetConsoleCursorPosition,
//     Api_GetLargestConsoleWindowSize,
//     Api_ScrollConsoleScreenBuffer,
//     Api_SetConsoleTextAttribute,
//     Api_SetConsoleWindowInfo,
//     Api_ReadConsoleOutputString,
//     Api_WriteConsoleInput,
//     Api_WriteConsoleOutput,
//     Api_WriteConsoleOutputString,
//     Api_ReadConsoleOutput,
//     Api_GetConsoleTitle,
//     Api_SetConsoleTitle,
// } CONSOLE_L2_API_TYPE;



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

#pragma once

typedef struct _CONSOLE_GETNUMBEROFFONTS_MSG {
    OUT ULONG NumberOfFonts;
} CONSOLE_GETNUMBEROFFONTS_MSG, * PCONSOLE_GETNUMBEROFFONTS_MSG;

typedef struct _CONSOLE_GETSELECTIONINFO_MSG {
    OUT CONSOLE_SELECTION_INFO SelectionInfo;
} CONSOLE_GETSELECTIONINFO_MSG, * PCONSOLE_GETSELECTIONINFO_MSG;

typedef struct _CONSOLE_GETMOUSEINFO_MSG {
    OUT ULONG NumButtons;
} CONSOLE_GETMOUSEINFO_MSG, * PCONSOLE_GETMOUSEINFO_MSG;

typedef struct _CONSOLE_GETFONTINFO_MSG {
    IN BOOLEAN MaximumWindow;
    OUT ULONG NumFonts;  // this value is valid even for error cases
} CONSOLE_GETFONTINFO_MSG, * PCONSOLE_GETFONTINFO_MSG;

typedef struct _CONSOLE_GETFONTSIZE_MSG {
    IN ULONG  FontIndex;
    OUT COORD FontSize;
} CONSOLE_GETFONTSIZE_MSG, * PCONSOLE_GETFONTSIZE_MSG;

typedef struct _CONSOLE_CURRENTFONT_MSG {
    IN BOOLEAN MaximumWindow;
    IN OUT ULONG FontIndex;
    IN OUT COORD FontSize;
    IN OUT ULONG FontFamily;
    IN OUT ULONG FontWeight;
    IN OUT WCHAR FaceName[LF_FACESIZE];
} CONSOLE_CURRENTFONT_MSG, * PCONSOLE_CURRENTFONT_MSG;

typedef struct _CONSOLE_SETFONT_MSG {
    IN ULONG  FontIndex;
} CONSOLE_SETFONT_MSG, * PCONSOLE_SETFONT_MSG;

typedef struct _CONSOLE_SETICON_MSG {
    IN HICON hIcon;
} CONSOLE_SETICON_MSG, * PCONSOLE_SETICON_MSG;

typedef struct _CONSOLE_SETICON_MSG64 {
    IN PVOID64 hIcon;
} CONSOLE_SETICON_MSG64, * PCONSOLE_SETICON_MSG64;

typedef struct _CONSOLE_ADDALIAS_MSG {
    IN USHORT SourceLength;
    IN USHORT TargetLength;
    IN USHORT ExeLength;
    IN BOOLEAN Unicode;
} CONSOLE_ADDALIAS_MSG, * PCONSOLE_ADDALIAS_MSG;

typedef struct _CONSOLE_GETALIAS_MSG {
    IN USHORT SourceLength;
    OUT USHORT TargetLength;
    IN USHORT ExeLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETALIAS_MSG, * PCONSOLE_GETALIAS_MSG;

typedef struct _CONSOLE_GETALIASESLENGTH_MSG {
    OUT ULONG AliasesLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETALIASESLENGTH_MSG, * PCONSOLE_GETALIASESLENGTH_MSG;

typedef struct _CONSOLE_GETALIASEXESLENGTH_MSG {
    OUT ULONG AliasExesLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETALIASEXESLENGTH_MSG, * PCONSOLE_GETALIASEXESLENGTH_MSG;

typedef struct _CONSOLE_GETALIASES_MSG {
    IN BOOLEAN Unicode;
    OUT ULONG AliasesBufferLength;
} CONSOLE_GETALIASES_MSG, * PCONSOLE_GETALIASES_MSG;

typedef struct _CONSOLE_GETALIASEXES_MSG {
    OUT ULONG AliasExesBufferLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETALIASEXES_MSG, * PCONSOLE_GETALIASEXES_MSG;

typedef struct _CONSOLE_EXPUNGECOMMANDHISTORY_MSG {
    IN BOOLEAN Unicode;
} CONSOLE_EXPUNGECOMMANDHISTORY_MSG, * PCONSOLE_EXPUNGECOMMANDHISTORY_MSG;

typedef struct _CONSOLE_SETNUMBEROFCOMMANDS_MSG {
    IN ULONG NumCommands;
    IN BOOLEAN Unicode;
} CONSOLE_SETNUMBEROFCOMMANDS_MSG, * PCONSOLE_SETNUMBEROFCOMMANDS_MSG;

typedef struct _CONSOLE_GETCOMMANDHISTORYLENGTH_MSG {
    OUT ULONG CommandHistoryLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETCOMMANDHISTORYLENGTH_MSG, * PCONSOLE_GETCOMMANDHISTORYLENGTH_MSG;

typedef struct _CONSOLE_GETCOMMANDHISTORY_MSG {
    OUT ULONG CommandBufferLength;
    IN BOOLEAN Unicode;
} CONSOLE_GETCOMMANDHISTORY_MSG, * PCONSOLE_GETCOMMANDHISTORY_MSG;

typedef struct _CONSOLE_INVALIDATERECT_MSG {
    IN SMALL_RECT Rect;
} CONSOLE_INVALIDATERECT_MSG, * PCONSOLE_INVALIDATERECT_MSG;

typedef struct _CONSOLE_VDM_MSG {
    IN ULONG iFunction;
    OUT BOOLEAN Bool;
    IN OUT POINT Point;
    OUT RECT Rect;
} CONSOLE_VDM_MSG, * PCONSOLE_VDM_MSG;

typedef struct _CONSOLE_SETCURSOR_MSG {
    IN HCURSOR CursorHandle;
} CONSOLE_SETCURSOR_MSG, * PCONSOLE_SETCURSOR_MSG;

typedef struct _CONSOLE_SETCURSOR_MSG64 {
    IN PVOID64 CursorHandle;
} CONSOLE_SETCURSOR_MSG64, * PCONSOLE_SETCURSOR_MSG64;

typedef struct _CONSOLE_SHOWCURSOR_MSG {
    IN BOOLEAN bShow;
    OUT ULONG DisplayCount;
} CONSOLE_SHOWCURSOR_MSG, * PCONSOLE_SHOWCURSOR_MSG;

typedef struct _CONSOLE_MENUCONTROL_MSG {
    IN ULONG CommandIdLow;
    IN ULONG CommandIdHigh;
    OUT HMENU hMenu;
} CONSOLE_MENUCONTROL_MSG, * PCONSOLE_MENUCONTROL_MSG;

typedef struct _CONSOLE_MENUCONTROL_MSG64 {
    IN ULONG CommandIdLow;
    IN ULONG CommandIdHigh;
    OUT PVOID64 hMenu;
} CONSOLE_MENUCONTROL_MSG64, * PCONSOLE_MENUCONTROL_MSG64;

typedef struct _CONSOLE_SETPALETTE_MSG {
    IN HPALETTE hPalette;
    IN ULONG dwUsage;
} CONSOLE_SETPALETTE_MSG, * PCONSOLE_SETPALETTE_MSG;

typedef struct _CONSOLE_SETPALETTE_MSG64 {
    IN PVOID64 hPalette;
    IN ULONG dwUsage;
} CONSOLE_SETPALETTE_MSG64, * PCONSOLE_SETPALETTE_MSG64;

typedef struct _CONSOLE_SETDISPLAYMODE_MSG {
    IN ULONG dwFlags;
    OUT COORD ScreenBufferDimensions;
} CONSOLE_SETDISPLAYMODE_MSG, * PCONSOLE_SETDISPLAYMODE_MSG;

typedef struct _CONSOLE_REGISTERVDM_MSG {
    IN ULONG RegisterFlags;
    IN HANDLE StartEvent;
    IN HANDLE EndEvent;
    IN HANDLE ErrorEvent;
    OUT ULONG StateLength;
    OUT PVOID StateBuffer;
    OUT PVOID VDMBuffer;
} CONSOLE_REGISTERVDM_MSG, * PCONSOLE_REGISTERVDM_MSG;

typedef struct _CONSOLE_REGISTERVDM_MSG64 {
    IN ULONG RegisterFlags;
    IN PVOID64 StartEvent;
    IN PVOID64 EndEvent;
    IN PVOID64 ErrorEvent;
    OUT ULONG StateLength;
    OUT PVOID64 StateBuffer;
    OUT PVOID64 VDMBuffer;
} CONSOLE_REGISTERVDM_MSG64, * PCONSOLE_REGISTERVDM_MSG64;

typedef struct _CONSOLE_GETHARDWARESTATE_MSG {
    OUT COORD Resolution;
    OUT COORD FontSize;
} CONSOLE_GETHARDWARESTATE_MSG, * PCONSOLE_GETHARDWARESTATE_MSG;

typedef struct _CONSOLE_SETHARDWARESTATE_MSG {
    IN COORD Resolution;
    IN COORD FontSize;
} CONSOLE_SETHARDWARESTATE_MSG, * PCONSOLE_SETHARDWARESTATE_MSG;

typedef struct _CONSOLE_GETDISPLAYMODE_MSG {
    OUT ULONG ModeFlags;
} CONSOLE_GETDISPLAYMODE_MSG, * PCONSOLE_GETDISPLAYMODE_MSG;

typedef struct _CONSOLE_GETKEYBOARDLAYOUTNAME_MSG {
    union {
        WCHAR awchLayout[9];
        char achLayout[9];
    };
    BOOLEAN bAnsi;
} CONSOLE_GETKEYBOARDLAYOUTNAME_MSG, * PCONSOLE_GETKEYBOARDLAYOUTNAME_MSG;

typedef struct _CONSOLE_SETKEYSHORTCUTS_MSG {
    IN BOOLEAN Set;
    IN BYTE ReserveKeys;
} CONSOLE_SETKEYSHORTCUTS_MSG, * PCONSOLE_SETKEYSHORTCUTS_MSG;

typedef struct _CONSOLE_SETMENUCLOSE_MSG {
    IN BOOLEAN Enable;
} CONSOLE_SETMENUCLOSE_MSG, * PCONSOLE_SETMENUCLOSE_MSG;

typedef struct _CONSOLE_CHAR_TYPE_MSG {
    IN COORD coordCheck;
    OUT ULONG dwType;
} CONSOLE_CHAR_TYPE_MSG, * PCONSOLE_CHAR_TYPE_MSG;

typedef struct _CONSOLE_LOCAL_EUDC_MSG {
    IN USHORT CodePoint;
    IN COORD FontSize;
} CONSOLE_LOCAL_EUDC_MSG, * PCONSOLE_LOCAL_EUDC_MSG;

typedef struct _CONSOLE_CURSOR_MODE_MSG {
    IN OUT BOOLEAN Blink;
    IN OUT BOOLEAN DBEnable;
} CONSOLE_CURSOR_MODE_MSG, * PCONSOLE_CURSOR_MODE_MSG;

typedef struct _CONSOLE_REGISTEROS2_MSG {
    IN BOOLEAN fOs2Register;
} CONSOLE_REGISTEROS2_MSG, * PCONSOLE_REGISTEROS2_MSG;

typedef struct _CONSOLE_SETOS2OEMFORMAT_MSG {
    IN BOOLEAN fOs2OemFormat;
} CONSOLE_SETOS2OEMFORMAT_MSG, * PCONSOLE_SETOS2OEMFORMAT_MSG;

typedef struct _CONSOLE_NLS_MODE_MSG {
    IN OUT BOOLEAN Ready;
    IN ULONG NlsMode;
} CONSOLE_NLS_MODE_MSG, * PCONSOLE_NLS_MODE_MSG;

typedef struct _CONSOLE_GETCONSOLEWINDOW_MSG {
    OUT HWND hwnd;
} CONSOLE_GETCONSOLEWINDOW_MSG, * PCONSOLE_GETCONSOLEWINDOW_MSG;

typedef struct _CONSOLE_GETCONSOLEWINDOW_MSG64 {
    OUT PVOID64 hwnd;
} CONSOLE_GETCONSOLEWINDOW_MSG64, * PCONSOLE_GETCONSOLEWINDOW_MSG64;

typedef struct _CONSOLE_GETPROCESSLIST_MSG {
    OUT ULONG dwProcessCount;
} CONSOLE_GETCONSOLEPROCESSLIST_MSG, * PCONSOLE_GETCONSOLEPROCESSLIST_MSG;

typedef struct _CONSOLE_GETHISTORY_MSG {
    OUT ULONG HistoryBufferSize;
    OUT ULONG NumberOfHistoryBuffers;
    OUT ULONG dwFlags;
} CONSOLE_HISTORY_MSG, * PCONSOLE_HISTORY_MSG;

typedef enum _CONSOLE_API_NUMBER_L3 {
    ConsolepGetNumberOfFonts = CONSOLE_FIRST_API_NUMBER(3),
    ConsolepGetMouseInfo,
    ConsolepGetFontInfo,
    ConsolepGetFontSize,
    ConsolepGetCurrentFont,
    ConsolepSetFont,
    ConsolepSetIcon,
    ConsolepInvalidateBitmapRect,
    ConsolepVDMOperation,
    ConsolepSetCursor,
    ConsolepShowCursor,
    ConsolepMenuControl,
    ConsolepSetPalette,
    ConsolepSetDisplayMode,
    ConsolepRegisterVDM,
    ConsolepGetHardwareState,
    ConsolepSetHardwareState,
    ConsolepGetDisplayMode,
    ConsolepAddAlias,
    ConsolepGetAlias,
    ConsolepGetAliasesLength,
    ConsolepGetAliasExesLength,
    ConsolepGetAliases,
    ConsolepGetAliasExes,
    ConsolepExpungeCommandHistory,
    ConsolepSetNumberOfCommands,
    ConsolepGetCommandHistoryLength,
    ConsolepGetCommandHistory,
    ConsolepSetKeyShortcuts,
    ConsolepSetMenuClose,
    ConsolepGetKeyboardLayoutName,
    ConsolepGetConsoleWindow,
    ConsolepCharType,
    ConsolepSetLocalEUDC,
    ConsolepSetCursorMode,
    ConsolepGetCursorMode,
    ConsolepRegisterOS2,
    ConsolepSetOS2OemFormat,
    ConsolepGetNlsMode,
    ConsolepSetNlsMode,
    ConsolepGetSelectionInfo,
    ConsolepGetConsoleProcessList,
    ConsolepGetHistory,
    ConsolepSetHistory,
    ConsolepSetCurrentFont,
} CONSOLE_API_NUMBER_L3, * PCONSOLE_API_NUMBER_L3;

typedef union _CONSOLE_MSG_BODY_L3 {
    CONSOLE_GETNUMBEROFFONTS_MSG GetNumberOfConsoleFonts;
    CONSOLE_GETMOUSEINFO_MSG GetConsoleMouseInfo;
    CONSOLE_GETFONTINFO_MSG GetConsoleFontInfo;
    CONSOLE_GETFONTSIZE_MSG GetConsoleFontSize;
    CONSOLE_CURRENTFONT_MSG GetCurrentConsoleFont;
    CONSOLE_SETFONT_MSG SetConsoleFont;
    CONSOLE_INVALIDATERECT_MSG InvalidateConsoleBitmapRect;
    CONSOLE_VDM_MSG VDMConsoleOperation;
    CONSOLE_SHOWCURSOR_MSG ShowConsoleCursor;
    CONSOLE_SETDISPLAYMODE_MSG SetConsoleDisplayMode;
#ifdef BUILD_WOW6432
    CONSOLE_REGISTERVDM_MSG64 RegisterConsoleVDM;
    CONSOLE_SETCURSOR_MSG64 SetConsoleCursor;
    CONSOLE_SETICON_MSG64 SetConsoleIcon;
    CONSOLE_MENUCONTROL_MSG64 ConsoleMenuControl;
    CONSOLE_SETPALETTE_MSG64 SetConsolePalette;
    CONSOLE_GETCONSOLEWINDOW_MSG64 GetConsoleWindow;
#else
    CONSOLE_REGISTERVDM_MSG RegisterConsoleVDM;
    CONSOLE_SETCURSOR_MSG SetConsoleCursor;
    CONSOLE_SETICON_MSG SetConsoleIcon;
    CONSOLE_MENUCONTROL_MSG ConsoleMenuControl;
    CONSOLE_SETPALETTE_MSG SetConsolePalette;
    CONSOLE_GETCONSOLEWINDOW_MSG GetConsoleWindow;
#endif
    CONSOLE_GETHARDWARESTATE_MSG GetConsoleHardwareState;
    CONSOLE_SETHARDWARESTATE_MSG SetConsoleHardwareState;
    CONSOLE_GETDISPLAYMODE_MSG GetConsoleDisplayMode;
    CONSOLE_ADDALIAS_MSG AddConsoleAliasW;
    CONSOLE_GETALIAS_MSG GetConsoleAliasW;
    CONSOLE_GETALIASESLENGTH_MSG GetConsoleAliasesLengthW;
    CONSOLE_GETALIASEXESLENGTH_MSG GetConsoleAliasExesLengthW;
    CONSOLE_GETALIASES_MSG GetConsoleAliasesW;
    CONSOLE_GETALIASEXES_MSG GetConsoleAliasExesW;
    CONSOLE_EXPUNGECOMMANDHISTORY_MSG ExpungeConsoleCommandHistoryW;
    CONSOLE_SETNUMBEROFCOMMANDS_MSG SetConsoleNumberOfCommandsW;
    CONSOLE_GETCOMMANDHISTORYLENGTH_MSG GetConsoleCommandHistoryLengthW;
    CONSOLE_GETCOMMANDHISTORY_MSG GetConsoleCommandHistoryW;
    CONSOLE_SETKEYSHORTCUTS_MSG SetConsoleKeyShortcuts;
    CONSOLE_SETMENUCLOSE_MSG SetConsoleMenuClose;
    CONSOLE_GETKEYBOARDLAYOUTNAME_MSG GetKeyboardLayoutName;
    CONSOLE_CHAR_TYPE_MSG GetConsoleCharType;
    CONSOLE_LOCAL_EUDC_MSG SetConsoleLocalEUDC;
    CONSOLE_CURSOR_MODE_MSG SetConsoleCursorMode;
    CONSOLE_CURSOR_MODE_MSG GetConsoleCursorMode;
    CONSOLE_REGISTEROS2_MSG RegisterConsoleOS2;
    CONSOLE_SETOS2OEMFORMAT_MSG SetConsoleOS2OemFormat;
    CONSOLE_NLS_MODE_MSG GetConsoleNlsMode;
    CONSOLE_NLS_MODE_MSG SetConsoleNlsMode;
    CONSOLE_GETSELECTIONINFO_MSG GetConsoleSelectionInfo;
    CONSOLE_GETCONSOLEPROCESSLIST_MSG GetConsoleProcessList;
    CONSOLE_CURRENTFONT_MSG SetCurrentConsoleFont;
    CONSOLE_HISTORY_MSG SetConsoleHistory;
    CONSOLE_HISTORY_MSG GetConsoleHistory;
} CONSOLE_MSG_BODY_L3, * PCONSOLE_MSG_BODY_L3;

#ifndef __cplusplus
typedef struct _CONSOLE_MSG_L3 {
    CONSOLE_MSG_HEADER Header;
    union {
        CONSOLE_MSG_BODY_L3;
    } u;
} CONSOLE_MSG_L3, * PCONSOLE_MSG_L3;
#else
typedef struct _CONSOLE_MSG_L3 :
    public CONSOLE_MSG_HEADER
{
    CONSOLE_MSG_BODY_L3 u;
} CONSOLE_MSG_L3, * PCONSOLE_MSG_L3;
#endif  // __cplusplus

    // TODO Compare against terminal/src/server/ApiSorter.cpp
// typedef enum CONSOLE_L3_API_TYPE {
//     Api_GetNumberOfFonts,
//     Api_GetNumberOfConsoleMouseButtons,
//     Api_GetFontInfo,
//     Api_GetConsoleFontSize,
//     Api_GetCurrentConsoleFont,
//     Api_SetFont,
//     Api_SetIcon,
//     Api_InvalidateRect,
//     Api_VDM,
//     Api_SetCursor,
//     Api_ShowCursor,
//     Api_MenuControl,
//     Api_SetPalette,
//     Api_SetConsoleDisplayMode,
//     Api_RegisterVDM,
//     Api_GetHardwareState,
//     Api_SetHardwareState,
//     Api_GetConsoleDisplayMode,
//     Api_AddConsoleAlias,
//     Api_GetConsoleAlias,
//     Api_GetConsoleAliasesLength,
//     Api_GetConsoleAliasExesLength,
//     Api_GetConsoleAliases,
//     Api_GetConsoleAliasExes,
//     Api_ExpungeConsoleCommandHistory,
//     Api_SetConsoleNumberOfCommands,
//     Api_GetConsoleCommandHistoryLength,
//     Api_GetConsoleCommandHistory,
//     Api_SetKeyShortcuts,
//     Api_MenuClose,
//     Api_GetKeyboardLayoutName,
//     Api_GetConsoleWindow,
//     Api_CharType,
//     Api_LocalEudc,
//     Api_CursorMode,
//     Api_CursorMode2,
//     Api_RegisterOS2,
//     Api_SetOS2OEMFormat,
//     Api_NlsMode,
//     Api_NlsMode2,
//     Api_GetConsoleSelectionInfo,
//     Api_GetConsoleProcessList,
//     Api_GetConsoleHistory,
//     Api_SetConsoleHistory,
//     Api_SetConsoleCurrentFont,
// } CONSOLE_L3_API_TYPE;



/*++
Copyright (c) Microsoft Corporation
Licensed under the MIT license.

Module Name:
- conwinuserrefs.h

Abstract:
- Contains private definitions from WinUserK.h that we'll need to publish.
--*/

#pragma once

#pragma region WinUserK.h(private internal)

extern "C" {
/* WinUserK */
/*
* Console window startup optimization.
*/

// TODO Seems to be exactly the same as handterm's ControlType below, however with some "reserved" stuff
typedef enum _CONSOLECONTROL
{
    Reserved1,
    ConsoleNotifyConsoleApplication,
    Reserved2,
    ConsoleSetCaretInfo,
    Reserved3,
    ConsoleSetForeground,
    ConsoleSetWindowOwner,
    ConsoleEndTask,
} CONSOLECONTROL;

//
// CtrlFlags definitions
//
#define CONSOLE_CTRL_C_FLAG 0x00000001
#define CONSOLE_CTRL_BREAK_FLAG 0x00000002
#define CONSOLE_CTRL_CLOSE_FLAG 0x00000004

#define CONSOLE_CTRL_LOGOFF_FLAG 0x00000010
#define CONSOLE_CTRL_SHUTDOWN_FLAG 0x00000020

typedef struct _CONSOLEENDTASK
{
    HANDLE ProcessId;
    HWND hwnd;
    ULONG ConsoleEventCode;
    ULONG ConsoleFlags;
} CONSOLEENDTASK, *PCONSOLEENDTASK;

typedef struct _CONSOLEWINDOWOWNER
{
    HWND hwnd;
    ULONG ProcessId;
    ULONG ThreadId;
} CONSOLEWINDOWOWNER, *PCONSOLEWINDOWOWNER;

typedef struct _CONSOLESETFOREGROUND
{
    HANDLE hProcess;
    BOOL bForeground;
} CONSOLESETFOREGROUND, *PCONSOLESETFOREGROUND;

/*
    * Console window startup optimization.
    */
#define CPI_NEWPROCESSWINDOW 0x0001

typedef struct _CONSOLE_PROCESS_INFO
{
    IN DWORD dwProcessID;
    IN DWORD dwFlags;
} CONSOLE_PROCESS_INFO, *PCONSOLE_PROCESS_INFO;

typedef struct _CONSOLE_CARET_INFO
{
    IN HWND hwnd;
    IN RECT rc;
} CONSOLE_CARET_INFO, *PCONSOLE_CARET_INFO;

NTSTATUS ConsoleControl(
    __in CONSOLECONTROL Command,
    __in_bcount_opt(ConsoleInformationLength) PVOID ConsoleInformation,
    __in DWORD ConsoleInformationLength);

/* END WinUserK */
};
#pragma endregion



//// Misc

// NOTE As declared by handterm
typedef enum ControlType
{
    ConsoleSetVDMCursorBounds,
    ConsoleNotifyConsoleApplication,
    ConsoleFullscreenSwitch,
    ConsoleSetCaretInfo,
    ConsoleSetReserveKeys,
    ConsoleSetForeground,
    ConsoleSetWindowOwner,
    ConsoleEndTask,
} ControlType;

#define ProcThreadAttributeConsoleReference 10

#define PROC_THREAD_ATTRIBUTE_CONSOLE_REFERENCE \
    ProcThreadAttributeValue(10, FALSE, TRUE, FALSE)

#define ProcThreadAttributeValue(Number, Thread, Input, Additive) \
    (((Number) & PROC_THREAD_ATTRIBUTE_NUMBER) | \
        ((Thread != FALSE) ? PROC_THREAD_ATTRIBUTE_THREAD : 0) | \
        ((Input != FALSE) ? PROC_THREAD_ATTRIBUTE_INPUT : 0) | \
        ((Additive != FALSE) ? PROC_THREAD_ATTRIBUTE_ADDITIVE : 0))

#define PROC_THREAD_ATTRIBUTE_NUMBER 0x0000ffff
#define PROC_THREAD_ATTRIBUTE_THREAD 0x00010000
#define PROC_THREAD_ATTRIBUTE_INPUT 0x00020000
#define PROC_THREAD_ATTRIBUTE_ADDITIVE 0x00040000

typedef struct CONSOLE_API_MSG {
    CD_IO_DESCRIPTOR Descriptor;
    union
    {
        struct
        {
            CD_CREATE_OBJECT_INFORMATION CreateObject;
            CONSOLE_CREATESCREENBUFFER_MSG CreateScreenBuffer;
        };
        struct
        {
            CONSOLE_MSG_HEADER msgHeader;
            union
            {
                CONSOLE_MSG_BODY_L1 consoleMsgL1;
                CONSOLE_MSG_BODY_L2 consoleMsgL2;
                CONSOLE_MSG_BODY_L3 consoleMsgL3;
            } u;
        };
    };
} CONSOLE_API_MSG, * PCONSOLE_API_MSG;

#define FG_ATTRS (FOREGROUND_BLUE | FOREGROUND_GREEN | FOREGROUND_RED | FOREGROUND_INTENSITY)
#define BG_ATTRS (BACKGROUND_BLUE | BACKGROUND_GREEN | BACKGROUND_RED | BACKGROUND_INTENSITY)
#define META_ATTRS (COMMON_LVB_LEADING_BYTE | COMMON_LVB_TRAILING_BYTE | COMMON_LVB_GRID_HORIZONTAL | COMMON_LVB_GRID_LVERTICAL | COMMON_LVB_GRID_RVERTICAL | COMMON_LVB_REVERSE_VIDEO | COMMON_LVB_UNDERSCORE)

#define CONSOLE_READ_NOREMOVE   0x0001
#define CONSOLE_READ_NOWAIT     0x0002

// Used by TranslateMessageEx to purposefully return false to certain WM_KEYDOWN/WM_CHAR messages
// TODO See usage and note in terminal/src/interactivity/win32/windowio.cpp
#define TM_POSTCHARBREAKS 0x0002


// TODO https://doxygen.reactos.org/d8/d14/wincon_8h_source.html
// TODO https://doxygen.reactos.org/d1/d58/wincontypes_8h_source.html

