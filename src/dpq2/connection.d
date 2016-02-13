module dpq2.connection;

@trusted:

import dpq2;

import std.conv: to;
import std.string: toStringz, fromStringz;
import std.exception: enforceEx;
import std.range;
import core.exception;

/*
 * Bugs: On Unix connection is not thread safe.
 * 
 * On Unix, forking a process with open libpq connections can lead
 * to unpredictable results because the parent and child processes share
 * the same sockets and operating system resources. For this reason,
 * such usage is not recommended, though doing an exec from the child
 * process to load a new executable is safe.



int PQisthreadsafe();
Returns 1 if the libpq is thread-safe and 0 if it is not.
*/

/// BaseConnection
package class BaseConnection
{
    string connString; /// Database connection parameters
    
    package PGconn* conn;
    private
    {
        bool readyForQuery = false; // connection started and not disconnect() was called

        enum ConsumeResult
        {
            PQ_CONSUME_ERROR,
            PQ_CONSUME_OK
        }
    }
    
    @property bool nonBlocking()
    {
        return PQisnonblocking(conn) == 1;
    }

    private void setNonBlocking( bool state )
    {
        if( PQsetnonblocking(conn, state ? 1 : 0 ) == -1 )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }
    
	/// Connect to DB
    void connect()
    {
        assert( !readyForQuery );
        
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if( !nonBlocking && status != CONNECTION_OK )
            throw new ConnectionException(this, __FILE__, __LINE__);
        
        readyForQuery = true;
    }

	/// Connect to DB in a nonblocking manner
    void connectStart()
    {
        assert( !readyForQuery );

        conn = PQconnectStart(cast(char*) toStringz(connString)); // TODO: wrong DerelictPQ args

        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if( status == CONNECTION_BAD )
            throw new ConnectionException(this, __FILE__, __LINE__);

        readyForQuery = true;
    }

    void resetStart()
    {
        if(PQresetStart(conn) == 0)
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    PostgresPollingStatusType poll() nothrow
    {
        assert( readyForQuery );

        return PQconnectPoll(conn);
    }

    PostgresPollingStatusType resetPoll() nothrow
    {
        assert( readyForQuery );

        return PQresetPoll(conn);
    }

    ConnStatusType status() nothrow
    {
        return PQstatus(conn);
    }

	/// Disconnect from DB
    void disconnect() nothrow
    {
        if( readyForQuery )
        {
            readyForQuery = false;
            PQfinish( conn );
            // TODO: remove readyForQuery and just use conn = null as flag
        }
    }

    void consumeInput()
    {
        assert( readyForQuery );

        const size_t r = PQconsumeInput( conn );
        if( r != ConsumeResult.PQ_CONSUME_OK ) throw new ConnectionException(this, __FILE__, __LINE__);
    }
    
    package bool flush()
    {
        assert( readyForQuery );

        auto r = PQflush(conn);
        if( r == -1 ) throw new ConnectionException(this, __FILE__, __LINE__);
        return r == 0;
    }
    
    package size_t socket()
    {
        auto r = PQsocket( conn );
        assert( r >= 0 );
        return r;
    }

    string errorMessage() const nothrow
    {
        return to!string(PQerrorMessage(cast(PGconn*) conn)); //TODO: need report to derelict pq
    }

    ~this()
    {
        disconnect();
    }

    /**
     * returns the previous notice receiver or processor function pointer, and sets the new value.
     * If you supply a null function pointer, no action is taken, but the current pointer is returned.
     */
    PQnoticeProcessor setNoticeProcessor(PQnoticeProcessor proc, void* arg) nothrow
    {
        assert( readyForQuery );

        return PQsetNoticeProcessor(conn, proc, arg);
    }

    /// Get for the next result from a sendQuery. Can return null.
    immutable(Result) getResult()
    {
        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto r = cast(immutable) PQgetResult(conn);

        if(r)
        {
            auto container = new immutable ResultContainer(r);
            return new immutable Result(container);
        }

        return null;
    }

    /// Get result from PQexec* functions or throw error if pull is empty
    package immutable(ResultContainer) createResultContainer(immutable PGresult* r) const
    {
        if(r is null) throw new ConnectionException(this, __FILE__, __LINE__);

        return new immutable ResultContainer(r);
    }

    bool isBusy() nothrow
    {
        assert( readyForQuery );

        return PQisBusy(conn) == 1;
    }

    string parameterStatus(string paramName)
    {
        assert( readyForQuery );

        auto res = PQparameterStatus(conn, cast(char*) toStringz(paramName)); //TODO: need report to derelict pq

        if(res is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        return to!string(fromStringz(res));
    }

    string escapeLiteral(string msg)
    {
        assert( readyForQuery );

        auto buf = PQescapeLiteral(conn, msg.toStringz, msg.length);

        if(buf is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        const char[] res = buf.fromStringz;

        PQfreemem(buf);

        return to!string(res);
    }

    string host() const nothrow
    {
        assert( readyForQuery );

        return to!string(PQhost(cast(PGconn*) conn).fromStringz); //TODO: need report to derelict pq
    }
}

/// Connection exception
class ConnectionException : Dpq2Exception
{
    private const BaseConnection conn;

    this(in BaseConnection c, string file, size_t line)
    {
        conn = c;

        super(conn.errorMessage(), file, line);
    }
}

void _integration_test( string connParam )
{
    assert( PQlibVersion() >= 9_0100 );

    {
        auto c = new BaseConnection;
        c.connString = connParam;

        c.connect();
        c.disconnect();

        c.connect();
        c.disconnect();

        destroy(c);
    }

    {
        bool exceptionFlag = false;
        auto c = new BaseConnection;
        c.connString = "!!!some incorrect connection string!!!";

        try c.connect();
        catch(ConnectionException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 40); // error message check
        }
        finally
            assert(exceptionFlag);
    }
}
