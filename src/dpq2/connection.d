/**
 * Represents connection to the PostgreSQL server
 *
 * Most functions is correspond to those in the documentation of Postgres:
 * $(HTTPS https://www.postgresql.org/docs/current/static/libpq.html)
 */
module dpq2.connection;

import dpq2.query;
import dpq2.args: QueryParams;
import dpq2.result;
import dpq2.exception;

import derelict.pq.pq;
import std.conv: to;
import std.string: toStringz, fromStringz;
import std.exception: enforce;
import std.range;
import std.stdio: File;
import std.socket;
import core.exception;
import core.time: Duration;

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
version(DerelictPQ_Static)
class Connection
{
    mixin ConnectionMethods;
}
else
package class Connection
{
    import dpq2.dynloader: ReferenceCounter;

    private immutable ReferenceCounter dynLoaderRefCnt;

    mixin ConnectionMethods;
}

private mixin template ConnectionMethods()
{
    package PGconn* conn;

    invariant
    {
        assert(conn !is null);
    }

    /// Makes a new connection to the database server
    this(string connString)
    {
        conn = PQconnectdb(toStringz(connString));
        version(DerelictPQ_Dynamic) dynLoaderRefCnt = ReferenceCounter(true);
        checkCreatedConnection();
    }

    /// ditto
    this(in string[string] keyValueParams)
    {
        auto a = keyValueParams.keyValToPQparamsArrays;

        conn = PQconnectdbParams(&a.keys[0], &a.vals[0], 0);
        version(DerelictPQ_Dynamic) dynLoaderRefCnt = ReferenceCounter(true);
        checkCreatedConnection();
    }

	/// Starts creation of a connection to the database server in a nonblocking manner
    this(ConnectionStart, string connString)
    {
        conn = PQconnectStart(toStringz(connString));
        version(DerelictPQ_Dynamic) dynLoaderRefCnt = ReferenceCounter(true);
        checkCreatedConnection();
    }

	/// ditto
    this(ConnectionStart, in string[string] keyValueParams)
    {
        auto a = keyValueParams.keyValToPQparamsArrays;

        conn = PQconnectStartParams(&a.keys[0], &a.vals[0], 0);
        version(DerelictPQ_Dynamic) dynLoaderRefCnt = ReferenceCounter(true);
        checkCreatedConnection();
    }

    private void checkCreatedConnection()
    {
        enforce!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if( status == CONNECTION_BAD )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    ~this()
    {
        PQfinish( conn );

        version(DerelictPQ_Dynamic) dynLoaderRefCnt.__custom_dtor();
    }

    mixin Queries;

    /// Returns the blocking status of the database connection
    bool isNonBlocking()
    {
        return PQisnonblocking(conn) == 1;
    }

    /// Sets the nonblocking status of the connection
    private void setNonBlocking(bool state)
    {
        if( PQsetnonblocking(conn, state ? 1 : 0 ) == -1 )
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    /// Begin reset the communication channel to the server, in a nonblocking manner
    ///
    /// Useful only for non-blocking operations.
    void resetStart()
    {
        if(PQresetStart(conn) == 0)
            throw new ConnectionException(this, __FILE__, __LINE__);
    }

    /// Useful only for non-blocking operations.
    PostgresPollingStatusType poll() nothrow
    {
        assert(conn);

        return PQconnectPoll(conn);
    }

    /// Useful only for non-blocking operations.
    PostgresPollingStatusType resetPoll() nothrow
    {
        assert(conn);

        return PQresetPoll(conn);
    }

    /// Returns the status of the connection
    ConnStatusType status() nothrow
    {
        return PQstatus(conn);
    }

    /**
        Returns the current in-transaction status of the server.
        The status can be:
            * PQTRANS_IDLE    - currently idle
            * PQTRANS_ACTIVE  - a command is in progress (reported only when a query has been sent to the server and not yet completed)
            * PQTRANS_INTRANS - idle, in a valid transaction block
            * PQTRANS_INERROR - idle, in a failed transaction block
            * PQTRANS_UNKNOWN - reported if the connection is bad
     */
    PGTransactionStatusType transactionStatus() nothrow
    {
        return PQtransactionStatus(conn);
    }

    /// If input is available from the server, consume it
    ///
    /// Useful only for non-blocking operations.
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

    /// Obtains the file descriptor number of the connection socket to the server
    int posixSocket()
    {
        int r = PQsocket(conn);

        if(r == -1)
            throw new ConnectionException(this, __FILE__, __LINE__);

        return r;
    }

    /// Obtains duplicate file descriptor number of the connection socket to the server
    socket_t posixSocketDuplicate()
    {
        version(Windows)
        {
            assert(false, "FIXME: implement socket duplication");
        }
        else // Posix OS
        {
            import core.sys.posix.unistd: dup;

            return cast(socket_t) dup(cast(socket_t) posixSocket);
        }
    }

    /// Obtains std.socket.Socket of the connection to the server
    ///
    /// Due to a limitation of Socket actually for the Socket creation
    /// duplicate of internal posix socket will be used.
    Socket socket()
    {
        return new Socket(posixSocketDuplicate, AddressFamily.UNSPEC);
    }

    /// Returns the error message most recently generated by an operation on the connection
    string errorMessage() const nothrow
    {
        return PQerrorMessage(conn).to!string;
    }

    /**
     * Sets or examines the current notice processor
     *
     * Returns the previous notice receiver or processor function pointer, and sets the new value.
     * If you supply a null function pointer, no action is taken, but the current pointer is returned.
     */
    PQnoticeProcessor setNoticeProcessor(PQnoticeProcessor proc, void* arg) nothrow
    {
        assert(conn);

        return PQsetNoticeProcessor(conn, proc, arg);
    }

    /// Get next result after sending a non-blocking commands. Can return null.
    ///
    /// Useful only for non-blocking operations.
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

    /// Get result after PQexec* functions or throw exception if pull is empty
    package immutable(ResultContainer) createResultContainer(immutable PGresult* r) const
    {
        if(r is null) throw new ConnectionException(this, __FILE__, __LINE__);

        return new immutable ResultContainer(r);
    }

    /// Select single-row mode for the currently-executing query
    bool setSingleRowMode()
    {
        return PQsetSingleRowMode(conn) == 1;
    }

    /**
     Try to cancel query

     If the cancellation is effective, the current command will
     terminate early and return an error result or exception. If the
     cancellation will fails (say, because the server was already done
     processing the command) there will be no visible result at all.
    */
    void cancel()
    {
        auto c = new Cancellation(this);
        c.doCancel;
    }

    ///
    bool isBusy() nothrow
    {
        assert(conn);

        return PQisBusy(conn) == 1;
    }

    ///
    string parameterStatus(string paramName)
    {
        assert(conn);

        auto res = PQparameterStatus(conn, toStringz(paramName));

        if(res is null)
            throw new ConnectionException(this, __FILE__, __LINE__);

        return to!string(fromStringz(res));
    }

    ///
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

    ///
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

    ///
    string dbName() const nothrow
    {
        assert(conn);

        return PQdb(conn).fromStringz.to!string;
    }

    ///
    string host() const nothrow
    {
        assert(conn);

        return PQhost(conn).fromStringz.to!string;
    }

    ///
    int protocolVersion() const nothrow
    {
        assert(conn);

        return PQprotocolVersion(conn);
    }

    ///
    int serverVersion() const nothrow
    {
        assert(conn);

        return PQserverVersion(conn);
    }

    ///
    void trace(ref File stream)
    {
        PQtrace(conn, stream.getFP);
    }

    ///
    void untrace()
    {
        PQuntrace(conn);
    }

    ///
    void setClientEncoding(string encoding)
    {
        if(PQsetClientEncoding(conn, encoding.toStringz) != 0)
            throw new ConnectionException(this, __FILE__, __LINE__);
    }
}

private auto keyValToPQparamsArrays(in string[string] keyValueParams)
{
    static struct PQparamsArrays
    {
        immutable(char)*[] keys;
        immutable(char)*[] vals;
    }

    PQparamsArrays a;
    a.keys.length = keyValueParams.length + 1;
    a.vals.length = keyValueParams.length + 1;

    size_t i;
    foreach(e; keyValueParams.byKeyValue)
    {
        a.keys[i] = e.key.toStringz;
        a.vals[i] = e.value.toStringz;

        i++;
    }

    assert(i == keyValueParams.length);

    return a;
}

/// Check connection options in the provided connection string
///
/// Throws exception if connection string isn't passes check.
void connStringCheck(string connString)
{
    char* errmsg = null;
    PQconninfoOption* r = PQconninfoParse(connString.toStringz, &errmsg);

    if(r is null)
    {
        enforce!OutOfMemoryError(errmsg, "Unable to allocate libpq conninfo data");
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

/// Represents query cancellation process
class Cancellation
{
    private PGcancel* cancel;

    ///
    this(Connection c)
    {
        cancel = PQgetCancel(c.conn);

        if(cancel is null)
            throw new ConnectionException(c, __FILE__, __LINE__);
    }

    ///
    ~this()
    {
        PQfreeCancel(cancel);
    }

    /**
     Requests that the server abandon processing of the current command

     Throws exception if cancel request was not successfully dispatched.

     Successful dispatch is no guarantee that the request will have any
     effect, however. If the cancellation is effective, the current
     command will terminate early and return an error result
     (exception). If the cancellation fails (say, because the server
     was already done processing the command), then there will be no
     visible result at all.
    */
    void doCancel()
    {
        char[256] errbuf;
        auto res = PQcancel(cancel, errbuf.ptr, errbuf.length);

        if(res != 1)
            throw new CancellationException(to!string(errbuf.ptr.fromStringz), __FILE__, __LINE__);
    }
}

///
class CancellationException : Dpq2Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Connection exception
class ConnectionException : Dpq2Exception
{
    this(in Connection c, string file = __FILE__, size_t line = __LINE__)
    {
        super(c.errorMessage(), file, line);
    }

    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

version (integration_tests)
Connection createTestConn(T...)(T params)
{
    version(DerelictPQ_Static)
        auto c = new Connection(params);
    else
    {
        import dpq2.dynloader: connFactory;

        Connection c = connFactory.createConnection(params);
    }

    return c;
}

version (integration_tests)
void _integration_test( string connParam )
{
    {
        debug import std.experimental.logger;

        auto c = createTestConn(connParam);

        assert( PQlibVersion() >= 9_0100 );

        auto dbname = c.dbName();
        auto pver = c.protocolVersion();
        auto sver = c.serverVersion();

        debug
        {
            trace("DB name: ", dbname);
            trace("Protocol version: ", pver);
            trace("Server version: ", sver);
        }

        destroy(c);
    }

    {
        bool exceptionFlag = false;

        try
            auto c = createTestConn(ConnectionStart(), "!!!some incorrect connection string!!!");
        catch(ConnectionException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 40); // error message check
        }
        finally
            assert(exceptionFlag);
    }

    {
        auto c = createTestConn(connParam);

        assert(c.escapeLiteral("abc'def") == "'abc''def'");
        assert(c.escapeIdentifier("abc'def") == "\"abc'def\"");

        c.setClientEncoding("WIN866");
        assert(c.exec("show client_encoding")[0][0].as!string == "WIN866");
    }

    {
        auto c = createTestConn(connParam);

        assert(c.transactionStatus == PQTRANS_IDLE);

        c.exec("BEGIN");
        assert(c.transactionStatus == PQTRANS_INTRANS);

        try c.exec("DISCARD ALL");
        catch (Exception) {}
        assert(c.transactionStatus == PQTRANS_INERROR);

        c.exec("ROLLBACK");
        assert(c.transactionStatus == PQTRANS_IDLE);
    }

    {
        import std.exception: assertThrown;

        string[string] kv;
        kv["host"] = "wrong-host";
        kv["dbname"] = "wrong-db-name";

        assertThrown!ConnectionException(createTestConn(kv));
        assertThrown!ConnectionException(createTestConn(ConnectionStart(), kv));
    }
}
