module dpq2.query;

@trusted:

import dpq2;
import core.time: Duration;

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

    @property string preparedStatementName() const { return sqlCommand; }
    @property void preparedStatementName(string s){ sqlCommand = s; }
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
    immutable (Answer) exec( string SQLcmd )
    {
        auto pgResult = PQexec(conn, toStringz( SQLcmd ));

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Answer(container);
    }
    
    /// Perform SQL query to DB
    immutable (Answer) exec(in QueryParams p)
    {
        auto a = prepareArgs( p );
        auto pgResult = PQexecParams (
                conn,
                cast(const char*)toStringz( p.sqlCommand ),
                cast(int)p.args.length,
                a.types.ptr,
                a.values.ptr,
                cast(int*)a.lengths.ptr,
                cast(int*)a.formats.ptr,
                cast(int)p.resultFormat
        );

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Answer(container);
    }
    
    /// Submits a command to the server without waiting for the result(s)
    void sendQuery( string SQLcmd )
    {
        const size_t r = PQsendQuery( conn, toStringz(SQLcmd) );
        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
    }
    
    /// Submits a command and separate parameters to the server without waiting for the result(s)
    void sendQuery( in QueryParams p )
    {
        auto a = prepareArgs( p );
        size_t r = PQsendQueryParams (
                conn,
                cast(const char*)toStringz(p.sqlCommand),
                cast(int)p.args.length,
                a.types.ptr,
                a.values.ptr,
                cast(int*)a.lengths.ptr,
                cast(int*)a.formats.ptr,
                cast(int)p.resultFormat
            );

        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
    }

    /// Sends a request to execute a prepared statement with given parameters, without waiting for the result(s)
    void sendQueryPrepared(in QueryParams p)
    {
        auto a = prepareArgs(p);

        size_t r = PQsendQueryPrepared( //TODO: need report to derelict pq
                conn,
                cast(char*)toStringz(p.preparedStatementName),
                to!int(p.args.length),
                cast(char**)a.values.ptr,
                cast(int*)a.lengths.ptr,
                cast(int*)a.formats.ptr,
                to!int(p.resultFormat)
            );

        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
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
    private static PreparedArgs* prepareArgs(in QueryParams p) pure
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

    immutable(Result) prepare(string statementName, string sqlStatement, size_t nParams)
    {
        PGresult* pgResult = PQprepare(
                conn,
                cast(char*)toStringz(statementName), //TODO: need report to derelict pq
                cast(char*)toStringz(sqlStatement), //TODO: need report to derelict pq
                to!int(nParams),
                null
            );

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Result(container);
    }

    /// Waiting for completion of reading or writing
    /// Return: timeout not occured
    bool waitEndOf(WaitType type, Duration timeout = Duration.zero)
    {
        import std.socket;

        auto socket = socket();
        auto set = new SocketSet;
        set.add(socket);

        while(true)
        {
            if(status() == CONNECTION_BAD)
                throw new ConnectionException(this, __FILE__, __LINE__);

            if(poll() == PGRES_POLLING_OK)
            {
                return true;
            }
            else
            {
                size_t sockNum;

                with(WaitType)
                final switch(type)
                {
                    case READ:
                        sockNum = Socket.select(set, null, set, timeout);
                        break;

                    case WRITE:
                        sockNum = Socket.select(null, set, set, timeout);
                        break;

                    case READ_WRITE:
                        sockNum = Socket.select(set, set, set, timeout);
                        break;
                }

                enforce(sockNum >= 0);
                if(sockNum == 0) return false; // timeout is occurred

                continue;
            }
        }
    }
}

enum WaitType
{
    READ,
    WRITE,
    READ_WRITE
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
        assert( a.length == 3 );
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

    {
        // checking sendQueryPrepared
        auto s = conn.prepare("prepared statement", "SELECT $1::text, $2::integer", 1);
        assert(s.status == PGRES_COMMAND_OK);

        QueryParams p;
        p.preparedStatementName = "prepared statement";
        p.args.length = 2;
        p.args[0].value = "abc";
        p.args[1].value = "123456";

        conn.sendQueryPrepared(p);

        conn.waitEndOf(WaitType.READ, dur!"seconds"(5));
        conn.consumeInput();

        immutable(Result)[] res;

        while(true)
        {
            auto r = conn.getResult();
            if(r is null) break;
            res ~= r;
        }

        assert(res[0].getAnswer[0][0].as!PGtext);
        assert(res[0].getAnswer[0][1].as!PGinteger);
    }

    conn.disconnect();

    {
        bool exceptionFlag = false;

        try conn.exec("SELECT 'abc'::text").getAnswer;
        catch(ConnectionException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 15); // error message check
        }
        finally
            assert(exceptionFlag);
    }
}
