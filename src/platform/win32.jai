
//// Some utilities

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
CreateHandle :: ( handleOut: PHANDLE, deviceName: string, desiredAccess: ACCESS_MASK, parent: HANDLE , inheritable: BOOLEAN,
                  openOptions: ULONG ) -> NTSTATUS
{
    flags: ULONG = OBJ_CASE_INSENSITIVE;

    if inheritable
        flags |= OBJ_INHERIT;

    wideStr, lenBytes := WideStrTmp( deviceName );

    name: UNICODE_STRING;
    name.Buffer = cast(PWSTR) wideStr;
    name.Length = (USHORT) lenBytes;
    name.MaximumLength = name.Length + size_of(WCHAR);

    objectAttributes: OBJECT_ATTRIBUTES;
    InitializeObjectAttributes( *objectAttributes, *name, flags, parent, 0 );

    ioStatus: IO_STATUS_BLOCK;
    return NtOpenFile( handleOut, desiredAccess, *objectAttributes, *ioStatus,
                       FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, openOptions );
}

InitializeObjectAttributes :: ( p: POBJECT_ATTRIBUTES, n: PUNICODE_STRING, a: ULONG, r: HANDLE,
                                s: PSECURITY_DESCRIPTOR )
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
CreateClientHandle :: ( handleOut: PHANDLE, serverHandle: HANDLE, name: PCWSTR, inheritable: BOOLEAN ) -> NTSTATUS
{
    return CreateHandle( handleOut, name, GENERIC_WRITE | GENERIC_READ | SYNCHRONIZE, serverHandle, inheritable,
                         FILE_SYNCHRONOUS_IO_NONALERT );
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
    return CreateHandle( handleOut, WideStrTmp( "\\Device\\ConDrv\\Server" ), GENERIC_ALL, 0, inheritable, 0 );
}




WCHAR :: u16;
PWSTR :: *WCHAR;
PCWSTR :: *WCHAR; // const
PHANDLE :: *HANDLE;

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


ntdll :: #system_library "ntdll";
kernel32 :: #system_library "kernel32";

NtOpenFile :: ( FileHandle: PHANDLE, DesiredAccess: ACCESS_MASK, ObjectAttributes: POBJECT_ATTRIBUTES,
                IoStatusBlock: PIO_STATUS_BLOCK, ShareAccess: ULONG, OpenOptions: ULONG ) -> NTSTATUS #foreign ntdll;

DeviceIoControl :: ( handle: HANDLE, code: DWORD, in_buff: *void, in_count: DWORD, out_buff: *void, out_count: DWORD,
                     returned: *DWORD, overlapped: *OVERLAPPED ) -> BOOL #foreign kernel32;
