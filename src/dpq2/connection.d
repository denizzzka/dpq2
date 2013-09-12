
module dpq2.connection;
@trusted:

version(BINDINGS_DYNAMIC)
{
    import derelict.pq.pq;
}
else
{
    import dpq2.libpq;
}
    
import dpq2.answer;

import std.conv: to;
import std.string: toStringz;
import std.exception;
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
class BaseConnection
{
    string connString; /// Database connection parameters
    
    package PGconn* conn;
    private
    {
        bool readyForQuery;
        enum ConsumeResult
        {
            PQ_CONSUME_ERROR,
            PQ_CONSUME_OK
        }
    }
    
    @property bool nonBlocking(){ return PQisnonblocking(conn) == 1; }

    @disable
    @property bool nonBlocking( bool m )
    {
        setNonBlocking( m );
        return m;
    }
    
    private void setNonBlocking( bool state )
    {
        if( PQsetnonblocking(conn, state ? 1 : 0 ) == -1 )
            throw new exception();
    }
    
	/// Connect to DB
    void connect()
    {
        assert( !readyForQuery );
        
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if( !nonBlocking && PQstatus(conn) != ConnStatusType.CONNECTION_OK )
            throw new exception();
        
        readyForQuery = true;
    }

	/// Disconnect from DB
    void disconnect()
    {
        if( readyForQuery )
        {
            readyForQuery = false;
            PQfinish( conn );
        }
    }

    package void consumeInput()
    {
        size_t r = PQconsumeInput( conn );
        if( r != ConsumeResult.PQ_CONSUME_OK ) throw new exception();
    }
    
    package bool flush()
    {
        auto r = PQflush(conn);
        if( r == -1 ) throw new exception();
        return r == 0;
    }
    
    package size_t socket()
    {
        auto r = PQsocket( conn );
        assert( r >= 0 );
        return r;
    }
    
    ~this()
    {
        disconnect();
    }
    
    /// Exception
    class exception : Exception
    {
        /// libpq connection status
        immutable ConnStatusType statusType;
        
        this()
        {
            statusType = PQstatus(conn);
            super( to!string( statusType ), null, null );
        }
    }
}

void _unittest( string connParam )
{    
    assert( PQlibVersion() >= 90100 );
    
    auto c = new BaseConnection;
	c.connString = connParam;
    c.connect();
    c.disconnect();
}
