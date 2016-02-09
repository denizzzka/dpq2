module dpq2.connection;

@trusted:

public import derelict.pq.pq:
    PostgresPollingStatusType,
    ConnStatusType,
    PQnoticeProcessor;

import derelict.pq.pq;
import dpq2.answer: Answer;
import std.conv: to;
import std.string: toStringz;
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
        debug bool readyForQuery; // connection started and not disconnect() was called
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
            throw new ConnException(this, __FILE__, __LINE__);
    }
    
	/// Connect to DB
    void connect()
    {
        assert( !readyForQuery );
        
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if( !nonBlocking && status != CONNECTION_OK )
            throw new ConnException(this, __FILE__, __LINE__);
        
        readyForQuery = true;
    }

	/// Connect to DB in a nonblocking manner
    void connectNonblockingStart()
    {
        assert( !readyForQuery );

        conn = PQconnectStart(cast(char*) toStringz(connString)); // TODO: wrong DerelictPQ args

        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");

        if( status == CONNECTION_BAD )
            throw new ConnException(this, __FILE__, __LINE__);

        readyForQuery = true;
    }

    PostgresPollingStatusType poll()
    {
        assert( readyForQuery );

        return PQconnectPoll(conn);
    }

    ConnStatusType status()
    {
        return PQstatus(conn);
    }

	/// Disconnect from DB
    void disconnect()
    {
        if( readyForQuery )
        {
            readyForQuery = false;
            PQfinish( conn );
            // TODO: remove readyForQuery and just use conn = null as flag
        }
    }

    package void consumeInput()
    {
        assert( readyForQuery );

        const size_t r = PQconsumeInput( conn );
        if( r != ConsumeResult.PQ_CONSUME_OK ) throw new ConnException(this, __FILE__, __LINE__);
    }
    
    package bool flush()
    {
        assert( readyForQuery );

        auto r = PQflush(conn);
        if( r == -1 ) throw new ConnException(this, __FILE__, __LINE__);
        return r == 0;
    }
    
    package size_t socket()
    {
        auto r = PQsocket( conn );
        assert( r >= 0 );
        return r;
    }

    package string errorMessage()
    {
        return to!(string)(PQerrorMessage(conn));
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

    /// Waits for the next result from a sendQuery
    package Answer getResult()
    {
        Answer res;

        auto r = PQgetResult( conn );

        if(r)
        {
            res = new Answer(r);
            res.checkAnswerForErrors(); // It is important to do a separate check because of Answer ctor is nothrow
        }

        return res;
    }
}

/// Connection exception
class ConnException : Dpq2Exception
{
    private BaseConnection conn;

    this(BaseConnection c, string file, size_t line)
    {
        conn = c;

        super(conn.errorMessage(), file, line);
    }
}

class Dpq2Exception : Exception
{
    this(string msg, string file, size_t line)
    {
        super(msg, file, line);
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
        catch(ConnException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 40); // error message check
        }
        finally
            assert(exceptionFlag);
    }
}
