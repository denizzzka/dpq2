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

/// Answer
class answer
{  
    /// Result table's cell coordinates 
    struct Coords
    {
        size_t Row; /// Row
        size_t Col; /// Column
    }

    /// Result table's cell
    // внимание: ячейка не знает своих собственных координат - так задумано, для экономии
    struct Cell {
        package {
            const (byte)* val;
            size_t size; // currently used only for bin
            debug valueFormat format;
        }

        /// Returns value from text formatted fields
        @property string str() const {
            debug enforce( format == valueFormat.TEXT, "Format of the column is not text" );
            return to!string( cast(immutable(char)*)val );
        }

        /// Returns value from binary formatted fields
        @property const (byte)[] bin() const {
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

    /// Returns the command status tag from the SQL command that generated the PGresult
    /**
     * Commonly this is just the name of the command, but it might include 
     * additional data such as the number of rows processed. The caller should 
     * not free the result directly. It will be freed when the associated 
     * PGresult handle is passed to PQclear.
     */
    string cmdStatus()
    {
        return to!string( PQcmdStatus(res) );
    }

    /// Returns row count
    @property size_t rowCount(){ return PQntuples(res); }

    /// Returns column count
    @property size_t columnCount(){ return PQnfields(res); }

    /// Returns column format
    valueFormat columnFormat( size_t colNum )
    {
        return PQfformat(res, colNum);
    }
    
    /// Returns column number by field name
    size_t columnNum( string column_name )
    {    
        size_t n = PQfnumber(res, toStringz(column_name));
        if( n == -1 )
            throw new exception(exception.exceptionTypes.COLUMN_NOT_FOUND,
                                "Column '"~column_name~"' is not found");
        return n;
    }

    private const (Cell)* getValue( const Coords c )
    {
        assertCoords(c);
        
        Cell* r = new Cell;
        r.val = PQgetvalue(res, c.Row, c.Col);
        r.size = size( c );
        debug r.format = columnFormat( c.Col );
        return r;
    }
    
    /// Returns pointer to cell
    const (Cell)* opIndex( size_t Row, size_t Col )
    {
        return getValue( Coords( Row, Col ) );
    };
    
    /// Returns cell size
    size_t size( const Coords c ) {
        assertCoords(c);
        return PQgetlength(res, c.Row, c.Col);
    }
    
    /// Cell NULL checking
    bool isNULL( const Coords c ) {
        assertCoords(c);
        return PQgetisnull(res, c.Col, c.Row) != 0;
    }

    private void assertCoords( const Coords c )
    {
        assert( c.Row < rowCount, to!string(c.Row)~" row is out of range 0.."~to!string(rowCount-1)~" of result rows" );
        assert( c.Col < columnCount, to!string(c.Col)~" col is out of range 0.."~to!string(columnCount-1)~" of result cols" );
    }
    
    /// Exception
    class exception : Exception
    {       
        /// Exception types
        enum exceptionTypes
        {
            COLUMN_NOT_FOUND /// Column not found
        }
        
        exceptionTypes type; /// Exception type
        
        /// Returns the error message associated with the command
        string resultErrorMessage()
        {
            return to!string( PQresultErrorMessage(res) );
        }
        
        this( exceptionTypes t, string msg )
        {
            type = t;
            super( msg, null, null );
        }
        
        this()
        {
            super( resultErrorMessage~" ("~to!string(status)~")", null, null );
        }           
    }
}

class notify
{
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
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    string sql_query =
    "select now() as time,  'abc'::text as field_name,   123,  456.78\n"
    "union all\n"

    "select now(),          'def'::text,                 456,  910.11\n"
    "union all\n"

    "select NULL,           'ijk'::text,                 789,  12345.115345";

    auto r = conn.exec( sql_query );
    
    alias answer.Coords Coords;

    assert( r.rowCount == 3 );
    assert( r.columnCount == 4);
    assert( r.columnFormat(2) == valueFormat.TEXT );
    assert( r[1,2].str == "456" );
    assert( !r.isNULL( Coords(0,0) ) );
    assert( r.isNULL( Coords(0,2) ) );
    assert( r.columnNum( "field_name" ) == 1 );

    string sql_query3 = "listen test_notify; notify test_notify";
    r = conn.exec( sql_query3 );
    assert( conn.getNextNotify.name == "test_notify" );
}
