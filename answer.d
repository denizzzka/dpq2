module dpq2.answer;
@trusted:

import dpq2.libpq;
public import dpq2.query;

import std.string: toStringz;
import std.exception;
import core.exception;
import std.traits;
import std.bitmanip;
import std.datetime;

// Supported PostgreSQL binary types
alias short   PGsmallint; /// smallint
alias int     PGinteger; /// integer
alias long    PGbigint; /// bigint
alias float   PGreal; /// real
alias double  PGdouble_precision; /// double precision
alias string  PGtext; /// text
alias SysTime PGtime_stamp; /// time stamp with/without timezone
alias ubyte[] PGbytea; /// bytea

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
    //immutable 
    struct Cell
    {
        private immutable (ubyte)* val;
        private size_t size; // currently used only for bin, text fields have 0 end byte
        debug dpq2.libpq.valueFormat format;
        
        this( immutable (ubyte)* value, size_t valueSize )
        {
            val = value;
            size = valueSize;
        }
        
        /// Returns value as string from text formatted field
        @property string str() const
        {
            debug enforce( format == valueFormat.TEXT, "Format of the column is not text" );
            return as!string();
        }

        /// Returns value as ubytes array from binary formatted field
        @property immutable (ubyte)[] bin() const
        {
            debug enforce( format == valueFormat.BINARY, "Format of the column is not binary" );
            return val[0..size];
        }

        /// Returns cell value as native string type
        @property T as(T)() const
        if( isSomeString!(T) )
        {
            return to!T( cast(immutable(char)*) val );
        }
        
        /// Returns cell value as native integer or decimal values
        ///
        /// Postgres type "numeric" is oversized and not supported by now
        @property T as(T)() const
        if( isNumeric!(T) )
        {
            assert( size == T.sizeof, "Cell size isn't equal to type size" );
            
            ubyte[T.sizeof] s = val[0..T.sizeof];
            return bigEndianToNative!(T)( s );
        }
        
        /// Returns cell value as native date and time
        @property T* as(T)() const
        if( is( T == SysTime ) )
        {
            ulong pre_time = as!(ulong)();
            // UTC because server always sends binary timestamps in UTC, not in TZ
            return new SysTime( pre_time * 10, UTC() );
        }
    }
    
    private PGresult* res;
    
    private this(){}
    
    package this(PGresult* r)
    {
        res = r;
        enforceEx!OutOfMemoryError(r, "Can't write query result");
        if(!(status == ExecStatusType.PGRES_COMMAND_OK ||
             status == ExecStatusType.PGRES_TUPLES_OK))
            throw new exception();
    }
    
    ~this() {
        PQclear(res);
    }

    ExecStatusType status() 
    {
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
    dpq2.libpq.valueFormat columnFormat( size_t colNum )
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
        
        Cell* r;
        auto v = PQgetvalue(res, c.Row, c.Col);
        auto s = size( c );
                
        static if( is( Cell.format ) )
            r = new Cell( v, s, columnFormat( c.Col ));
        else
            r = new Cell( v, s);
        
        return r;
    }
    
    /// Returns pointer to cell
    const (Cell)* opIndex( size_t Row, size_t Col )
    {
        return getValue( Coords( Row, Col ) );
    }
    
    /// Returns cell size
    size_t size( const Coords c ) 
    {
        assertCoords(c);
        return PQgetlength(res, c.Row, c.Col);
    }
    
    /// Cell NULL checking
    bool isNULL( const Coords c ) 
    {
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

/// Notify
class notify
{
    private PGnotify* n;

    this(){}
    this( PGnotify* n ) { this.n = n; }
    ~this() { PQfreemem(n); }

    /// Returns notification condition name
    @property string name() { return to!string( n.relname ); }

    /// Returns notification parameter
    @property string extra() { return to!string( n.extra ); }

    /// Returns process ID of notifying server process
    @property size_t pid() { return n.be_pid; }

    invariant()
    {
        assert( n != null );
    }
}

void _unittest( string connParam )
{
    // Answer properies test
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


    // Cell properties test
    static queryArg arg;
    queryParams p;
    p.resultFormat = valueFormat.BINARY;
    p.sqlCommand = "SELECT "
        "-32761::smallint, "
        "-2147483646::integer, "
        "-9223372036854775806::bigint, "
        "-12.3456::real, "
        "-1234.56789012345::double precision, "
        "'2012-10-04 11:00:21.227803+08'::timestamp with time zone, "
        "'2012-10-04 11:00:21.227803+08'::timestamp without time zone, "
        "'2012-10-04 11:00:21.227803+00'::timestamp with time zone, "
        "'2012-10-04 11:00:21.227803+00'::timestamp without time zone, "
        "'first line\nsecond line'::text";

    r = conn.exec( p );

    assert( r[0,0].as!PGsmallint == -32761 );
    assert( r[0,1].as!PGinteger == -2147483646 );
    assert( r[0,2].as!PGbigint == -9223372036854775806 );
    assert( r[0,3].as!PGreal == -12.3456f );
    assert( r[0,4].as!PGdouble_precision == -1234.56789012345 );

    assert( r[0,5].as!PGtime_stamp.toSimpleString() == "0013-Oct-05 03:00:21.227803Z" );
    assert( r[0,6].as!PGtime_stamp.toSimpleString() == "0013-Oct-05 11:00:21.227803Z" );
    assert( r[0,7].as!PGtime_stamp.toSimpleString() == "0013-Oct-05 11:00:21.227803Z" );
    assert( r[0,8].as!PGtime_stamp.toSimpleString() == "0013-Oct-05 11:00:21.227803Z" );

    assert( r[0,9].as!PGtext == "first line\nsecond line" );


    // Notifies test
    r = conn.exec( "listen test_notify; notify test_notify" );
    assert( conn.getNextNotify.name == "test_notify" );
}
