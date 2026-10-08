module dpq2.async.poll;

import core.time : Duration;
import dpq2.async.waiter;
import dpq2.connection : Connection;
import derelict.pq.pq;
import dpq2.connection : ConnectionException;

///
struct ConnectPoller
{
    private SocketWaiter waiter;
    private Duration pollingTimeout;

    ///
    void reset(Connection conn)
    {
        conn.resetStart();

        while (true)
        {
            if (conn.status() == CONNECTION_BAD)
                throw new ConnectionException(conn);

            auto st = conn.resetPoll();
            if (st != PGRES_POLLING_OK)
            {
                SocketWaitMode mode;

                if (st == PGRES_POLLING_READING)
                    mode = SocketWaitMode.read;
                else if (st == PGRES_POLLING_WRITING)
                    mode = SocketWaitMode.write;
                else if (st == PGRES_POLLING_FAILED)
                    throw new ConnectionException(conn);
                else
                    mode = SocketWaitMode.read;

                waiter.wait(mode, pollingTimeout);

                continue;
            }

            break;
        }
    }

    ///
    void poll(Connection conn)
    {
        while (true)
        {
            if (conn.status() == CONNECTION_BAD)
                throw new ConnectionException(conn, __FILE__, __LINE__);

            auto st = conn.poll();
            if (st != PGRES_POLLING_OK)
            {
                SocketWaitMode mode;

                if (st == PGRES_POLLING_READING)
                    mode = SocketWaitMode.read;
                else if (st == PGRES_POLLING_WRITING)
                    mode = SocketWaitMode.write;
                else if (st == PGRES_POLLING_FAILED)
                    throw new ConnectionException(conn, __FILE__, __LINE__);
                else
                    mode = SocketWaitMode.read;

                if (!waiter.wait(mode, pollingTimeout))
                    throw new PostgresClientTimeoutException(__FILE__, __LINE__);

                continue;
            }
            else
            {
                break;
            }
        }
    }
}
