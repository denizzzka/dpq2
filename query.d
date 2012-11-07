module dpq2.query;
@trusted:

import dpq2.libpq;
import dpq2.answer;
public import dpq2.connection;
public import dpq2.libpq: valueFormat;

/// Query parameters
struct queryParams
{
    string sqlCommand; /// SQL command
    queryArg[] args; /// SQL command arguments
    valueFormat resultFormat = valueFormat.TEXT; /// Result value format
}

/// Query argument
struct queryArg
{
    Oid type = 0;
    valueFormat queryFormat = valueFormat.TEXT; /// Value format
    ubyte[] valueBin; // can be null for SQL NULL value
    
    @property void valueStr( string s )
    {
        if( s == null )
            valueBin = null;
        else
            valueBin = cast(ubyte[])( s ~ '\0' );
    }
}

/// Connection
final class Connection: BaseConnection
{
    @system alias void delegate( Answer a ) answerHandler;
    private shared answerHandler handler;
    private void unusedHandler( Answer a ) { assert(false); }
    
    /// Perform SQL query to DB
    Answer exec( string SQLcmd )
    {
        assert( !handler );
        handler = &unusedHandler; // FIXME: dirty blocking
        auto r = getAnswer(
            PQexec(conn, toStringz( SQLcmd ))
        );
        
        return r;
    }
    
    /// Perform SQL query to DB
    Answer exec(ref const queryParams p)
    {
        assert( !handler );
        handler = &unusedHandler; // FIXME: dirty blocking
        
        auto a = prepareArgs( p );
        auto r = getAnswer
        (
            PQexecParams (
                conn,
                toStringz( p.sqlCommand ),
                p.args.length,
                a.types.ptr,
                a.values.ptr,
                a.lengths.ptr,
                a.formats.ptr,
                p.resultFormat
            )
        );
        
        return r;
    }
    
    import std.concurrency;
    alias Tid Descriptor;
    
    @property bool inUse(){ return handler != null; }    
    
    /// Submits a command to the server without waiting for the result(s)
    Descriptor sendQuery( string SQLcmd, answerHandler handler )
    {
        assert( !this.handler );
        this.handler = handler;
        
        size_t r = PQsendQuery( conn, toStringz(SQLcmd) );
        if( r != 1 ) throw new exception();
        
        return spawnExpectAnswer();
    }
    
    /// Submits a command and separate parameters to the server without waiting for the result(s)
    Descriptor sendQuery( ref const queryParams p, answerHandler handler )
    {
        assert( !this.handler );
        this.handler = handler;
        
        auto a = prepareArgs( p );
        size_t r = PQsendQueryParams (
                        conn,
                        toStringz( p.sqlCommand ),
                        p.args.length,
                        a.types.ptr,
                        a.values.ptr,
                        a.lengths.ptr,
                        a.formats.ptr,
                        p.resultFormat                        
                    );
        if( !r ) throw new exception();
        
        return spawnExpectAnswer();
    }
    
    private Tid spawnExpectAnswer()
    {
        return spawn( &expectAnswer, thisTid, cast(shared Connection) this );
    }
    
    static private void expectAnswer( Tid tid, shared Connection connection )
    {
        import std.socket;
        
        auto c = cast(Connection) connection;
        auto s = new Socket( cast(socket_t) c.socket(), AddressFamily.UNSPEC );
        auto ss = new SocketSet;
        ss.add( s );
        
        while( !c.flush() )
            Socket.select( null, ss, null );
        
        Socket.select( ss, null, null );
        
        do {
            c.consumeInput();
        } while( c.isBusy() );
        
        PGresult* r;
        while( r = PQgetResult( c.conn ), r )
            c.handler( new Answer( r ) );
        
        connection.handler = null;
        tid.send(true);
    }
    
    //TODO: возвращать количество сработок
    void waitAnswers()
    {
        receiveOnly!bool(); // TODO: ждать сообщение только от нашего Tid
    }
    
    /// Waits for the next result from a sendQuery
    package Answer getResult()
    {
        return getAnswer( PQgetResult( conn ) );
    }
    
    /// getResult would block waiting for input?
    package bool isBusy()
    {
        return PQisBusy(conn) == 1;
    }
    
    /// Returns null if no notifies was received
    @property
    immutable (notify) getNextNotify()
    {
        consumeInput();
        auto n = PQnotifies(conn);
        return n is null ? null : new notify( n );
    }
    
    private struct preparedArgs
    {
        Oid[] types;
        size_t[] formats;
        size_t[] lengths;
        const(ubyte)*[] values;
    }
    
    // For PQxxxParams need especially prepared arguments
    private preparedArgs* prepareArgs(ref const queryParams p)
    {
        preparedArgs* a = new preparedArgs;
        a.types = new Oid[p.args.length];
        a.formats = new size_t[p.args.length];
        a.lengths = new size_t[p.args.length];
        a.values = new const(ubyte)*[p.args.length];
        
        for( int i = 0; i < p.args.length; ++i )
        {
            a.types[i] = p.args[i].type;
            a.formats[i] = p.args[i].queryFormat;
            a.values[i] = p.args[i].valueBin.ptr;
            a.lengths[i] = p.args[i].valueBin.length;
        }
        
        return a;
    }
    
    // It is important to do a separate check because of Answer ctor is nothrow
    private Answer getAnswer( PGresult* r )
    {
        handler = null;
        auto res = new Answer( r );
        res.checkAnswerForErrors();
        return res;
    }
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    string sql_query =
    "select now() as time, 'abc'::text as string, 123, 456.78\n"
    "union all\n"
    "select now(), 'абвгд'::text, 777, 910.11\n"
    "union all\n"
    "select NULL, 'ijk'::text, 789, 12345.115345";

    auto r = conn.exec( sql_query );
    
    string sql_query2 =
    "select * from (\n"
    ~ sql_query ~
    ") t\n"
    "where string = $1";
    
    queryArg[1] args;
    queryArg arg;
    arg.valueStr = "абвгд";
    args[0] = arg;
    
    queryParams p;
    p.sqlCommand = sql_query2;
    p.args = args;

    auto r2 = conn.exec( p );
}
