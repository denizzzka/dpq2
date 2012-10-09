module dpq2.answer;

// for rdmd
pragma(lib, "pq");
pragma(lib, "com_err");

@trusted:

import dpq2.libpq;
public import dpq2.query;

import std.string: toStringz;
import std.exception;
import core.exception;
import std.traits;
import std.bitmanip: bigEndianToNative;
import std.datetime;

// Supported PostgreSQL binary types
alias short   PGsmallint; /// smallint
alias int     PGinteger; /// integer
alias long    PGbigint; /// bigint
alias float   PGreal; /// real
alias double  PGdouble_precision; /// double precision
alias string  PGtext; /// text
alias immutable ubyte[] PGbytea; /// bytea
alias SysTime PGtime_stamp; /// time stamp with/without timezone


/// Answer
immutable class answer
{      
    private PGresult* res;
    
    /// Result table's cell coordinates 
    struct Coords
    {
        size_t Row; /// Row
        size_t Col; /// Column
    }

    /// Result table's cell
    immutable struct Cell
    {
        private ubyte[] value;
        debug private dpq2.libpq.valueFormat format;
        
        version(Debug){} else
        this( immutable (ubyte)* value, size_t valueSize ) immutable
        {
            Cell.value = value[0..valueSize];
        }
        
        debug
        this( immutable (ubyte)* value, size_t valueSize, dpq2.libpq.valueFormat f ) immutable
        {
            Cell.value = value[0..valueSize];
            format = f;
        }

        /// Returns value as bytes from binary formatted field
        @property T as(T)()
        if( is( T == immutable(ubyte[]) ) )
        {
            debug enforce( format == valueFormat.BINARY, "Format of the column is not binary" );
            return value;
        }

        /// Returns cell value as native string type
        @property T as(T)()
        if( isSomeString!(T) )
        {
            return to!T( cast(immutable(char)*) value.ptr );
        }
        
        /// Returns cell value as native integer or decimal values
        ///
        /// Postgres type "numeric" is oversized and not supported by now
        @property T as(T)()
        if( isNumeric!(T) )
        {
            debug enforce( format == valueFormat.BINARY, "Format of the column is not binary" );
            assert( value.length == T.sizeof, "Cell size isn't equal to type size" );
            
            ubyte[T.sizeof] s = value[0..T.sizeof];
            return bigEndianToNative!(T)( s );
        }
        
        /// Returns cell value as native date and time
        @property T* as(T)()
        if( is( T == SysTime ) )
        {
            ulong pre_time = as!(ulong)();
            // UTC because server always sends binary timestamps in UTC, not in TZ
            return new SysTime( pre_time * 10, UTC() );
        }
        
        
        struct Array
        {
            // (network order)
            ubyte _ndims[4]; // number of dimensions of the array
            ubyte _dataoffset_ign[4]; // offset for data, removed by libpq
            ubyte _OID[4]; // element type OID
            
            @property int ndims() { return bigEndianToNative!int(_ndims); }
            @property Oid OID() { return bigEndianToNative!int(_OID); }
        }

        struct Dim
        {
            ubyte _dim_size[4]; // Number of elements in dimension
            ubyte _lbound[4]; // Index of first element

            @property int dim_size() { return bigEndianToNative!int(_dim_size); }
            @property int lbound() { return bigEndianToNative!int(_lbound); }
        }
        
        auto array_cell( size_t x )
        {
            import std.stdio;
            Array* r = cast(Array*) value.ptr;

            assert( r.ndims > 0 );

            writeln( "Dim_num: ", r.ndims );
            writeln( "OID: ", r.OID );
            
            
            for( auto i = 0; i < r.ndims; ++i )
            {
                Dim* d = (cast(Dim*) (r + 1)) + i;
                writeln( "Dimension number: ", i );
                writeln( "size of dimension: ", d.dim_size );
                writeln( "lbound: ", d.lbound );
            }
            
            writeln( "bytea content: ", value);
            
            return 1;
        }
    }
    
    package this(immutable PGresult* r) immutable
    {
        res = r;
        enforceEx!OutOfMemoryError(res, "Can't write query result");
        if(!(status == ExecStatusType.PGRES_COMMAND_OK ||
             status == ExecStatusType.PGRES_TUPLES_OK))
        {
            throw new exception( exception.exceptionTypes.UNDEFINED_FIX_IT,
                resultErrorMessage~" ("~to!string(status)~")" );
        }
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
    @property string cmdStatus()
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

    private immutable (Cell)* getValue( const Coords c )
    {
        assertCoords(c);
        
        auto v = PQgetvalue(res, c.Row, c.Col);
        auto s = size( c );

        debug
            auto r = new Cell( v, s, columnFormat( c.Col ) );
        else
            auto r = new Cell( v, s );
        
        return r;
    }
    
    /// Returns pointer to cell
    immutable (Cell)* opIndex( size_t Row, size_t Col )
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
    
    private string resultErrorMessage()
    {
        return to!string( PQresultErrorMessage(res) );
    }
    
    private void assertCoords( const Coords c )
    {
        assert( c.Row < rowCount, to!string(c.Row)~" row is out of range 0.."~to!string(rowCount-1)~" of result rows" );
        assert( c.Col < columnCount, to!string(c.Col)~" col is out of range 0.."~to!string(columnCount-1)~" of result cols" );
    }    

    invariant()
    {
        assert( res != null );
    }
}


/// Notify
immutable class notify
{
    private PGnotify* n;

    this( immutable (PGnotify*) pgn ) immutable
    {
        n = pgn;
        enforceEx!OutOfMemoryError(n, "Can't write notify");
    }
        
    ~this()
    {
        PQfreemem( cast(void*) n );
    }

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


/// Exception
immutable class exception : Exception
{    
    /// Exception types
    enum exceptionTypes
    {
        COLUMN_NOT_FOUND, /// Column not found
        UNDEFINED_FIX_IT /// Undefined, need to find and fix it
    }
    
    exceptionTypes type; /// Exception type
    
    this( exceptionTypes t, string msg )
    {
        type = t;
        super( msg, null, null );
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

    auto e = conn.exec( sql_query );
    
    alias answer.Coords Coords;

    assert( e.rowCount == 3 );
    assert( e.columnCount == 4);
    assert( e.columnFormat(2) == valueFormat.TEXT );

    assert( e[1,2].as!PGtext == "456" );
    assert( !e.isNULL( Coords(0,0) ) );
    assert( e.isNULL( Coords(0,2) ) );
    assert( e.columnNum( "field_name" ) == 1 );

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
        "'first line\nsecond line'::text, "
        r"E'\\x44 20 72 75 6c 65 73 00 21'::bytea"; // "D rules\x00!" (ASCII)

    auto r = conn.exec( p );

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
    assert( r[0,10].as!PGbytea == [0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21] ); // "D rules\x00!" (ASCII)

    // Notifies test
    auto n = conn.exec( "listen test_notify; notify test_notify" );
    assert( conn.getNextNotify.name == "test_notify" );
}
