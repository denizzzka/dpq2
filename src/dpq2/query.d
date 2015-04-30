module dpq2.query;

@trusted:

import dpq2.answer;
public import dpq2.connection;

import derelict.pq.pq;


/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    QueryArg[] args; /// SQL command arguments
    valueFormat resultFormat = valueFormat.BINARY; /// Result value format
}

/// Query argument
struct QueryArg
{
    Oid type = 0;
    private ubyte[] valueBin;
    
    /// s can be null for SQL NULL value
    @property void value( string s )
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
    Answer exec(ref const QueryParams p)
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
    void sendQuery( ref const QueryParams p )
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
    Notify getNextNotify()
    {
        consumeInput();
        auto n = PQnotifies(conn);
        return n is null ? null : new Notify( n );
    }
    
    private struct preparedArgs
    {
        Oid[] types;
        size_t[] formats;
        size_t[] lengths;
        const(ubyte)*[] values;
    }
    
    // For PQxxxParams need especially prepared arguments
    private preparedArgs* prepareArgs(ref const QueryParams p)
    {
        preparedArgs* a = new preparedArgs;
        a.types = new Oid[p.args.length];
        a.formats = new size_t[p.args.length];
        a.lengths = new size_t[p.args.length];
        a.values = new const(ubyte)*[p.args.length];
        
        for( int i = 0; i < p.args.length; ++i )
        {
            a.types[i] = p.args[i].type;
            a.formats[i] = valueFormat.TEXT;
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
    
    conn.exec( sql_query );
    
    const string sql_query2 =
    "select * from (\n"
    ~ sql_query ~
    ") t\n"
    "where string = $1";
    
    QueryArg[1] args;
    QueryArg arg;
    arg.value = "абвгд";
    args[0] = arg;
    
    QueryParams p;
    p.sqlCommand = sql_query2;
    p.args = args[];
    
    conn.exec( p );
    
    conn.disconnect();
}
