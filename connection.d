///TODO: защита класса BaseConnection на тему мультитредности

module dpq2.connection;
@trusted:

import dpq2.libpq;

import std.conv: to;
import std.string: toStringz;
import std.exception;
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
        bool connectingInProgress;
        bool readyForQuery;
        bool asyncFlag = false;
        enum ConsumeResult
        {
            PQ_CONSUME_ERROR,
            PQ_CONSUME_OK
        }
        
        version(Release){}else
        {
        }
    }
    
    @property bool async(){ return asyncFlag; }

    @property bool async( bool m )
    {
        assert( asyncFlag && !m, "pqlib can't change mode from async to sync" );
        
        if( !asyncFlag && m )
        {
            //auto res = PQregisterEventProc(conn, null,
                //const char *name, void *passThrough);
        }
        asyncFlag = m;
        return asyncFlag;
    }
    
	/// Connect to DB
    void connect()
    {
		// TODO: нужны блокировки чтобы нельзя было несколько раз создать
		// соединение из параллельных потоков или запрос через нерабочее соединение
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if( !async && PQstatus(conn) != ConnStatusType.CONNECTION_OK )
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
        else
        {
            assert("Not connected yet!");
        }
    }

    package void consumeInput()
    {
        int r = PQconsumeInput( conn );
        if( r != ConsumeResult.PQ_CONSUME_OK ) throw new exception();
    }

    private static string PQerrorMessage(PGconn* conn)
    {
        return to!(string)( dpq2.libpq.PQerrorMessage(conn) );
    }
    
    private size_t eventProc(PGEventId evtId, void *evtInfo, void *passThrough)
    {
        import std.stdio;
        writeln( evtId );
        return 1;
    }
    
    ~this()
    {
        disconnect();
    }
    
    /// Exception
    class exception : Exception
    {
        ConnStatusType statusType; /// libpq connection status
        
        this()
        {
            statusType = PQstatus(conn);
            super( PQerrorMessage(conn), null, null );
        }
    }
}


void _unittest( string connParam )
{    
    assert( PQlibVersion() >= 90100 );
    
    auto c = new BaseConnection;
	c.connString = connParam;
    c.connect();
    c.asyncFlag = true;
    c.disconnect();
    
    
}
