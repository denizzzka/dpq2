module dpq2.native_conn.connection;

import std.socket;

class NativeConnection
{
    private Socket socket;

    /// Starts creation of a connection to the database server in a nonblocking manner
    this(string host, ushort port)
    {
        socket = new TcpSocket();
        socket.blocking = false;
        auto addr = new InternetAddress(host, port);
        socket.connect(addr);
    }
}

version (integration_tests)
void _integration_test(string host, ushort port)
{
    auto conn = new NativeConnection(host, port);
}
