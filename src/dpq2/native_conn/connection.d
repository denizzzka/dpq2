module dpq2.native_conn.connection;

import std.socket;
import std.datetime: Duration;
import dpq2.connection: ConnectionException;
import derelict.pq.types: ConnStatusType;

class NativeConnection
{
    private Socket socket;
    private Address addr;
    private ConnStatusType status;

    /// Starts creation of a connection to the database server in a nonblocking manner
    this(string host, ushort port)
    {
        socket = new TcpSocket();
        socket.blocking = false;
        addr = new InternetAddress(host, port);

        startConnect();
    }

    private void startConnect()
    {
        socket.connect(addr);
    }

    void waitEndOfRead(in Duration timeout)
    {
        //TODO: make waiting independent from available event library
        import vibe.core.core;

        version(Posix)
        {
            import core.sys.posix.fcntl;
            assert((fcntl(socket.handle, F_GETFL, 0) & O_NONBLOCK), "Socket assumed to be non-blocking already");
        }

        auto event = createFileDescriptorEvent(socket.handle, FileDescriptorEvent.Trigger.read);

        do
        {
            if(!event.wait(timeout))
                throw new ConnectionException("Connection error", __FILE__, __LINE__);

            //~ consumeInput();
        }
        while(true); // (this.isBusy); // wait until PQgetresult won't block anymore
    }
}

version (integration_tests)
void _integration_test(string host, ushort port)
{
    import std.datetime;

    auto conn = new NativeConnection(host, port);
    //~ conn.waitEndOfRead(1.seconds);
}
