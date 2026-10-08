module dpq2.async.waiter;

import core.time : Duration;
import dpq2.connection : Connection;
import dpq2.exception : Dpq2Exception;

public enum SocketWaitMode
{
    read,      /// wait for socket to become readable
    write,     /// wait for socket to become writable
    readWrite  /// wait for either readability or writability
}

public interface SocketWaiter
{
    /// Returns true if socket became ready before timeout, false on timeout
    bool wait(SocketWaitMode mode, Duration timeout);
}

/// Creates a SocketWaiter bound to the given socket descriptor
public alias SocketWaiterFactory = SocketWaiter delegate(int socket);

///
struct ResultWaiter
{
    private SocketWaiter waiter;
    private Duration timeout;

    ///
    void waitEndOfReadAndConsume(Connection conn)
    {
        waitEndOfReadAndConsume(conn, timeout);
    }

    ///
    void waitEndOfReadAndConsume(Connection conn, Duration timeout)
    {
        do
        {
            if(!waiter.wait(SocketWaitMode.read, timeout))
                throw new PostgresClientTimeoutException(__FILE__, __LINE__);
            conn.consumeInput();
        }
        while(conn.isBusy);
    }
}

///
class PostgresClientTimeoutException : Dpq2Exception
{
    this(string file = __FILE__, size_t line = __LINE__)
    {
        this("Exceeded query time limit", file, line);
    }

    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}
