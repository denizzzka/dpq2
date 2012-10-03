module dpq2.answer;
@trusted:

import dpq2.libpq;
import dpq2.connection;
import dpq2.query;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

debug import std.stdio: writeln;

class answer
{  
    struct Coords
    {
        size_t Col;
        size_t Row;
    }

    // внимание: ячейка не знает своих собственных координат - так задумано, для экономии
    struct cell {
        package {
            immutable (byte)* val;
            int size; // currently used only for bin
            debug valueFormat format;
        }

        @property string str(){
            debug enforce( format == valueFormat.TEXT, "Format of the column is not text" );
            return to!string( cast(immutable(char)*)val );
        }

        @property immutable (byte[]) bin(){
            debug enforce( format == valueFormat.BINARY, "Format of the column is not binary" );
            return val[0..size];
        }
    }
    
    private PGresult* res;
    
    private this(){}
    
    package this(PGresult* r){
        res = r;
        enforceEx!OutOfMemoryError(r, "Can't write query result");
        if(!(status == ExecStatusType.PGRES_COMMAND_OK ||
             status == ExecStatusType.PGRES_TUPLES_OK))
            throw new exception();
    }
    
    ~this() {
        PQclear(res);
    }

    ExecStatusType status() {
        return PQresultStatus(res);
    }

    string cmd_status() {
        return to!string( PQcmdStatus(res) );
    }

    int rows_num(){ return PQntuples(res); }

    int cols_num(){ return PQnfields(res); }

    valueFormat columnFormat( size_t colNum ) {
        return PQfformat(res, colNum);
    }
    
    int column_num( string column_name ) {    
        int n = PQfnumber(res, toStringz(column_name));
        if( n == -1 )
            throw new exception(exception.exception_types.COLUMN_NOT_FOUND,
                                "Column '"~column_name~"' is not found");
        return n;
    }

    cell* getValue( const Coords c )
    {
        assertCoords(c);
        
        cell* r = new cell;
        r.val = PQgetvalue(res, c.Row, c.Col);
        r.size = size( c );
        debug r.format = columnFormat( c.Col );
        return r;
    }
    
    cell* opIndex( size_t Row, size_t Col )
    {
        return getValue( Coords( Col, Row ) );
    };
    
    int size( const Coords c ) {
        assertCoords(c);
        return PQgetlength(res, c.Row, c.Col);
    }
    
    bool isNULL( const Coords c ) {
        assertCoords(c);
        return PQgetisnull(res, c.Row, c.Col) != 0;
    }

    private void assertCoords( const Coords c )
    {
        assert( c.Row < rows_num, to!string(c.Row)~" row is out of range 0.."~to!string(rows_num-1)~" of result rows" );
        assert( c.Col < cols_num, to!string(c.Col)~" col is out of range 0.."~to!string(rows_num-1)~" of result cols" );
    }

    class exception : Exception {       
        enum exception_types {
            COLUMN_NOT_FOUND
        }
        
        exception_types type;

        string error_msg() {
            return to!string( PQresultErrorMessage(res) );
        }
        
        this( exception_types t, string msg ) {
            type = t;
            super( msg, null, null );
        }
        
        this() {
            super( error_msg~" ("~to!string(status)~")", null, null );
        }           
    }
}

class notify {
    private PGnotify* n;

    this(){}
    this( PGnotify* n ) { this.n = n; }
    ~this() { PQfreemem(n); }

    string name() { return to!string( n.relname ); }
    string extra() { return to!string( n.extra ); }
    int pid() { return n.be_pid; }

    invariant(){
        assert( n != null );
    }
}

void _unittest( string connParam )
{
    connArgs cd = {
        connString: connParam,
        type: connVariant.SYNC
    };

    auto conn = new Connection;
    conn.connect( cd );

    string sql_query =
    "select now() as time,  'abc'::text as string,  123,  456.78\n"
    "union all\n"
    "select now(),          'def'::text,            456,  910.11\n"
    "union all\n"
    "select NULL,           'ijk'::text,            789,  12345.115345";

    auto r = conn.exec( sql_query );
    
    alias dpq2.answer.answer.Coords Coords;

    assert( r.rows_num == 3 );
    assert( r.cols_num == 4);
    assert( r.columnFormat(2) == dpq2.libpq.valueFormat.TEXT );
    assert( r[1,2].str == "456" );
    assert( !r.isNULL( Coords(0,0) ) );
    assert( r.isNULL( Coords(0,2) ) );
    assert( r.column_num( "string" ) == 1 );

    auto c = r.getValue( Coords(2,1) ); 
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
    assert( r.getValue( Coords(2,0) ).str == "456" );

    string sql_query3 = "listen test_notify; notify test_notify";
    r = conn.exec( sql_query3 );
    assert( conn.getNextNotify.name == "test_notify" );
}
