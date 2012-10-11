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
    immutable struct Value
    {
        private ubyte[] value;
        debug private dpq2.libpq.valueFormat format;
        
        version(Debug){} else
        this( immutable (ubyte)* value, size_t valueSize ) immutable
        {
            this.value = value[0..valueSize];
        }
        
        debug
        this( immutable (ubyte)* value, size_t valueSize, dpq2.libpq.valueFormat f ) immutable
        {
            this.value = value[0..valueSize];
            format = f;
        }
        
        this( immutable (ubyte[]) value ) immutable
        {
            this.value = value;
            debug format = valueFormat.BINARY;
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
            assert( value.length == T.sizeof, "Value value length isn't equal to type size" );
            
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
        
        immutable (Array*) asArray()
        {
            return new Array( &this );
        }
    }
        
    immutable struct Array
    {
        Oid OID;
        int nDims; /// Number of dimensions
        int[] dimsSize; /// Dimensions sizes info
        size_t nElems; /// Total elements
        
        private
        {
            Value* cell;
            ubyte[][] elements;
            bool[] elementIsNULL;
            
            struct arrayHeader_net
            {
                ubyte[4] ndims; // number of dimensions of the array
                ubyte[4] dataoffset_ign; // offset for data, removed by libpq. may be it is conteins isNULL flag!
                ubyte[4] OID; // element type OID
            }

            struct Dim_net // network byte order
            {
                ubyte[4] dim_size; // number of elements in dimension
                ubyte[4] lbound; // unknown
            }
        }
        
        this( immutable(Value*) c ) immutable
        {
            cell = c;
            debug enforce( cell.format == valueFormat.BINARY, "Format of the column is not binary" );
            
            arrayHeader_net* h = cast(arrayHeader_net*) cell.value.ptr;
            nDims = bigEndianToNative!int(h.ndims);
            OID = bigEndianToNative!Oid(h.OID);
            
            // TODO: here is need exception, not enforce
            enforce( nDims > 0, "Dimensions number must be more than 0" );
            
            auto ds = new int[ nDims ];
            
            // Recognize dimensions of array
            int n_elems = 1;
            for( auto i = 0; i < nDims; ++i )
            {
                Dim_net* d = (cast(Dim_net*) (h + 1)) + i;
                
                int dim_size = bigEndianToNative!int( d.dim_size );
                int lbound = bigEndianToNative!int(d.lbound);

                // FIXME: What is lbound in postgresql array reply?
                enforce( lbound == 1, "Please report if you came across this error." );
                assert( dim_size > 0 );
                
                ds[i] = dim_size;
                n_elems *= dim_size;
            }
            
            nElems = n_elems;
            dimsSize = ds.idup;
            
            auto elements = new immutable (ubyte)[][ nElems ];
            auto elementIsNULL = new bool[ nElems ];
            
            // Looping through all elements and fill out index of them
            auto curr_offset = arrayHeader_net.sizeof + Dim_net.sizeof * nDims;            
            for(uint i = 0; i < n_elems; ++i )
            {
                ubyte[int.sizeof] size_net;
                size_net = cell.value[ curr_offset .. curr_offset + size_net.sizeof ];
                uint size = bigEndianToNative!uint( size_net );
                if( size == size.max ) // NULL magic number
                {
                    elementIsNULL[i] = true;
                    size = 0;
                }
                else
                {
                    elementIsNULL[i] = false;
                }
                curr_offset += size_net.sizeof;
                elements[i] = cell.value[curr_offset .. curr_offset + size];
                curr_offset += size;
            }
            this.elements = elements.idup;
            this.elementIsNULL = elementIsNULL.idup;
        }
        
        /// Returns Value struct
        immutable (Value)* getValue( ... ) immutable
        {
            auto n = coords2Serial( _argptr, _arguments );
            return new Value( elements[n] );
        }
        
        /// Value NULL checking
        bool isNULL( ... ) immutable
        {
            auto n = coords2Serial( _argptr, _arguments );
            return elementIsNULL[n];
        }
        
        size_t coords2Serial( void *_argptr, TypeInfo[] _arguments ) immutable
        {
            assert( _arguments.length > 0, "Number of the arguments must be more than 0" );
            
            // Variadic args parsing
            auto args = new int[ _arguments.length ];
            // TODO: here is need exception, not enforce
            enforce( nDims == args.length, "Mismatched dimensions number in arguments and server reply" );
            
            for( uint i; i < args.length; ++i )
            {
                assert( _arguments[i] == typeid(int) );
                args[i] = va_arg!(int)(_argptr);
                enforce( dimsSize[i] > args[i] ); // TODO: here is need exception, not enforce
            }
            
            // Calculates serial number of the element
            auto inner = args.length - 1; // inner dimension
            auto element_num = args[inner]; // serial number of the element
            uint s = 1; // perpendicular to a vector which size is calculated currently
            for( auto i = inner; i > 0; --i )
            {
                s *= dimsSize[i];
                element_num += s * args[i-1];
            }
            
            assert( element_num <= nElems );
            return element_num;
        }
    }
    
    package this(immutable PGresult* r) immutable nothrow
    {
        res = r;
        enforceEx!OutOfMemoryError(res, "Can't write query result");
        if(!(status == ExecStatusType.PGRES_COMMAND_OK ||
             status == ExecStatusType.PGRES_TUPLES_OK))
        {
            throw new exception( exception.exceptionTypes.UNDEFINED_FIXME,
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
        assertCol( colNum );
        return PQfformat(res, colNum);
    }
    
    /// Returns column Oid
    @property Oid OID( size_t colNum )
    {
        assertCol( colNum );
        return PQftype(res, colNum);
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

    immutable (Value)* getValue( const Coords c )
    {
        assertCoords(c);
        
        auto v = PQgetvalue(res, c.Row, c.Col);
        auto s = size( c );

        debug
            auto r = new Value( v, s, columnFormat( c.Col ) );
        else
            auto r = new Value( v, s );
        
        return r;
    }
    
    /// Returns pointer to cell
    immutable (Value)* opIndex( size_t Row, size_t Col )
    {
        return getValue( Coords( Row, Col ) );
    }
    
    /// Returns cell size
    size_t size( const Coords c ) 
    {
        assertCoords(c);
        return PQgetlength(res, c.Row, c.Col);
    }
    
    /// Value NULL checking
    bool isNULL( size_t Row, size_t Col ) 
    {
        assertCoords(Coords(Row, Col));
        return PQgetisnull(res, Row, Col) != 0;
    }
    
    private string resultErrorMessage()
    {
        return to!string( PQresultErrorMessage(res) );
    }
    
    private void assertCol( size_t c )
    {
        assert( c < columnCount, to!string(c)~" col is out of range 0.."~to!string(columnCount-1)~" of result cols" );
    }
    
    private void assertCoords( const Coords c )
    {
        assert( c.Row < rowCount, to!string(c.Row)~" row is out of range 0.."~to!string(rowCount-1)~" of result rows" );
        assertCol( c.Col );
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
        UNDEFINED_FIXME /// Undefined, need to find and fix it
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
    assert( !e.isNULL(0, 0) );
    assert( e.isNULL(2, 0) );
    assert( e.columnNum( "field_name" ) == 1 );

    // Value properties test
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
        "array[[[1,  2, 3], "
               "[4,  5, 6]], "
               
              "[[7,  8, 9], "
              "[10, 11,12]], "
              
              "[[13,14,NULL], "
               "[16,17,18]]]::integer[], "
        "NULL";


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
    
    auto v = r[0,11];
    assert( r.OID(11) == 1007 ); // int4 array
    auto a = v.asArray;
    assert( a.OID == 23 ); // -2 billion to 2 billion integer, 4-byte storage
    assert( a.getValue(2,1,2).as!PGinteger == 18 );
    assert( a.isNULL(2,0,2) );
    assert( !a.isNULL(2,1,2) );
    
    assert( r.isNULL(0, 12) );
    assert( !r.isNULL(0, 9) );
    
    // Notifies test
    auto n = conn.exec( "listen test_notify; notify test_notify" );
    assert( conn.getNextNotify.name == "test_notify" );
}
