module dpq2.query;
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
public import dpq2.connection;

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
    /// Perform SQL query to DB
    Answer exec( string SQLcmd )
    {
        auto r = getAnswer(
            PQexec(conn, toStringz( SQLcmd ))
        );
        
        return r;
    }
    
    /// Perform SQL query to DB
    Answer exec(ref const queryParams p)
    {
        auto a = prepareArgs( p );
        auto r = getAnswer
        (
            PQexecParams (
                conn,
                cast(const char*)toStringz( p.sqlCommand ),
                cast(int)p.args.length,
                a.types.ptr,
                a.values.ptr,
                cast(int*)a.lengths.ptr,
                cast(int*)a.formats.ptr,
                cast(int)p.resultFormat
            )
        );
        
        return r;
    }
    
    /// Submits a command to the server without waiting for the result(s)
    void sendQuery( string SQLcmd )
    {
        size_t r = PQsendQuery( conn, toStringz(SQLcmd) );
        if( r != 1 ) throw new exception();
    }
    
    /// Submits a command and separate parameters to the server without waiting for the result(s)
    void sendQuery( ref const queryParams p )
    {
        auto a = prepareArgs( p );
        size_t r = PQsendQueryParams (
                    conn,
                    cast(const char*)toStringz( p.sqlCommand ),
                    cast(int)p.args.length,
                    a.types.ptr,
                    a.values.ptr,
                    cast(int*)a.lengths.ptr,
                    cast(int*)a.formats.ptr,
                    cast(int)p.resultFormat                    
                    );
                    
        if( !r ) throw new exception();
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
    notify getNextNotify()
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
        Answer res;
        
        if( r )
        {
            res = new Answer( r );
            res.checkAnswerForErrors();
        }
        
        return res;
    }
    
    private string errorMessage()
    {
        return to!(string)( PQerrorMessage(conn) );
    }
    
    /// Exception
    class exception: Exception
    {
        /// PQerrorMessage
        immutable string message;
        
        this()
        {
            message = errorMessage();
            super( message, null, null );
        }
    }
}


void _integration_test( string connParam )
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
    p.args = args[];

    auto r2 = conn.exec( p );

    conn.disconnect();
}
