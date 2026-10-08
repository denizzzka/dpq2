module dpq2.async.connection;

import dpq2.async.waiter;
import dpq2.async.poll;

import core.time : Duration;
import dpq2.connection : Connection;

///
class AsyncHelper
{
    private SocketWaiter waiter;
    private ConnectPoller poller;
    private ResultWaiter resultWaiter;

    ///
    this(SocketWaiter waiter, Duration pollingTimeout, Duration requestTimeout)
    {
        this.waiter = waiter;
        this.poller = ConnectPoller(waiter, pollingTimeout);
        this.resultWaiter = ResultWaiter(waiter, requestTimeout);
    }

    ///
    void reset(Connection conn)
    {
        poller.reset(conn);
    }

    ///
    void poll(Connection conn)
    {
        poller.poll(conn);
    }

    ///
    void waitEndOfReadAndConsume(Connection conn)
    {
        resultWaiter.waitEndOfReadAndConsume(conn);
    }

    ///
    void waitEndOfReadAndConsume(Connection conn, Duration timeout)
    {
        resultWaiter.waitEndOfReadAndConsume(conn, timeout);
    }
}
