module dpq2.async.connection;

import dpq2.async.waiter;
import dpq2.async.poll;

import core.time : Duration;
import dpq2.connection : Connection;
import derelict.pq.pq : PostgresPollingStatusType;

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

///
class AsyncConnection : Connection
{
    private AsyncHelper helper;
    private Duration pollingTimeout;
    private Duration requestTimeout;

    ///
    this(string connString, SocketWaiter waiter, Duration pollingTimeout, Duration requestTimeout)
    {
        super(connString);
        this.helper = new AsyncHelper(waiter, pollingTimeout, requestTimeout);
        this.pollingTimeout = pollingTimeout;
        this.requestTimeout = requestTimeout;
    }

    ///
    protected void doReset()
    {
        helper.reset(this);
    }

    ///
    protected void doPoll()
    {
        helper.poll(this);
    }

    ///
    protected void waitEndOfReadAndConsume()
    {
        helper.waitEndOfReadAndConsume(this, requestTimeout);
    }

    ///
    protected void waitEndOfReadAndConsume(Duration timeout)
    {
        helper.waitEndOfReadAndConsume(this, timeout);
    }

    ///
    protected void doQuery(void delegate() doesQueryAndCollectsResults)
    {
        doPoll();
        doesQueryAndCollectsResults();
    }
}
