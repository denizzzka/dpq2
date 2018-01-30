﻿module dpq2.query;

public import dpq2.args;

import dpq2;
import core.time: Duration, dur;
import std.exception: enforce;

mixin template Queries()
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
    immutable (Answer) execParams(in ref QueryParams qp)
    {
        auto p = InternalQueryParams(&qp);
        auto pgResult = PQexecParams (
                conn,
                p.command,
                p.nParams,
                p.paramTypes,
                p.paramValues,
                p.paramLengths,
                p.paramFormats,
                p.resultFormat
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
    void sendQueryParams(in ref QueryParams qp)
    {
        auto p = InternalQueryParams(&qp);
        size_t r = PQsendQueryParams (
                conn,
                p.command,
                p.nParams,
                p.paramTypes,
                p.paramValues,
                p.paramLengths,
                p.paramFormats,
                p.resultFormat
            );

        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
    }

    /// Sends a request to execute a prepared statement with given parameters, without waiting for the result(s)
    void sendQueryPrepared(in ref QueryParams qp)
    {
        auto p = InternalQueryParams(&qp);
        size_t r = PQsendQueryPrepared(
                conn,
                p.stmtName,
                p.nParams,
                p.paramValues,
                p.paramLengths,
                p.paramFormats,
                p.resultFormat
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

    /// Submits a request to create a prepared statement with the given parameters, and waits for completion.
    immutable(Result) prepare(string statementName, string sqlStatement, in Oid[] oids = null)
    {
        PGresult* pgResult = PQprepare(
                conn,
                toStringz(statementName),
                toStringz(sqlStatement),
                oids.length.to!int,
                oids.ptr
            );

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Result(container);
    }

    /// Submits a request to execute a prepared statement with given parameters, and waits for completion.
    immutable(Answer) execPrepared(in ref QueryParams qp)
    {
        auto p = InternalQueryParams(&qp);
        auto pgResult = PQexecPrepared(
                conn,
                p.stmtName,
                p.nParams,
                cast(const(char*)*)p.paramValues,
                p.paramLengths,
                p.paramFormats,
                p.resultFormat
            );

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Answer(container);
    }

    /// Sends a request to create a prepared statement with the given parameters, without waiting for completion.
    void sendPrepare(string statementName, string sqlStatement, in Oid[] oids = null)
    {
        size_t r = PQsendPrepare(
                conn,
                toStringz(statementName),
                toStringz(sqlStatement),
                oids.length.to!int,
                cast(Oid*)oids.ptr //const should be accepted here, see https://github.com/DerelictOrg/DerelictPQ/issues/21
            );

        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
    }

    immutable(Answer) describePrepared(string statementName)
    {
        PGresult* pgResult = PQdescribePrepared(conn, toStringz(statementName));

        // is guaranteed by libpq that the result will not be changed until it will not be destroyed
        auto container = createResultContainer(cast(immutable) pgResult);

        return new immutable Answer(container);
    }

    void sendDescribePrepared(string statementName)
    {
        size_t r = PQsendDescribePrepared(conn, statementName.toStringz);

        if(r != 1) throw new ConnectionException(this, __FILE__, __LINE__);
    }

    /// Waiting for completion of reading or writing
    /// Return: timeout not occured
    bool waitEndOf(WaitType type, Duration timeout = Duration.zero)
    {
        import std.socket;

        auto socket = this.socket();
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

void _integration_test( string connParam ) @trusted
{
    auto conn = new Connection(connParam);

    // Text type arguments testing
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

    // Binary type arguments testing
    {
        import vibe.data.bson: Bson;

        const string sql_query =
        "select $1::text, $2::integer, $3::text, $4, $5::integer[]";

        Value[5] args;
        args[0] = toValue("абвгд");
        args[1] = Value(ValueFormat.BINARY, OidType.Undefined); // undefined type NULL value
        args[2] = toValue("123");
        args[3] = Value(ValueFormat.BINARY, OidType.Int8); // NULL value

        Bson binArray = Bson([
            Bson([Bson(null), Bson(123), Bson(456)]),
            Bson([Bson(0), Bson(789), Bson(null)])
        ]);

        args[4] = bsonToValue(binArray);

        QueryParams p;
        p.sqlCommand = sql_query;
        p.args = args[];

        auto a = conn.execParams( p );

        foreach(i; 0 .. args.length)
            assert(a.columnFormat(i) == ValueFormat.BINARY);

        assert( a.OID(0) == OidType.Text );
        assert( a.OID(1) == OidType.Int4 );
        assert( a.OID(2) == OidType.Text );
        assert( a.OID(3) == OidType.Int8 );
        assert( a.OID(4) == OidType.Int4Array );

        // binary args array test
        assert( a[0][4].as!Bson == binArray );
    }

    {
        // Bug #52: empty text argument
        QueryParams p;
        Value v = toValue("");

        p.sqlCommand = "SELECT $1";
        p.args = [v];

        auto a = conn.execParams(p);

        assert( !a[0][0].isNull );
        assert( a[0][0].as!string == "" );
    }

    // checking prepared statements
    {
        // uses PQprepare:
        auto s = conn.prepare("prepared statement 1", "SELECT $1::integer");
        assert(s.status == PGRES_COMMAND_OK);

        QueryParams p;
        p.preparedStatementName = "prepared statement 1";
        p.args = [42.toValue];
        auto r = conn.execPrepared(p);
        assert (r[0][0].as!int == 42);
    }
    {
        // uses PQsendPrepare:
        conn.sendPrepare("prepared statement 2", "SELECT $1::text, $2::integer");

        conn.waitEndOf(WaitType.READ, dur!"seconds"(5));
        conn.consumeInput();

        immutable(Result)[] res;

        while(true)
        {
            auto r = conn.getResult();
            if(r is null) break;
            res ~= r;
        }

        assert(res.length == 1);
        assert(res[0].status == PGRES_COMMAND_OK);
    }
    {
        // check prepared arg types and result types
        auto a = conn.describePrepared("prepared statement 2");

        assert(a.nParams == 2);
        assert(a.paramType(0) == OidType.Text);
        assert(a.paramType(1) == OidType.Int4);
    }
    {
        // async check prepared arg types and result types
        conn.sendDescribePrepared("prepared statement 2");

        conn.waitEndOf(WaitType.READ, dur!"seconds"(5));
        conn.consumeInput();

        immutable(Result)[] res;

        while(true)
        {
            auto r = conn.getResult();
            if(r is null) break;
            res ~= r;
        }

        assert(res.length == 1);
        assert(res[0].status == PGRES_COMMAND_OK);

        auto a = res[0].getAnswer;

        assert(a.nParams == 2);
        assert(a.paramType(0) == OidType.Text);
        assert(a.paramType(1) == OidType.Int4);
    }
    {
        QueryParams p;
        p.preparedStatementName = "prepared statement 2";
        p.argsFromArray = ["abc", "123456"];

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

        assert(res.length == 1);
        assert(res[0].getAnswer[0][0].as!PGtext == "abc");
        assert(res[0].getAnswer[0][1].as!PGinteger == 123456);
    }

    import std.socket;
    conn.socket.shutdown(SocketShutdown.BOTH); // breaks connection

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
