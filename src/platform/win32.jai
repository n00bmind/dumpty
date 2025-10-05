
//// Some utilities

HRESULT_FROM_WIN32 :: inline ( x: u32 ) -> HRESULT
{ 
    FACILITY_WIN32 :: 0x0007;

    return ifx cast(HRESULT) x <= 0
        then cast(HRESULT) x
        else cast(HRESULT) ((x & 0x0000FFFF) | (FACILITY_WIN32 << 16) | 0x80000000);
}

GetLastErrorAsHr :: inline () -> HRESULT
{
    return HRESULT_FROM_WIN32( GetLastError() );
}

WideStrTmp :: ( s: string ) -> PCWSTR, lenBytes: s32
{
    result, success, lenBytes := utf8_to_wide( s,, temp );
    assert( success && "Wide string conversion failed" );

    return result, lenBytes;
}

/*++
Routine Description:
- This routine opens a handle to the console driver.

Arguments:
- handleOut - Receives the handle.
- deviceName - Supplies the name to be used to open the console driver.
- desiredAccess - Supplies the desired access mask.
- parent - Optionally supplies the parent object.
- inheritable - Supplies a boolean indicating if the new handle is to be made inheritable.
- openOptions - Supplies the open options to be passed to NtOpenFile. A common
                option for clients is FILE_SYNCHRONOUS_IO_NONALERT, to make the handle
                synchronous.

Return Value:
- NTSTATUS indicating if the handle was successfully created.
--*/
CreateHandle :: ( handleOut: PHANDLE, deviceName: string, desiredAccess: ACCESS_MASK,
                  parent: HANDLE , inheritable: BOOLEAN, openOptions: ULONG ) -> NTSTATUS
{
    flags: ULONG = OBJ_CASE_INSENSITIVE;

    if inheritable
        flags |= OBJ_INHERIT;

    wideStr, lenBytes := WideStrTmp( deviceName );

    name: UNICODE_STRING;
    name.Buffer = cast(PWSTR) wideStr;
    name.Length = cast(USHORT) lenBytes;
    name.MaximumLength = name.Length + size_of(WCHAR);

    objectAttributes: OBJECT_ATTRIBUTES;
    InitializeObjectAttributes( *objectAttributes, *name, flags, parent, NULL );

    ioStatus: IO_STATUS_BLOCK;
    return NtOpenFile( handleOut, desiredAccess, *objectAttributes, *ioStatus,
                       FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, openOptions );
}

InitializeObjectAttributes :: ( p: POBJECT_ATTRIBUTES, n: PUNICODE_STRING, a: ULONG,
                                r: HANDLE, s: PSECURITY_DESCRIPTOR )
{
    p.Length = size_of(OBJECT_ATTRIBUTES);
    p.RootDirectory = r;
    p.ObjectName = n;
    p.Attributes = a;
    p.SecurityDescriptor = s;
    p.SecurityQualityOfService = NULL;
}

/*++
Routine Description:
- This routine creates a handle to an input or output client of the given
  server. No control io is sent to the server as this request must be coming
  from the server itself.

Arguments:
- handleOut - Receives a handle to the new client.
- serverHandle - Supplies a handle to the server to which to attach the
                 newly created client.
- name - Supplies the name of the client object.
- inheritable - Supplies a flag indicating if the handle must be inheritable.

Return Value:
- NTSTATUS indicating if the client was successfully created.
--*/
CreateClientHandle :: ( handleOut: PHANDLE, serverHandle: HANDLE, name: string,
                        inheritable: BOOLEAN ) -> NTSTATUS
{
    return CreateHandle( handleOut, name, GENERIC_WRITE | GENERIC_READ | SYNCHRONIZE,
                         serverHandle, inheritable, FILE_SYNCHRONOUS_IO_NONALERT );
}

/*++
Routine Description:
- This routine creates a new server on the driver and returns a handle to it.

Arguments:
- handleOut - Receives a handle to the new server.
- inheritable - Supplies a flag indicating if the handle must be inheritable.

Return Value:
- NTSTATUS indicating if the console was successfully created.
--*/
CreateServerHandle :: ( handleOut: PHANDLE, inheritable: BOOLEAN ) -> NTSTATUS
{
    return CreateHandle( handleOut, "\\Device\\ConDrv\\Server", GENERIC_ALL, NULL,
                         inheritable, 0 );
}




NULL                                :: cast(*void) 0;
BYTE                                :: u8;
UCHAR                               :: u8;
USHORT                              :: u16;
ULONG                               :: u32;
WCHAR                               :: u16;
PWSTR                               :: *WCHAR;
PCWSTR                              :: *WCHAR; // const
PVOID                               :: *void;
PVOID64                             :: *void;
DWORD_PTR                           :: u64;
ULONG_PTR                           :: u64;
PHANDLE                             :: *HANDLE;
ACCESS_MASK                         :: DWORD;
HPCON                               :: *void;
HPALETTE                            :: *void;
LANGID                              :: USHORT;


OBJ_INHERIT                         :: 0x00000002;
OBJ_CASE_INSENSITIVE                :: 0x00000040;
SYNCHRONIZE                         :: 0x00100000;
PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE :: 131094;
FILE_WRITE_ATTRIBUTES               :: 0x100;
FILE_OPEN                           :: 0x00000001;
FILE_CREATE                         :: 0x00000002;
FILE_PIPE_BYTE_STREAM_TYPE          :: 0x00000000;
FILE_PIPE_BYTE_STREAM_MODE          :: 0x00000000;
FILE_PIPE_QUEUE_OPERATION           :: 0x00000000;
FILE_SYNCHRONOUS_IO_NONALERT        :: 0x00000020;
FILE_NON_DIRECTORY_FILE             :: 0x00000040;
CREATE_EVENT_MANUAL_RESET           :: 0x1;
EVENT_ALL_ACCESS                    :: 0x1F0003;
DUPLICATE_SAME_ACCESS               :: 0x00000002;
ERROR_PIPE_NOT_CONNECTED            :: 233;


UNICODE_STRING :: struct
{
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PWSTR;
}
PUNICODE_STRING :: *UNICODE_STRING;

OBJECT_ATTRIBUTES :: struct
{
    Length: ULONG;
    RootDirectory: HANDLE;
    ObjectName: *UNICODE_STRING;
    Attributes: ULONG;
    SecurityDescriptor: *void;
    SecurityQualityOfService: *void;
}
POBJECT_ATTRIBUTES :: *OBJECT_ATTRIBUTES;

IO_STATUS_BLOCK :: struct
{
    union {
        Status: NTSTATUS;
        Pointer: *void;
    }
    Information: ULONG_PTR;
}
PIO_STATUS_BLOCK :: *IO_STATUS_BLOCK;

SECURITY_DESCRIPTOR :: struct
{
    Revision: UCHAR;
    Sbz1: UCHAR;
    Control: USHORT;
    Owner: ULONG;
    Group: ULONG;
    Sacl: ULONG;
    Dacl: ULONG;
}
PSECURITY_DESCRIPTOR :: *SECURITY_DESCRIPTOR;

proc_thread_attr :: struct
{
    attr: DWORD_PTR;
    size: SIZE_T;
    value: *void;
}
 
PROC_THREAD_ATTRIBUTE_LIST :: struct
{
    mask: DWORD;  /* bitmask of items in list */
    size: DWORD;  /* max number of items in list */
    count: DWORD; /* number of items in list */
    pad: DWORD;
    unk: DWORD_PTR;
    attrs: [1] proc_thread_attr;
}
PPROC_THREAD_ATTRIBUTE_LIST :: *PROC_THREAD_ATTRIBUTE_LIST;

STARTUPINFOEXA :: struct
{
    StartupInfo: STARTUPINFOA;
    lpAttributeList: *PROC_THREAD_ATTRIBUTE_LIST;
}

STARTUPINFOEXW :: struct
{
    StartupInfo: STARTUPINFOW;
    lpAttributeList: *PROC_THREAD_ATTRIBUTE_LIST;
}


ntdll :: #system_library "ntdll";
kernel32 :: #system_library "kernel32";
user32 :: #system_library "user32";

NtOpenFile :: ( FileHandle: PHANDLE, DesiredAccess: ACCESS_MASK, ObjectAttributes: POBJECT_ATTRIBUTES,
                IoStatusBlock: PIO_STATUS_BLOCK, ShareAccess: ULONG, OpenOptions: ULONG ) -> NTSTATUS #foreign ntdll;

CreateEventExW :: ( sa: *SECURITY_ATTRIBUTES, name: PCWSTR, flags: DWORD, access: DWORD )
                    -> HANDLE #foreign kernel32;

DuplicateHandle :: ( hSourceProcessHandle: HANDLE, hSourceHandle: HANDLE, hTargetProcessHandle: HANDLE,
                     lpTargetHandle: PHANDLE, dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwOptions: DWORD )
                     -> BOOL #foreign kernel32;

InitializeProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, count: DWORD,
                                        flags: DWORD, size: *SIZE_T ) -> BOOL #foreign kernel32;

UpdateProcThreadAttribute :: ( list: *PROC_THREAD_ATTRIBUTE_LIST, flags: DWORD,
                                attr: DWORD_PTR, value: *void, size: SIZE_T,
                                prev_ret: *void, size_ret: *SIZE_T ) -> BOOL #foreign kernel32;

DeleteProcThreadAttributeList :: ( list: *PROC_THREAD_ATTRIBUTE_LIST ) -> void #foreign kernel32;

WaitForSingleObjectEx :: ( hHandle: HANDLE, dwMilliseconds: DWORD, bAlertable: BOOL ) -> DWORD #foreign kernel32;

DeviceIoControl :: ( handle: HANDLE, code: DWORD, in_buff: *void, in_count: DWORD, out_buff: *void, out_count: DWORD,
                     returned: *DWORD, overlapped: *OVERLAPPED ) -> BOOL #foreign kernel32;

// Conhost stuff
#load "win32_conhost.jai";

