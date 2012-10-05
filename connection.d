///TODO: защита класса BaseConnection на тему мультитредности

module dpq2.connection;
@trusted:

import dpq2.libpq;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

/// Available connection types
enum connVariant { SYNC, ASYNC };

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
export class BaseConnection
{
    package PGconn* conn;
    private bool connectingInProgress;
    private bool readyForQuery;
    private enum ConsumeResult
    {
        PQ_CONSUME_ERROR,
        PQ_CONSUME_OK
    }
    
    export string connString; /// Database connection parameters
	connVariant connType = connVariant.SYNC; /// Connection type variant

	/// Connect to DB
    export void connect()
    {
		// TODO: нужны блокировки чтобы нельзя было несколько раз создать
		// соединение из параллельных потоков или запрос через нерабочее соединение
        conn = PQconnectdb(toStringz(connString));
        
        enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
        
        if(connType == connVariant.SYNC &&
           PQstatus(conn) != ConnStatusType.CONNECTION_OK)
            throw new exception();
        
        readyForQuery = true;
    }

	/// Disconnect from DB
    export void disconnect()
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

    export ~this()
    {
        disconnect();
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
    c.disconnect();
}
