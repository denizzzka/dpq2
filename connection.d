///TODO: защита класса BaseConnection на тему мультитредности

module dpq2.connection;
@trusted:

import dpq2.libpq;
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
    
    @system alias nothrow void delegate( Answer a ) answerHandler;
    
    package PGconn* conn;
    private
    {
        bool connectingInProgress;
        bool readyForQuery;
        enum ConsumeResult
        {
            PQ_CONSUME_ERROR,
            PQ_CONSUME_OK
        }
        
        shared static answerHandler[PGconn*] handlers; // TODO: list would be better and thread-safe?
        
        version(Release){}else
        {
        }
    }
    
    enum handlerStatuses
    {
        HANDLER_STATUS_OK,
        HANDLER_NOT_FOUND /// No delegate for query processing has been found
    }
    
    auto handlerStatus = handlerStatuses.HANDLER_STATUS_OK;
    
    @property bool async(){ return PQisnonblocking(conn) == 1; }

    @disable
    @property bool async( bool m ) // FIXME: need to disable after connect or immutable connection params
    {
        //assert( !(async && !m), "pqlib can't change mode from async to sync" );
        
        if( !async && m )
            registerEventProc( &eventsHandler, "PGRESULT_HANDLER", &handlerStatus );
            // TODO: event handler can be registred only after connect!
            
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
    }

    package void consumeInput()
    {
        int r = PQconsumeInput( conn );
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
    
    private static string PQerrorMessage(PGconn* conn)
    {
        return to!(string)( dpq2.libpq.PQerrorMessage(conn) );
    }
    
    private void registerEventProc( PGEventProc proc, string name, void *passThrough )
    {
        if(!PQregisterEventProc(conn, proc, toStringz(name), passThrough))
            throw new exception( "Could not register "~name~" event handler" );
    }
    
    package void addHandler( answerHandler h )
    {   // FIXME: need synchronization
        assert( !( conn in handlers ),
            "Can't make a query while hasn't been completed previous one." );
        handlers[ conn ] = h;
    }
    
    private static nothrow extern (C) size_t eventsHandler(PGEventId evtId, void* evtInfo, void* hStatus)
    {
        auto handlerStatus = cast(handlerStatuses*) hStatus;
        *handlerStatus = handlerStatuses.HANDLER_STATUS_OK;
        
        enum { ERROR = 0, OK }
        
        switch( evtId )
        {
            case PGEventId.PGEVT_REGISTER:
                return OK;
                
            case PGEventId.PGEVT_RESULTCREATE:
                auto info = cast(PGEventResultCreate*) evtInfo;
                assert( handlers[ info.conn ] != null );
                
                PGresult* r;
                while( r = PQgetResult(info.conn), r )
                {
                    handlers[ info.conn ]( new Answer(r) );
                }
                
                handlers.remove( info.conn );
                return OK; // all results are processed
                
            default:
                return OK; // other events
        }
    }
    
    ~this()
    {
        disconnect();
    }
    
    /// Exception
    class exception : Exception
    {
        ConnStatusType statusType; /// libpq connection status
        
        this( string msg )
        {
            super( msg, null, null );
        }
        
        this()
        {
            this( to!string( PQstatus(conn) ) ); // FIXME: need text representation of PQstatus result
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
