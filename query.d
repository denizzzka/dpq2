module dpq2.query;
@trusted:

import dpq2.libpq;
import dpq2.connection;
import dpq2.answer;

struct queryParams
{
    string sqlCommand;
    queryArg[] args;
    valueFormat result_format = valueFormat.TEXT;
}

struct queryArg
{
    Oid type = 0;
    valueFormat format = valueFormat.TEXT;
    union {
        byte[] valueBin;
        string valueStr;
    };
}

final class Connection: BaseConnection
{
    answer exec(string SQLcmd )
    {
        return new answer(
            PQexec(conn, toStringz( SQLcmd ))
        );
    }

    answer exec(ref const queryParams p)
    {
        // code above just preparing args for PQexecParams
        Oid[] types = new Oid[p.args.length];
        int[] formats = new int[p.args.length];
        int[] lengths = new int[p.args.length];
        const(byte)*[] values = new const(byte)*[p.args.length];

        for( int i = 0; i < p.args.length; ++i )
        {
            types[i] = p.args[i].type;
            formats[i] = p.args[i].format;  
            values[i] = p.args[i].valueBin.ptr;
            
            final switch( p.args[i].format )
            {
                case valueFormat.TEXT:
                    lengths[i] = to!int( p.args[i].valueStr.length );
                    break;
                case valueFormat.BINARY:
                    lengths[i] = to!int( p.args[i].valueBin.length );
                    break;
            }
        }

        return new answer
        (
            PQexecParams (
                conn,
                toStringz( p.sqlCommand ),
                to!int( p.args.length ),
                types.ptr,
                values.ptr,
                lengths.ptr,
                formats.ptr,
                p.result_format
            )
        );
    }

    /// returns null if no notifies was received
    notify getNextNotify()
    {
        consumeInput();
        auto n = PQnotifies(conn);
        return n is null ? null : new notify(n);
    }

}

void _unittest( string connParam )
{
    //TODO: отсюда всё вынести, кроме проверки запросов. Ответы првоерять в answer.d
    
    connArgs cd = {
        connString: connParam,
        type: connVariant.SYNC
    };

    auto conn = new Connection;
    conn.connect( cd );

    string sql_query =
    "select now() as time, 'abc'::text as string, 123, 456.78\n"
    "union all\n"
    "select now(), 'def'::text, 456, 910.11\n"
    "union all\n"
    "select NULL, 'ijk'::text, 789, 12345.115345";

    auto r = conn.exec( sql_query );
    
    alias dpq2.answer.answer.Coords Coords;
    
    auto c1 = Coords(2,1);
    auto c2 = Coords(0,0);
    auto c3 = Coords(0,2);
    auto c4 = Coords(2,0);

    assert( r.rows_num == 3 );
    assert( r.cols_num == 4);
    assert( r.columnFormat(2) == dpq2.libpq.valueFormat.TEXT );
    assert( r.getValue(c1).str == "456" );
    assert( !r.isNULL( c2 ) );
    assert( r.isNULL( c3 ) );
    assert( r.column_num( "string" ) == 1 );

    auto c = r.getValue( c1 ); 
    assert( c.str == "456" );   

    string sql_query2 =
    "select * from (\n"
    ~ sql_query ~
    ") t\n"
    "where string = $1";
    
    static queryArg arg = { valueStr: "def" };
    queryArg[1] args;
    args[0] = arg;
    queryParams p;
    p.sqlCommand = sql_query2;
    p.args = args;

    r = conn.exec( p );     
    assert( r.getValue( c4 ).str == "456" );

    string sql_query3 = "listen test_notify; notify test_notify";
    r = conn.exec( sql_query3 );
    assert( conn.getNextNotify.name == "test_notify" );
}
