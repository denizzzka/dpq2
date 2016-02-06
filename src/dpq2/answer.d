module dpq2.answer;

@trusted:

public import dpq2.query;
public import dpq2.types.native;
public import dpq2.types.bson;
import dpq2.oids;

import derelict.pq.pq;

import core.vararg;
import std.string: toStringz;
import std.exception: enforceEx;
import core.exception: OutOfMemoryError, AssertError;
import std.bitmanip: bigEndianToNative;
import std.typecons: Nullable;

/// Result table's cell coordinates 
struct Coords
{
    size_t row; /// Row
    size_t col; /// Column
}

/// Answer
class Answer
{
    private const (PGresult*) res;

    nothrow invariant()
    {
        assert( res != null );
    }
        
    package this(PGresult* r) nothrow
    {
        res = r;
    }
    
    ~this()
    {
        if( res )
        {
            PQclear(res);
        }
        else
            assert( true, "double free!" );
    }
    
    package void checkAnswerForErrors() const
    {
        cast(void) enforceEx!OutOfMemoryError(res, "Can't write query result");

        switch(status)
        {
            case PGRES_COMMAND_OK:
            case PGRES_TUPLES_OK:
                break;

            case PGRES_EMPTY_QUERY:
                throw new AnswerException(ExceptionType.EMPTY_QUERY,
                    "Empty query", __FILE__, __LINE__);

            case PGRES_FATAL_ERROR:
                throw new AnswerException(ExceptionType.FATAL_ERROR,
                    resultErrorMessage, __FILE__, __LINE__);

            default:
                throw new AnswerException(ExceptionType.UNDEFINED_FIXME,
                    "Please report if you came across this error! status="~to!string(status)~"\r\n"~
                    resultErrorMessage, __FILE__, __LINE__);
        }
    }
    
    @property
    ExecStatusType status() const
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
    @property string cmdStatus() const
    {
        return to!string( PQcmdStatus(res) );
    }

    /// Returns row count
    @property size_t rowCount() const { return PQntuples(res); }

    /// Returns column count
    @property size_t columnCount() const { return PQnfields(res); }

    /// Returns column format
    ValueFormat columnFormat( const size_t colNum ) const
    {
        assertCol( colNum );
        return cast(ValueFormat) PQfformat(res, cast(int)colNum);
    }
    
    /// Returns column Oid
    @property OidType OID( size_t colNum ) const
    {
        assertCol( colNum );

        return oid2oidType(PQftype(res, cast(int)colNum));
    }

    @property bool isArray( const size_t colNum ) const
    {
        assertCol(colNum);

        return dpq2.oids.isArray(OID(colNum));
    }

    /// Returns column number by field name
    size_t columnNum( string columnName ) const
    {    
        size_t n = PQfnumber(res, toStringz(columnName));

        if( n == -1 )
            throw new AnswerException(ExceptionType.COLUMN_NOT_FOUND,
                    "Column '"~columnName~"' is not found", __FILE__, __LINE__);

        return n;
    }
    
    /// Returns pointer to row of cells
    Row opIndex(in size_t row) const
    {
        return const Row( this, row );
    }
    
    @property
    debug override string toString() const
    {
        return "Rows: "~to!string(rowCount)~" Columns: "~to!string(columnCount);
    }
    
    @property
    private string resultErrorMessage() const
    {
        return to!string( PQresultErrorMessage(res) );
    }
    
    private void assertCol( const size_t c ) const
    {
        if(!(c < columnCount))
            throw new AnswerException(
                ExceptionType.OUT_OF_RANGE,
                "Column "~to!string(c)~" is out of range 0.."~to!string(columnCount)~" of result columns",
                __FILE__, __LINE__
            );
    }
    
    private void assertRow( const size_t r ) const
    {
        if(!(r < rowCount))
            throw new AnswerException(
                ExceptionType.OUT_OF_RANGE,
                "Row "~to!string(r)~" is out of range 0.."~to!string(rowCount)~" of result rows",
                __FILE__, __LINE__
            );
    }
    
     private void assertCoords( const Coords c ) const
    {
        assertRow( c.row );
        assertCol( c.col );
    }    
    
    package size_t currRow;
    
    @property Row front(){ return this[currRow]; }
    @property void popFront(){ ++currRow; }
    @property bool empty(){ return currRow >= rowCount; }
}

/// Represents one row from the answer table
const struct Row
{
    private const Answer answer;
    private immutable size_t row;
    
    this( const Answer answer, size_t row )
    {
        answer.assertRow( row );
        
        this.answer = answer;
        this.row = row;
    }
    
    /// Returns cell size
    @property
    size_t size( const size_t col ) const
    {
        answer.assertCol(col);
        return PQgetlength(answer.res, cast(int)row, cast(int)col);
    }
    
    /// Value NULL checking
    /// Do not confuse it with Nullable's isNull property
    @property
    bool isNULL( const size_t col ) const
    {
        answer.assertCol(col);

        return PQgetisnull(answer.res, cast(int)row, cast(int)col) != 0;
    }

    Nullable!Value opIndex(in size_t col) const
    {
        answer.assertCoords( Coords( row, col ) );
        
        auto v = PQgetvalue(answer.res, cast(int)row, cast(int)col);
        auto s = size( col );
        
        Nullable!Value r;
        
        if(!isNULL(col))
            r = Value(v, s, answer.columnFormat(col), answer.OID(col));
        
        return r;
    }
    
    Nullable!Value opIndex(in string column) const
    {
        return opIndex(columnNum(column));
    }
    
    /// Returns column number by field name
    size_t columnNum( string columnName ) const
    {
        return answer.columnNum( columnName );
    }
    
    /// Returns column count
    @property size_t columnCount() const{ return answer.columnCount(); }
    
    @property
    debug string toString() const
    {
        return "Columns: "~to!string(columnCount);
    }
}

/// Link to the cell of the answer table
struct Value
{
    package ValueFormat format;
    package OidType oidType;
    package ubyte[] value;

    this( const (ubyte)* value, size_t valueSize, ValueFormat f, OidType t )
    {
        this.value = cast(ubyte[]) value[0..valueSize];
        format = f;
        oidType = t;
    }
    
    this( const ubyte[] value, OidType t )
    {
        this.value = cast(ubyte[]) value;
        format = ValueFormat.BINARY;
        oidType = t;
    }

    @property
    bool isArray() const
    {
        return dpq2.oids.isArray(oidType);
    }

    @property
    Array asArray() const
    {
        if(!isArray)
            throw new AnswerException(ExceptionType.NOT_ARRAY,
                "Format of the column is "~to!string(oidType)~", isn't array",
                __FILE__, __LINE__
            );

        return const Array(this);
    }
}

/// Link to the cell of the answer table
const struct Array
{
    OidType OID;
    int nDims; /// Number of dimensions
    int[] dimsSize; /// Dimensions sizes info
    size_t nElems; /// Total elements

    private ubyte[][] elements;
    private bool[] elementIsNULL;

    this(in Value cell)
    {
        if(!(cell.format == ValueFormat.BINARY))
            throw new AnswerException(ExceptionType.NOT_BINARY,
                msg_NOT_BINARY, __FILE__, __LINE__);

        struct ArrayHeader_net // network byte order
        {
            ubyte[4] ndims; // number of dimensions of the array
            ubyte[4] dataoffset_ign; // offset for data, removed by libpq. may be it contains isNULL flag!
            ubyte[4] OID; // element type OID
        }

        struct Dim_net // network byte order
        {
            ubyte[4] dim_size; // number of elements in dimension
            ubyte[4] lbound; // unknown
        }

        ArrayHeader_net* h = cast(ArrayHeader_net*) cell.value.ptr;
        nDims = bigEndianToNative!int(h.ndims);
        OID = oid2oidType(bigEndianToNative!Oid(h.OID));

        if(!(nDims > 0))
            throw new AnswerException(ExceptionType.SMALL_DIMENSIONS_NUM,
                "Dimensions number is too small, it must be positive value",
                __FILE__, __LINE__
            );

        auto ds = new int[ nDims ];
        
        // Recognize dimensions of array
        int n_elems = 1;
        for( auto i = 0; i < nDims; ++i )
        {
            Dim_net* d = (cast(Dim_net*) (h + 1)) + i;
            
            int dim_size = bigEndianToNative!int( d.dim_size );
            int lbound = bigEndianToNative!int(d.lbound);

            // FIXME: What is lbound in postgresql array reply?
            if(!(lbound == 1))
                throw new AnswerException(ExceptionType.UNDEFINED_FIXME,
                    "Please report if you came across this error! lbound=="~to!string(lbound),
                    __FILE__, __LINE__
                );

            assert( dim_size > 0 );
            
            ds[i] = dim_size;
            n_elems *= dim_size;
        }
        
        nElems = n_elems;
        dimsSize = ds.idup;
        
        auto elements = new const (ubyte)[][ nElems ];
        auto elementIsNULL = new bool[ nElems ];
        
        // Looping through all elements and fill out index of them
        auto curr_offset = ArrayHeader_net.sizeof + Dim_net.sizeof * nDims;            
        for(uint i = 0; i < n_elems; ++i )
        {
            ubyte[int.sizeof] size_net;
            size_net[] = cell.value[ curr_offset .. curr_offset + size_net.sizeof ];
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
        this.elements = elements.dup;
        this.elementIsNULL = elementIsNULL.idup;
    }
    
    /// Returns Value struct by index
    Nullable!Value opIndex(int n) const
    {
        return getValue(n);
    }
    
    /// Returns Value struct
    /// Useful for multidimensional arrays
    Nullable!Value getValue( ... ) const
    {
        auto n = coords2Serial( _argptr, _arguments );
        
        Nullable!Value r;
        
        if(!elementIsNULL[n])
            r = Value(elements[n], OID);
        
        return r;
    }
    
    /// Value NULL checking
    bool isNULL( ... )
    {
        auto n = coords2Serial( _argptr, _arguments );
        return elementIsNULL[n];
    }

    private size_t coords2Serial( va_list _argptr, TypeInfo[] _arguments )
    {
        assert( _arguments.length > 0, "Number of the arguments must be more than 0" );
        
        // Variadic args parsing
        auto args = new int[ _arguments.length ];

        if(!(nDims == args.length))
            throw new AnswerException(
                ExceptionType.OUT_OF_RANGE,
                "Mismatched dimensions number in arguments and server reply",
                __FILE__, __LINE__
            );

        for( uint i; i < args.length; ++i )
        {
            assert( _arguments[i] == typeid(int) );
            args[i] = va_arg!(int)(_argptr);

            if(!(dimsSize[i] > args[i]))
                throw new AnswerException(
                    ExceptionType.OUT_OF_RANGE,
                    "Out of range",
                    __FILE__, __LINE__
                );
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

/// Notify
class Notify
{
    private immutable PGnotify* n;

    this(immutable PGnotify* pgn )
    {
        n = pgn;
        cast(void) enforceEx!OutOfMemoryError(n, "Can't write notify");
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

    nothrow invariant() 
    {
        assert( n != null );
    }
}

immutable msg_NOT_BINARY = "Format of the column is not binary";

/// Exception types
enum ExceptionType
{
    UNDEFINED_FIXME, /// Undefined, please report if you came across this error
    COLUMN_NOT_FOUND, /// Column is not found
    OUT_OF_RANGE,
    NOT_ARRAY, /// Format of the column isn't array
    NOT_BINARY, /// Format of the column isn't binary
    NOT_TEXT, /// Format of the column isn't text string
    NOT_IMPLEMENTED, /// Support of this type isn't implemented (or format isn't matches to specified D type)
    SMALL_DIMENSIONS_NUM,
    SIZE_MISMATCH,
    EMPTY_QUERY,
    FATAL_ERROR
}

/// Exception
class AnswerException : Dpq2Exception
{    
    ExceptionType type; /// Exception type
    
    this(ExceptionType t, string msg, string file, size_t line)
    {
        type = t;
        super(msg, file, line);
    }
}

void _integration_test( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    {
        string sql_query =
        "select now() as time,  'abc'::text as field_name,   123,  456.78\n"~
        "union all\n"~

        "select now(),          'def'::text,                 456,  910.11\n"~
        "union all\n"~

        "select NULL,           'ijk_АБВГД'::text,           789,  12345.115345";

        auto e = conn.exec(sql_query);

        assert( e[1][2].as!PGtext == "456" );
        assert( e[2][1].as!PGtext == "ijk_АБВГД" );
        assert( !e[0].isNULL(0) );
        assert( e[2].isNULL(0) );
        assert( e.columnNum( "field_name" ) == 1 );
        assert( e[1]["field_name"].as!PGtext == "def" );
    }

    QueryParams p;
    p.resultFormat = ValueFormat.BINARY;
    p.sqlCommand = "SELECT "~
        "-32761::smallint, "~
        "-2147483646::integer, "~
        "'first line\nsecond line'::text, "~
        "array[[[1,  2, 3], "~
               "[4,  5, 6]], "~
               
              "[[7,  8, 9], "~
              "[10, 11,12]], "~
              
              "[[13,14,NULL], "~
               "[16,17,18]]]::integer[] as test_array, "~
        "NULL,"~
        "array[11,22,NULL,44]::integer[] as small_array";

    auto r = conn.exec( p );

    {
        assert( r[0].isNULL(4) );
        assert( !r[0].isNULL(2) );

        assert( r.OID(3) == OidType.Int4Array );
        assert( r.isArray(3) );
        assert( !r.isArray(2) );
        auto v = r[0]["test_array"];
        assert( v.isArray );
        assert( !r[0][2].isArray );
        auto a = v.asArray;
        assert( a.OID == OidType.Int4 );
        assert( a.getValue(2,1,2).as!PGinteger == 18 );
        assert( a.isNULL(2,0,2) );
        assert( !a.isNULL(2,1,2) );
        assert( r[0]["small_array"].asArray[1].as!PGinteger == 22 );
        assert( r[0]["small_array"].asArray[2].isNull );

        {
            bool isNullFlag = false;
            try
                cast(void) r[0][4].as!PGsmallint;
            catch(AssertError)
                isNullFlag = true;
            finally
                assert(isNullFlag);
        }
    }

    // Notifies test
    conn.exec( "listen test_notify; notify test_notify" );
    assert( conn.getNextNotify.name == "test_notify" );
    
    // Async query test 1
    conn.sendQuery( "select 123; select 456; select 789" );
    while( conn.getResult() !is null ){}
    assert( conn.getResult() is null ); // removes null answer at the end

    // Async query test 2
    conn.sendQuery( p );
    while( conn.getResult() !is null ){}
    assert( conn.getResult() is null ); // removes null answer at the end
    
    // Range test
    foreach( elem; r )
    {
        assert( elem[0].as!PGsmallint == -32_761 );
    }

    destroy(r);

    {
        bool exceptionFlag = false;

        try conn.exec("WRONG SQL QUERY");
        catch(AnswerException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 20); // error message check
        }
        finally
            assert(exceptionFlag);
    }
}
