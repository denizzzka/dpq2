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
        
        alias nothrow void delegate( Answer a ) answerHandler;
        
        alias answerHandler[] connSpecHandlers; // TODO: list would be better and thread-safe?
        public static connSpecHandlers[PGconn*] handlers; // TODO: list would be better and thread-safe?
        
        version(Release){}else
        {
        }
    }
    debug static string s;
    
    @property bool async(){ return asyncFlag; }

    @property bool async( bool m ) // FIXME: need to disable after connect or immutable connection params
    {
        assert( !(asyncFlag && !m), "pqlib can't change mode from async to sync" );
        
        if( !asyncFlag && m )
            registerEventProc( &eventsHandler, "default", null ); // FIXME: why name?
            // TODO: event handler can be registred only after connect!

        asyncFlag = m;
        return asyncFlag;
    }
    
    package void setNonBlocking( bool state )
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
    {
        handlers[ conn ] ~= h;
    }
    
    private static nothrow extern (C) size_t eventsHandler(PGEventId evtId, void* evtInfo, void* passThrough)
    {
        enum { ERROR = 0, OK }
        
        switch( evtId )
        {
            case PGEventId.PGEVT_REGISTER:
                debug s ~= "PGEVT_REGISTER ";
                return OK;
                
            case PGEventId.PGEVT_RESULTCREATE:
                auto info = cast(PGEventResultCreate*) evtInfo;
                debug s ~= info.conn != null ? "true " : "false ";
                
                // handler search
                answerHandler h;
                connSpecHandlers* l = ( info.conn in handlers );
                if( l !is null )
                    h = (*l).moveFront(); // oldest registred
                
                // fetch every result
                PGresult* r;
                while( r = PQgetResult(info.conn), r )
                {
                    debug s ~= "result_received ";
                    if( h !is null) // handler was found previously?
                        h( new Answer(r) );
                }

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
    //c.async = true;
    //c.addHandler( (immutable Answer a){} );
    c.disconnect();
}
