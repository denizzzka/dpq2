///
module dpq2.native_conn.connection;

import dpq2.native_conn.internal.socket;
import std.datetime: Duration;
import dpq2.connection: ConnectionException;
import derelict.pq.types: ConnStatusType;
import std.array: Appender;

///
struct ConnParams
{
    public string host = "localhost"; /// Host to connect to
    public ushort port = 5432; /// Port to connect to
    public string username = "postgres"; ///
    public string password; ///
    public string dbname = "postgres"; /// Database to connect to
}

///
class NativeConnection
{
    private ConnParams connParams;
    private Socket socket;
    private ConnStatusType status;

    /// Parameters recevied from
    /// the backend.
    public string[string] parameters;

    /// message construction buffer
    private Appender!(ubyte[]) msgBuf;

    /// Starts creation of a connection to the database server in a nonblocking manner
    this(ConnParams params)
    {
        connParams = params;

        startConnect();
    }

    private void startConnect()
    {
        socket.connect(connParams.host, connParams.port);
    }
}

version (integration_tests)
void _integration_test(string host, ushort port)
{
    import std.datetime;

    ConnParams params = { host: host, port: port };
    auto conn = new NativeConnection(params);
}
