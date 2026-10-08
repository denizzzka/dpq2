module dpq2.async.cancellation;

import dpq2.cancellation;

///
class CancellationTimeoutException : CancellationException
{
    this(string file = __FILE__, size_t line = __LINE__)
    {
        super("Exceeded cancellation time limit", file, line);
    }
}

/**
 * Adds asynchronous query cancellation to a Connection.
 */
package mixin template CancellationSupport()
{
    import core.time : Duration;
    import dpq2.async.waiter : SocketWaitMode;
    import dpq2.cancellation : Cancellation, CancellationException;
    import derelict.pq.pq : CONNECTION_BAD, PGRES_POLLING_OK, PGRES_POLLING_FAILED, PGRES_POLLING_READING;

    /// Requests that the server abandons processing of the current command
    void cancelRequest(Duration timeout)
    {
        auto c = new Cancellation(this);
        c.start;

        auto waiter = waiterFactory(c.socket);

        while(true)
        {
            if(c.status == CONNECTION_BAD)
                throw new CancellationException(c.errorMessage);

            const r = c.poll;

            if(r == PGRES_POLLING_OK)
                break;
            else if(r == PGRES_POLLING_FAILED)
                throw new CancellationException(c.errorMessage);
            else if(r == PGRES_POLLING_READING)
            {
                // On success cancellation socket will be closed without any
                // data receive and wait() will return false. So there is no
                // point in checking whether wait() was executed successfully
                waiter.wait(SocketWaitMode.read, timeout);
            }

            continue;
        }
    }
}