module dpq2.connection;
@trusted:

import dpq2.libpq;
public import dpq2.libpq: valueFormat;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

enum connVariant { SYNC, ASYNC };

/*
 * Bugs: On Unix connection is not thread safe.
 * 
 * On Unix, forking a process with open libpq connections can lead
 * to unpredictable results because the parent and child processes share
 * the same sockets and operating system resources. For this reason,
 * such usage is not recommended, though doing an exec from the child
 * process to load a new executable is safe.

TODO: запрет копирования класса conn_piece:

Returns the thread safety status of the libpq library.

int PQisthreadsafe();
Returns 1 if the libpq is thread-safe and 0 if it is not.
*/
class BaseConnection
{
    package PGconn* conn;
    private bool connectingInProgress;
    private bool readyForQuery;
    private enum ConsumeResult
    {
        PQ_CONSUME_ERROR,
        PQ_CONSUME_OK
    }
    
    string connString; /// Database connection the parameters
	connVariant connType = connVariant.SYNC; /// Connection variant

    void connect()
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

    ~this() {
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
    
    class exception : Exception
    {
        alias ConnStatusType pq_type; /// libpq conn statuses

        pq_type type;
        
        this() {
            type = PQstatus(conn);
            super( PQerrorMessage(conn), null, null );
        }
    }
}

void _unittest( string connParam )
{    
    auto c = new BaseConnection;
	c.connString = connParam;
    c.connect();
    c.disconnect();
}
