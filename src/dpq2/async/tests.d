module dpq2.async.tests;

version(AsyncIntegrationTests):

import core.time : Duration, seconds, msecs;
import std.conv : to;
import std.exception : assertThrown;

import dpq2.async.connection : AsyncConnection;
import dpq2.async.waiter : PostgresClientTimeoutException;
import dpq2.args : QueryParams;
import dpq2.value : ValueFormat;
import dpq2.result : Row, ResponseException;
import dpq2.oids : OidType;
import dpq2.conv.to_d_types : as;

/**
 * Base (template) part of the async integration tests.
 *
 * The SocketWaiter implementation is not supplied by dpq2 itself (it must not
 * depend on any event loop), so the waiter factory is passed in as a template
 * argument. dpq2 therefore gains no new dependency; the tests are only
 * instantiated by an external consumer.
 *
 * Params:
 *      waiterFactory  = creates a SocketWaiter bound to a socket descriptor,
 *                       e.g. (int fd) => new VibeSocketWaiter(fd)
 *      runDetachedTask = schedules the given delegate as a detached task and
 *                       returns a future which is joined to await completion
 *      sleep          = suspends the current task for the given duration
 *      connParam      = libpq connection string
 */
void _integration_test(alias waiterFactory, alias runDetachedTask, alias sleep)(string connParam)
{
    auto conn = new AsyncConnection(
        connParam,
        (int fd) => waiterFactory(fd),
        5.seconds,
        30.seconds
    );

    {
        auto res = conn.exec(
            "SELECT 123::integer, 567::integer, 'asd fgh'::text",
            ValueFormat.BINARY
        );

        assert(res.getAnswer[0][1].as!int == 567);
    }

    {
        // Row-by-row result receiving
        int[] res;

        conn.execStatementRbR(
            `SELECT generate_series(0, 3) as i, pg_sleep(0.2)`,
            (immutable(Row) r)
            {
                res ~= r[0].as!int;
            }
        );

        assert(res.length == 4);
    }

    {
        // Row-by-row result receiving: error while receiving
        size_t rowCounter;

        QueryParams p;
        p.sqlCommand =
            `SELECT 1.0 / (generate_series(1, 100000) % 80000)`; // division by zero error at generate_series=80000

        bool assertThrown;

        try
            conn.execStatementRbR(p,
                (immutable(Row) r)
                {
                    rowCounter++;
                }
            );
        catch(ResponseException) // catches ERROR:  division by zero
            assertThrown = true;

        assert(assertThrown);
        assert(rowCounter > 0);
    }

    {
        QueryParams p;
        p.sqlCommand = `SELECT 123`;

        auto res = conn.execParams(p);

        assert(res.length == 1);
        assert(res[0][0].as!int == 123);
    }

    {
        conn.prepareEx("stmnt_name", "SELECT 123::integer UNION SELECT 456::integer");

        bool throwFlag = false;

        try
            conn.prepareEx("wrong_stmnt", "WRONG SQL STATEMENT");
        catch(ResponseException)
            throwFlag = true;

        assert(throwFlag);
    }

    {
        auto a = conn.describePrepared("stmnt_name");

        assert(a.nParams == 0);
        assert(a.OID(0) == OidType.Int4);
    }

    {
        QueryParams p;
        p.preparedStatementName = "stmnt_name";

        auto r = conn.execPrepared(p);

        assert(r.getAnswer[0][0].as!int == 123);
    }

    {
        QueryParams p;
        p.preparedStatementName = "stmnt_name";

        int[] res;

        conn.execPreparedRbR(
            p,
            (immutable(Row) r)
            {
                res ~= r.oneCell.as!int;
            }
        );

        assert(res.length == 2, res.to!string);
        assert(res[0] == 123);
        assert(res[1] == 456);
    }

    {
        assert(conn.escapeIdentifier("abc") == "\"abc\"");
    }

    {
        // Timeouts test
        conn.exec(`set statement_timeout to '5s'`);

        QueryParams p;
        p.sqlCommand = `SELECT pg_sleep_for('1 minute')`;

        assertThrown!ResponseException(
            conn.execParams(p)
        );

        // Internal statement timeout check
        const savedRequestTimeout = conn.requestTimeout;
        conn.requestTimeout = 5.seconds;

        conn.reset();

        assertThrown!PostgresClientTimeoutException(
            conn.execParams(p)
        );

        conn.requestTimeout = savedRequestTimeout;
    }

    {
        // Notify test.
        // LISTEN + waitForNotify run in a detached task, the current task
        // sends NOTIFY and then joins the listener future.
        string ntfName;
        string ntfExtra;

        auto listener = runDetachedTask(
        {
            auto listenerConn = new AsyncConnection(
                connParam,
                (int fd) => waiterFactory(fd),
                5.seconds,
                30.seconds
            );

            listenerConn.exec("LISTEN foo");

            auto ntf = listenerConn.waitForNotify(10.seconds);
            assert(ntf !is null);

            ntfName = ntf.name;
            ntfExtra = ntf.extra;
        });

        sleep(100.msecs);
        conn.exec("NOTIFY foo, 'bar'");

        listener.join();

        assert(ntfName == "foo");
        assert(ntfExtra == "bar");
    }

    {
        // Request cancellation test.
        // The long query is only submitted (not awaited), so cancel() can be
        // issued from the same thread before consuming the result.
        conn.sendQuery(`SELECT pg_sleep_for('1 minute')`);

        // Give the server a moment to actually start executing the query,
        // otherwise the cancel request may race ahead of it and have no effect.
        sleep(200.msecs);

        conn.cancel();

        bool canceled;
        try
        {
            while(conn.getResult(Duration.max) !is null) {}
            assert(conn.getResult(Duration.max) is null);
        }
        catch(ResponseException) // ERROR: canceling statement due to user request
            canceled = true;

        assert(canceled);
    }
}
