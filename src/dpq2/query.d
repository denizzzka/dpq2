module dpq2.query;

@trusted:

import dpq2.answer;
public import dpq2.connection;

import derelict.pq.pq;

enum ValueFormat : ubyte {
    TEXT,
    BINARY
}

/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    QueryArg[] args; /// SQL command arguments
    ValueFormat resultFormat = ValueFormat.BINARY; /// Result value format
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
// Inheritance used here for separation of query code from connection code
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
        const size_t r = PQsendQuery( conn, toStringz(SQLcmd) );
        if( r != 1 ) throw new ConnException(this, __FILE__, __LINE__);
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
                    
        if( !r ) throw new ConnException(this, __FILE__, __LINE__);
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
    
    private struct PreparedArgs
    {
        Oid[] types;
        size_t[] formats;
        size_t[] lengths;
        const(ubyte)*[] values;
    }
    
    // For PQxxxParams need especially prepared arguments
    private PreparedArgs* prepareArgs(ref const QueryParams p)
    {
        PreparedArgs* a = new PreparedArgs;
        a.types = new Oid[p.args.length];
        a.formats = new size_t[p.args.length];
        a.lengths = new size_t[p.args.length];
        a.values = new const(ubyte)*[p.args.length];
        
        for( int i = 0; i < p.args.length; ++i )
        {
            a.types[i] = p.args[i].type;
            a.formats[i] = ValueFormat.TEXT;
            a.values[i] = p.args[i].valueBin.ptr;
            a.lengths[i] = p.args[i].valueBin.length;
        }
        
        return a;
    }

    /// Get Answer from PQexec* functions
    // It is important to do a separate check because of Answer ctor is nothrow
    private Answer getAnswer( PGresult* r )
    {
        Answer res;
        
        if( r )
        {
            res = new Answer( r );
            res.checkAnswerForErrors();
        }
        else throw new ConnException(this, __FILE__, __LINE__);
        
        return res;
    }
}

void _integration_test( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    {    
        string sql_query =
        "select now() as time, 'abc'::text as string, 123, 456.78\n"~
        "union all\n"~
        "select now(), 'абвгд'::text, 777, 910.11\n"~
        "union all\n"~
        "select NULL, 'ijk'::text, 789, 12345.115345";

        auto a = conn.exec( sql_query );

        assert( a.cmdStatus.length > 2 );
        assert( a.columnCount == 4 );
        assert( a.rowCount == 3 );
        assert( a.columnFormat(1) == ValueFormat.TEXT );
        assert( a.columnFormat(2) == ValueFormat.TEXT );
    }

    {
        const string sql_query =
        "select $1::text, $2::integer, $3::text";

        QueryArg[3] args;
        args[0].value = "абвгд";
        args[1].value = null;
        args[2].value = "123";

        QueryParams p;
        p.sqlCommand = sql_query;
        p.args = args[];

        auto a = conn.exec( p );

        assert( a.columnFormat(1) == ValueFormat.BINARY );
        assert( a.columnFormat(2) == ValueFormat.BINARY );

        destroy(a);
    }

    conn.disconnect();

    {
        bool exceptionFlag = false;

        try conn.exec("SELECT 'abc'::text");
        catch(ConnException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 15); // error message check
        }
        finally
            assert(exceptionFlag);
    }
}
