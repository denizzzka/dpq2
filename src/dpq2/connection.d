module dpq2.connection;

@trusted:

import dpq2;

import std.conv: to;
import std.string: toStringz, fromStringz;
import std.exception: enforceEx;
import std.range;
import std.stdio: File;
import std.socket;
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

    @property bool isNonBlocking()
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
        assert(!conn);
        
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if( !isNonBlocking && status != CONNECTION_OK )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

	/// Connect to DB in a nonblocking manner
    void connectStart()
    {
        conn = PQconnectStart(cast(char*) toStringz(connString)); // TODO: wrong DerelictPQ args

        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if( status == CONNECTION_BAD )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    void resetStart()
    {
        if(PQresetStart(conn) == 0)
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    PostgresPollingStatusType poll() nothrow
    {
        assert(conn);

        return PQconnectPoll(conn);
    }

    PostgresPollingStatusType resetPoll() nothrow
    {
        assert(conn);

        return PQresetPoll(conn);
    }

    ConnStatusType status() nothrow
    {
        return PQstatus(conn);
    }

	/// Disconnect from DB
    void disconnect() nothrow
    {
        PQfinish( conn );
        conn = null;
    }

    void consumeInput()
    {
        assert(conn);

        const size_t r = PQconsumeInput( conn );
        if( r != 1 ) throw new ConnectionException(this, __FILE__, __LINE__);
    }
    
    package bool flush()
    {
        assert(conn);

        auto r = PQflush(conn);
        if( r == -1 ) throw new ConnectionException(this, __FILE__, __LINE__);
        return r == 0;
    }

    Socket socket()
    {
        import core.sys.posix.unistd: dup;

        auto r = PQsocket(conn);

        if(r == -1)
            throw new ConnectionException(this, __FILE__, __LINE__);

        socket_t socket = cast(socket_t) r;
        socket_t duplicate = cast(socket_t) dup(socket);

        return new Socket(duplicate, AddressFamily.UNSPEC);
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
        assert(conn);

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

    bool setSingleRowMode()
    {
        return PQsetSingleRowMode(conn) == 1;
    }

    void cancel()
    {
        auto c = new Cancellation(this);
        c.doCancel;
    }

    bool isBusy() nothrow
    {
        assert(conn);

        return PQisBusy(conn) == 1;
    }

    string parameterStatus(string paramName)
    {
        assert(conn);

        auto res = PQparameterStatus(conn, cast(char*) toStringz(paramName)); //TODO: need report to derelict pq

        if(res is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        return to!string(fromStringz(res));
    }

    string escapeLiteral(string msg)
    {
        assert(conn);

        auto buf = PQescapeLiteral(conn, msg.toStringz, msg.length);

        if(buf is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        const char[] res = buf.fromStringz;

        PQfreemem(buf);

        return to!string(res);
    }

    string host() const nothrow
    {
        assert(conn);

        return to!string(PQhost(cast(PGconn*) conn).fromStringz); //TODO: need report to derelict pq
    }

    void trace(ref File stream)
    {
        PQtrace(conn, stream.getFP);
    }

    void untrace()
    {
        PQuntrace(conn);
    }
}

/// Doing canceling queries in progress
class Cancellation
{
    private PGcancel* cancel;

    this(BaseConnection c)
    {
        cancel = PQgetCancel(c.conn);

        if(cancel is null)
            throw new ConnectionException(c, __FILE__, __LINE__);
    }

    ~this()
    {
        PQfreeCancel(cancel);
    }

    void doCancel()
    {
        char[256] errbuf;
        auto res = PQcancel(cancel, errbuf.ptr, errbuf.length);

        if(res != 1)
            throw new CancellationException(to!string(errbuf.ptr.fromStringz), __FILE__, __LINE__);
    }
}

class CancellationException : Dpq2Exception
{
    this(string msg, string file, size_t line)
    {
        super(msg, file, line);
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
