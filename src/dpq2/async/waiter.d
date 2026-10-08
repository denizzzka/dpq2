module dpq2.async.waiter;

import core.time : Duration;
import dpq2.connection : Connection, ConnectionException;

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
        while (conn.isBusy)
        {
            if (!waiter.wait(SocketWaitMode.read, timeout))
                throw new AsyncTimeoutException("Connection timeout while waiting for result");
            conn.consumeInput();
        }
    }
}

///
public class AsyncTimeoutException : ConnectionException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }

    this(string msg)
    {
        super(msg);
    }
}
