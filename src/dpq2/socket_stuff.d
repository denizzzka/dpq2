///
module dpq2.socket_stuff;

import dpq2.connection: ConnectionException;
import std.socket;

/// Obtains duplicate file descriptor number of the socket
version(Posix)
socket_t duplicateSocket(int socket)
{
    import core.sys.posix.unistd: dup;

    static assert(socket_t.sizeof == int.sizeof);

    int ret = dup(socket);

    if(ret == -1)
        throw new ConnectionException("Socket duplication error");

    return cast(socket_t) ret;
}

/// Obtains duplicate file descriptor number of the socket
version(Windows)
SOCKET duplicateSocket(int socket)
{
    import core.stdc.stdlib: malloc, free;
    import core.sys.windows.winbase: GetCurrentProcessId;

    static assert(SOCKET.sizeof == socket_t.sizeof);

    auto protocolInfo = cast(WSAPROTOCOL_INFOW*) malloc(WSAPROTOCOL_INFOW.sizeof);
    scope(failure) free(protocolInfo);

    int dupStatus = WSADuplicateSocketW(socket, GetCurrentProcessId, protocolInfo);

    if(dupStatus)
        throw new ConnectionException("WSADuplicateSocketW error, code "~WSAGetLastError().to!string);

    SOCKET s = WSASocketW(
            FROM_PROTOCOL_INFO,
            FROM_PROTOCOL_INFO,
            FROM_PROTOCOL_INFO,
            protocolInfo,
            0,
            0
        );

    if(s == INVALID_SOCKET)
        throw new ConnectionException("WSASocket error, code "~WSAGetLastError().to!string);

    return s;
}

// Socket duplication structs for Win32
version(Windows)
private
{
    import core.sys.windows.windef;
    import core.sys.windows.basetyps: GUID;

    alias GROUP = uint;

    enum INVALID_SOCKET = 0;
    enum FROM_PROTOCOL_INFO =-1;
    enum MAX_PROTOCOL_CHAIN = 7;
    enum WSAPROTOCOL_LEN = 255;

    struct WSAPROTOCOLCHAIN
    {
        int ChainLen;
        DWORD[MAX_PROTOCOL_CHAIN] ChainEntries;
    }

    struct WSAPROTOCOL_INFOW
    {
        DWORD dwServiceFlags1;
        DWORD dwServiceFlags2;
        DWORD dwServiceFlags3;
        DWORD dwServiceFlags4;
        DWORD dwProviderFlags;
        GUID ProviderId;
        DWORD dwCatalogEntryId;
        WSAPROTOCOLCHAIN ProtocolChain;
        int iVersion;
        int iAddressFamily;
        int iMaxSockAddr;
        int iMinSockAddr;
        int iSocketType;
        int iProtocol;
        int iProtocolMaxOffset;
        int iNetworkByteOrder;
        int iSecurityScheme;
        DWORD dwMessageSize;
        DWORD dwProviderReserved;
        WCHAR[WSAPROTOCOL_LEN+1] szProtocol;
    }

    extern(Windows) nothrow @nogc
    {
        import core.sys.windows.winsock2: WSAGetLastError;
        int WSADuplicateSocketW(SOCKET s, DWORD dwProcessId, WSAPROTOCOL_INFOW* lpProtocolInfo);
        SOCKET WSASocketW(int af, int type, int protocol, WSAPROTOCOL_INFOW*, GROUP, DWORD dwFlags);
    }
}
