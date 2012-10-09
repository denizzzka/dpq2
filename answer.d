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
import core.vararg;

// Supported PostgreSQL binary types
alias short   PGsmallint; /// smallint
alias int     PGinteger; /// integer
alias long    PGbigint; /// bigint
alias float   PGreal; /// real
alias double  PGdouble_precision; /// double precision
alias string  PGtext; /// text
alias immutable ubyte[] PGbytea; /// bytea
alias SysTime PGtime_stamp; /// time stamp with/without timezone

debug import std.stdio;

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
            ubyte[4] _ndims; // number of dimensions of the array
            ubyte[4] _dataoffset_ign; // offset for data, removed by libpq. may be it is conteins isNULL flag!
            ubyte[4] _OID; // element type OID
            
            @property int ndims() { return bigEndianToNative!int(_ndims); }
            @property Oid OID() { return bigEndianToNative!int(_OID); }
        }

        struct Dim_net // Network byte order
        {
            ubyte[4] _size; // Number of elements in dimension
            ubyte[4] _lbound; // Index of first element

            @property int dim_size() { return bigEndianToNative!int(_size); }
            @property int lbound() { return bigEndianToNative!int(_lbound); }
        }

        struct Dim
        {
            int dim_size; // Number of elements in dimension
            int lbound; // Index of first element
        }
        
        struct Elem
        {
            int size;
            ubyte* value;
        }
        
        auto array_cell( ... )
        {
            import std.stdio;
            
            writeln( _arguments.length );
            assert( _arguments.length > 0, "Number of the arguments must be more than 0" );
            
            // Arguments array
            auto args = new int[ _arguments.length ];
            for( int i; i < args.length; ++i )
            {
                assert( _arguments[i] == typeid(int) );
                args[i] = va_arg!(int)(_argptr);
            }
            
            // Array header
            Array* h = cast(Array*) value.ptr;
            
            // TODO: here is need exception, not enforce
            enforce( h.ndims > 0, "Dimensions number must be more than 0" );
            enforce( h.ndims == _arguments.length, "Mismatched dimensions number in the arguments and server reply" );
            
            writeln( "Dim_num: ", h.ndims );
            writeln( "OID: ", h.OID );
            
            size_t n_elems = 1;
            auto ds = new Dim[ h.ndims ];
            
            for( auto i = 0; i < h.ndims; ++i )
            {
                Dim_net* d = (cast(Dim_net*) (h + 1)) + i;
                assert( d.dim_size > 0 );
                assert( d.dim_size > args[i] );
                // FIXIT: What is lbound in postgresql array reply?
                enforce( d.lbound == 1, "Please report if you came across this error." );
                
                ds[i].dim_size = d.dim_size;
                ds[i].lbound = d.lbound;
                n_elems *= d.dim_size;
            }

            
            Elem[] res = new Elem[ n_elems ];           
            auto data_offset = Array.sizeof + Dim.sizeof * h.ndims;
            

            // Calculates serial number of the element
            auto inner = args.length - 1; // Inner dimension
            auto element_num = args[inner]; // Serial number of the element
            int s = 1; // Perpendicular to vector which size is calculated currently
            for( auto i = inner; i > 0; --i )
            {
                writeln("i: ", i );
                s *= ds[i].dim_size;
                element_num += s * args[i-1];
            }
            
            assert( element_num <= n_elems );
            
            // Looping through all elements and fill out index of them
            auto curr_offset = data_offset;
            
            for(int i = 0; i < n_elems; ++i )
            {
                ubyte[4] size_net;
                size_net = value[ curr_offset .. curr_offset + size_net.sizeof ];
                res[i].size = bigEndianToNative!int( size_net );
                res[i].value = cast(ubyte*) &value[curr_offset + size_net.sizeof];
                
                curr_offset += size_net.sizeof + res[i].size; //TODO: избавиться от лишней итерации этого в конце цикла
            }
            
            writeln( res );
            return res[element_num];
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
        r"E'\\x44 20 72 75 6c 65 73 00 21'::bytea, " // "D rules\x00!" (ASCII)
        r"array[[1, 2], "
              r"[3, 4]] ";


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

    auto v = r[0,11].array_cell(1, 1);
    assert( v.size == 4 );
    ubyte[4] v1 = *(cast(ubyte[4]*) v.value);
    PGinteger v2 = bigEndianToNative!PGinteger( v1 );
    
    writeln( "5: (unused) ", v2 );
    
    // Notifies test
    auto n = conn.exec( "listen test_notify; notify test_notify" );
    assert( conn.getNextNotify.name == "test_notify" );
}
