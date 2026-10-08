module dpq2.async.connection;

import dpq2.async.waiter;
import dpq2.async.poll;
import dpq2.async.cancellation : CancellationSupport;
import dpq2.async.queries : Queries;

import core.time : Duration, dur;
import dpq2.connection : Connection, ConnectionException;
import dpq2.result : Result, Notify, Row;
import derelict.pq.pq : CONNECTION_BAD, PGRES_SINGLE_TUPLE;
import std.exception : enforce;
import std.conv : to;

///
private class AsyncHelper
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
    Duration pollingTimeout; /// Timeout for use in polling loops etc
    Duration requestTimeout; /// Timeout for queries etc

    private AsyncHelper helper;
    private SocketWaiterFactory waiterFactory;

    ///
    this(string connString, SocketWaiterFactory waiterFactory, Duration pollingTimeout, Duration requestTimeout)
    {
        super(connString);
        this.pollingTimeout = pollingTimeout;
        this.requestTimeout = requestTimeout;
        this.waiterFactory = waiterFactory;
        this.helper = new AsyncHelper(waiterFactory(posixSocket), pollingTimeout, requestTimeout);
    }

    mixin CancellationSupport;
    mixin Queries;

    ///
    void reset()
    {
        helper.reset(this);
    }

    ///
    void setSingleRowModeEx()
    {
        if(setSingleRowMode() != 1)
            throw new ConnectionException("PQsetSingleRowMode failed");
    }

    ///
    immutable(Result) getResult(in Duration timeout)
    {
        if(isBusy)
            waitEndOfReadAndConsume(timeout);

        return super.getResult();
    }

    ///
    protected immutable(Result) runStatementBlockingManner(void delegate() sendsStatementDg)
    {
        immutable(Result)[] res;

        runStatementBlockingMannerWithMultipleResults(sendsStatementDg, (r){ res ~= r; }, false);

        enforce(res.length == 1, "Simple query without row-by-row mode can return only one Result instance, not " ~ res.length.to!string);

        return res[0];
    }

    ///
    protected void runStatementBlockingMannerWithMultipleResults(void delegate() sendsStatementDg, void delegate(immutable(Result)) processResult, bool isRowByRowMode)
    {
        doQuery(()
            {
                sendsStatementDg();

                if(isRowByRowMode)
                    setSingleRowModeEx();

                scope (failure)
                {
                    if(isRowByRowMode)
                    {
                        while(super.getResult() !is null) {} // autoclean of results queue
                    }
                }

                scope (exit)
                {
                    consumeInput(); // TODO: redundant call (also called in waitEndOfReadAndConsume) - can be moved into catch block?

                    while(true)
                    {
                        auto r = super.getResult();

                        /*
                         I am trying to check connection status with PostgreSQL server
                         with PQstatus and it always always return CONNECTION_OK even
                         when the cable to the server is unplugged.
                                                    – user1972556 (stackoverflow.com)

                         ...the idea of testing connections is fairly silly, since the
                         connection might die between when you test it and when you run
                         your "real" query. Don't test connections, just use them, and
                         if they fail be prepared to retry everything since you opened
                         the transaction. – Craig Ringer Jan 14 '13 at 2:59
                         */
                        if(status == CONNECTION_BAD)
                            throw new ConnectionException(this, __FILE__, __LINE__);

                        if(r is null) break;

                        processResult(r);
                    }
                }

                try
                {
                    waitEndOfReadAndConsume(requestTimeout);
                }
                catch (PostgresClientTimeoutException e)
                {
                    reset();
                    throw e;
                }
            }
        );
    }

    ///
    protected void runStatementWithRowByRowResult(void delegate() sendsStatementDg, void delegate(immutable(Row)) answerRowProcessDg)
    {
        runStatementBlockingMannerWithMultipleResults(
                sendsStatementDg,
                (r)
                {
                    auto answer = r.getAnswer;

                    enforce(answer.length <= 1, `0 or 1 rows can be received, not `~answer.length.to!string);

                    if(answer.length == 1)
                    {
                        enforce(r.status == PGRES_SINGLE_TUPLE, `Wrong result status: `~r.status.to!string);

                        answerRowProcessDg(answer[0]);
                    }
                },
                true
            );
    }

    /**
     * Non blocking method to wait for next notification.
     *
     * Params:
     *      timeout = maximal duration to wait for the new Notify to be received
     *
     * Returns: New Notify or null when no other notification is available or timeout occurs.
     * Throws: ConnectionException on connection failure
     */
    Notify waitForNotify(in Duration timeout = Duration.max)
    {
        // try read available
        auto ntf = getNextNotify();
        if(ntf !is null) return ntf;

        // wait for next one
        try waitEndOfReadAndConsume(timeout);
        catch (PostgresClientTimeoutException) return null;
        return getNextNotify();
    }

    ///
    private void waitEndOfReadAndConsume(Duration timeout)
    {
        helper.waitEndOfReadAndConsume(this, timeout);
    }

    ///
    protected void doQuery(void delegate() doesQueryAndCollectsResults)
    {
        helper.poll(this);
        doesQueryAndCollectsResults();
    }
}
