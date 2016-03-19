module dpq2.connection;

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

/// dumb flag for Connection ctor parametrization
struct ConnectionStart {};

/// Connection
class Connection
{
    //string connString; /// Database connection parameters
    package PGconn* conn;

    invariant
    {
        assert(conn !is null);
    }

    this(string connString)
    {
        conn = PQconnectdb(toStringz(connString));

        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if(status != CONNECTION_OK)
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

	/// Connect to DB in a nonblocking manner
    this(ConnectionStart, string connString)
    {
        conn = PQconnectStart(cast(char*) toStringz(connString)); // TODO: wrong DerelictPQ args

        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if( status == CONNECTION_BAD )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    ~this()
    {
        PQfinish( conn );
    }

    mixin Queries;

    @property bool isNonBlocking()
    {
        return PQisnonblocking(conn) == 1;
    }

    private void setNonBlocking( bool state )
    {
        if( PQsetnonblocking(conn, state ? 1 : 0 ) == -1 )
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

    int posixSocket()
    {
        int r = PQsocket(conn);

        if(r == -1)
            throw new ConnectionException(this, __FILE__, __LINE__);

        return r;
    }

    Socket socket()
    {
        import core.sys.posix.unistd: dup;

        socket_t s = cast(socket_t) dup(cast(socket_t) posixSocket);
        return new Socket(s, AddressFamily.UNSPEC);
    }

    string errorMessage() const nothrow
    {
        return to!string(PQerrorMessage(cast(PGconn*) conn)); //TODO: need report to derelict pq
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

        string res = buf.fromStringz.to!string;

        PQfreemem(buf);

        return res;
    }

    string escapeIdentifier(string msg)
    {
        assert(conn);

        auto buf = PQescapeIdentifier(conn, msg.toStringz, msg.length);

        if(buf is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        string res = buf.fromStringz.to!string;

        PQfreemem(buf);

        return res;
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

    void setClientEncoding(string encoding)
    {
        if(PQsetClientEncoding(conn, cast(char*) encoding.toStringz) != 0) //TODO: need report to derelict pq
            throw new ConnectionException(this, __FILE__, __LINE__);
    }
}

void connStringCheck(string connString)
{
    char* errmsg = null;
    PQconninfoOption* r = PQconninfoParse(cast(char*) connString.toStringz, &errmsg); //TODO: need report to derelict pq

    if(r is null)
    {
        enforceEx!OutOfMemoryError(errmsg, "Unable to allocate libpq conninfo data");
    }
    else
    {
        PQconninfoFree(r);
    }

    if(errmsg !is null)
    {
        string s = errmsg.fromStringz.to!string;
        PQfreemem(cast(void*) errmsg);

        throw new ConnectionException(s, __FILE__, __LINE__);
    }
}

unittest
{
    connStringCheck("dbname=postgres user=postgres");

    {
        bool raised = false;

        try
            connStringCheck("wrong conninfo string");
        catch(ConnectionException e)
            raised = true;

        assert(raised);
    }
}

/// Doing canceling queries in progress
class Cancellation
{
    private PGcancel* cancel;

    this(Connection c)
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
    this(in Connection c, string file, size_t line)
    {
        super(c.errorMessage(), file, line);
    }

    this(string msg, string file, size_t line)
    {
        super(msg, file, line);
    }
}

void _integration_test( string connParam )
{
    assert( PQlibVersion() >= 9_0100 );

    {
        auto c = new Connection(connParam);

        destroy(c);
    }

    {
        bool exceptionFlag = false;

        try
            auto c = new Connection(ConnectionStart(), "!!!some incorrect connection string!!!");
        catch(ConnectionException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 40); // error message check
        }
        finally
            assert(exceptionFlag);
    }

    {
        auto c = new Connection(connParam);

        assert(c.escapeLiteral("abc'def") == "'abc''def'");
        assert(c.escapeIdentifier("abc'def") == "\"abc'def\"");

        c.setClientEncoding("WIN866");
        assert(c.exec("show client_encoding")[0][0].as!string == "WIN866");
    }
}
