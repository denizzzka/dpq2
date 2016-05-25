module dpq2.result;

public import dpq2.conv.to_d_types;
public import dpq2.conv.to_bson;
public import dpq2.oids;
public import dpq2.value;

import dpq2;

import core.vararg;
import std.string: toStringz, fromStringz;
import std.exception: enforceEx;
import core.exception: OutOfMemoryError;
import std.bitmanip: bigEndianToNative;
import std.conv: to, ConvException;

/// Result table's cell coordinates 
private struct Coords
{
    size_t row; /// Row
    size_t col; /// Column
}

package immutable final class ResultContainer
{
    // ResultContainer allows only one copy of PGresult* due to avoid double free.
    // For the same reason this class is declared as final.
    private PGresult* result;
    alias result this;

    nothrow invariant()
    {
        assert( result != null );
    }

    package this(immutable PGresult* r)
    {
        assert(r);

        result = r;
    }

    ~this()
    {
        assert(result != null);

        PQclear(result);
    }
}

/// Contains result of query regardless of whether it contains an error or data answer
immutable class Result
{
    private ResultContainer result;

    package this(immutable ResultContainer r)
    {
        result = r;
    }

    @property
    ExecStatusType status() nothrow
    {
        return PQresultStatus(result);
    }

    @property
    string statusString()
    {
        return to!string(fromStringz(PQresStatus(status)));
    }

    @property
    string resultErrorMessage()
    {
        return to!string( PQresultErrorMessage(result) );
    }

    @property
    string resultErrorField(int fieldcode)
    {
        return PQresultErrorField(result, fieldcode).to!string;
    }

    immutable(Answer) getAnswer()
    {
        return new immutable Answer(result);
    }

    debug string toString()
    {
        import std.ascii: newline;

        string err = resultErrorMessage();

        return statusString()~(err.length != 0 ? newline~err : "");
    }
}

/// Contains result of query with valid data answer
immutable class Answer : Result
{
    package this(immutable ResultContainer r)
    {
        super(r);

        checkAnswerForErrors();
    }

    private void checkAnswerForErrors()
    {
        switch(status)
        {
            case PGRES_COMMAND_OK:
            case PGRES_TUPLES_OK:
                break;

            default:
                throw new AnswerCreationException(this, __FILE__, __LINE__);
        }
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
        return to!string( PQcmdStatus(result) );
    }

    /// Returns row count
    @property size_t length() nothrow { return PQntuples(result); }

    /// Returns column count
    @property size_t columnCount() nothrow { return PQnfields(result); }

    /// Returns column format
    ValueFormat columnFormat( const size_t colNum )
    {
        assertCol( colNum );
        return cast(ValueFormat) PQfformat(result, to!int(colNum));
    }
    
    /// Returns column Oid
    @property OidType OID( size_t colNum )
    {
        assertCol( colNum );

        return PQftype(result, to!int(colNum)).oid2oidType;
    }

    @property bool isSupportedArray( const size_t colNum )
    {
        assertCol(colNum);

        return dpq2.oids.isSupportedArray(OID(colNum));
    }

    /// Returns column number by field name
    size_t columnNum( string columnName )
    {    
        size_t n = PQfnumber(result, toStringz(columnName));

        if( n == -1 )
            throw new AnswerException(ExceptionType.COLUMN_NOT_FOUND,
                    "Column '"~columnName~"' is not found", __FILE__, __LINE__);

        return n;
    }

    /// Returns column name by field number
    string columnName( in size_t colNum )
    {
        const char* s = PQfname(result, colNum.to!int);

        if( s == null )
            throw new AnswerException(
                    ExceptionType.OUT_OF_RANGE,
                    "Column "~to!string(colNum)~" is out of range 0.."~to!string(columnCount),
                    __FILE__, __LINE__
                );

        return to!string(fromStringz(s));
    }

    /// Returns true if the column exists, false if not
    bool columnExists( string columnName )
    {    
        size_t n = PQfnumber(result, columnName.toStringz);

        return n != -1;
    }

    /// Returns row of cells
    immutable (Row) opIndex(in size_t row)
    {
        return immutable Row(
            cast(immutable)(this), // legal because this.ctor is immutable
            row
        );
    }

    /**
     Returns the number of parameters of a prepared statement.
     This function is only useful when inspecting the result of describePrepared.
     For other types of queries it will return zero.
    */
    uint nParams()
    {
        return PQnparams(result);
    }

    /**
     Returns the data type of the indicated statement parameter.
     Parameter numbers start at 0.
     This function is only useful when inspecting the result of describePrepared.
     For other types of queries it will return zero.
    */
    OidType paramType(T)(T paramNum)
    {
        return PQparamtype(result, paramNum.to!uint).oid2oidType;
    }

    debug override string toString()
    {
        import std.ascii: newline;

        string res;

        foreach(n; 0 .. columnCount)
            res ~= columnName(n)~"::"~OID(n).to!string~"\t";

        res ~= newline;

        foreach(row; rangify(this))
            res ~= row.toString~newline;

        return super.toString~newline~res;
    }

    private void assertCol( const size_t c )
    {
        if(!(c < columnCount))
            throw new AnswerException(
                ExceptionType.OUT_OF_RANGE,
                "Column "~to!string(c)~" is out of range 0.."~to!string(columnCount)~" of result columns",
                __FILE__, __LINE__
            );
    }
    
    private void assertRow( const size_t r )
    {
        if(!(r < length))
            throw new AnswerException(
                ExceptionType.OUT_OF_RANGE,
                "Row "~to!string(r)~" is out of range 0.."~to!string(length)~" of result rows",
                __FILE__, __LINE__
            );
    }
    
     private void assertCoords( const Coords c )
    {
        assertRow( c.row );
        assertCol( c.col );
    }
}

auto rangify(T)(T obj)
{
    struct Rangify(T)
    {
        T obj;
        alias obj this;

        private int curr;

        this(T o)
        {
            obj = o;
        }

        @property auto front(){ return obj[curr]; }
        @property void popFront(){ ++curr; }
        @property bool empty(){ return curr >= obj.length; }
    }

    return Rangify!(T)(obj);
}

/// Represents one row from the answer table
immutable struct Row
{
    private Answer answer;
    private size_t row;
    
    this(immutable Answer answer, in size_t row)
    {
        answer.assertRow( row );
        
        this.answer = answer;
        this.row = row;
    }
    
    /// Returns cell size
    @property
    size_t size( const size_t col )
    {
        answer.assertCol(col);
        return PQgetlength(answer.result, to!int(row), to!int(col));
    }
    
    /// Value NULL checking
    /// Do not confuse it with Nullable's isNull property
    @property
    bool isNULL( const size_t col )
    {
        answer.assertCol(col);

        return PQgetisnull(answer.result, to!int(row), to!int(col)) != 0;
    }

    immutable (Value) opIndex(in size_t col)
    {
        answer.assertCoords( Coords( row, col ) );

        // The pointer returned by PQgetvalue points to storage that is part of the PGresult structure.
        // One should not modify the data it points to, and one must explicitly copy the data into other
        // storage if it is to be used past the lifetime of the PGresult structure itself.
        const ubyte* v = cast(immutable) PQgetvalue(answer.result, to!int(row), to!int(col));
        size_t s = size(col);

        // it is legal to cast here because immutable value will be returned
        Value r = Value(cast(ubyte[]) v[0..s], answer.OID(col), isNULL(col), answer.columnFormat(col));

        return cast(immutable) r;
    }
    
    immutable (Value) opIndex(in string column)
    {
        return opIndex(columnNum(column));
    }
    
    /// Returns column number by field name
    size_t columnNum( string columnName )
    {
        return answer.columnNum( columnName );
    }

    /// Returns column name by field number
    string columnName( in size_t colNum )
    {
        return answer.columnName( colNum );
    }

    /// Returns column count
    @property size_t length() { return answer.columnCount(); }
    
    debug string toString()
    {
        string res;

        foreach(val; rangify(this))
            res ~= dpq2.result.toString(val)~"\t";

        return res;
    }
}

@property
immutable (Array) asArray(immutable(Value) v)
{
    if(v.format == ValueFormat.TEXT)
        throw new AnswerConvException(ConvExceptionType.NOT_ARRAY,
            "Value internal format is text",
            __FILE__, __LINE__
        );

    if(!v.isSupportedArray)
        throw new AnswerConvException(ConvExceptionType.NOT_ARRAY,
            "Format of the value is "~to!string(v.oidType)~", isn't supported array",
            __FILE__, __LINE__
        );

    return immutable Array(v);
}

debug string toString(immutable Value v)
{
    import vibe.data.bson: Bson;

    return v.isNull ? "NULL" : v.as!Bson.toString;
}

package struct ArrayHeader_net // network byte order
{
    ubyte[4] ndims; // number of dimensions of the array
    ubyte[4] dataoffset_ign; // offset for data, removed by libpq. may be it contains isNULL flag!
    ubyte[4] OID; // element type OID
}

package struct Dim_net // network byte order
{
    ubyte[4] dim_size; // number of elements in dimension
    ubyte[4] lbound; // unknown
}

struct ArrayProperties
{
    OidType OID = OidType.Undefined;
    int[] dimsSize; /// Dimensions sizes info
    size_t nElems; /// Total elements
    package size_t dataOffset;

    this(in Value cell)
    {
        const ArrayHeader_net* h = cast(ArrayHeader_net*) cell.data.ptr;
        int nDims = bigEndianToNative!int(h.ndims);
        OID = oid2oidType(bigEndianToNative!Oid(h.OID));

        if(nDims < 0)
            throw new AnswerException(ExceptionType.FATAL_ERROR,
                "Array dimensions number is negative ("~to!string(nDims)~")",
                __FILE__, __LINE__
            );

        dataOffset = ArrayHeader_net.sizeof + Dim_net.sizeof * nDims;

        dimsSize = new int[nDims];

        // Recognize dimensions of array
        for( auto i = 0; i < nDims; ++i )
        {
            Dim_net* d = (cast(Dim_net*) (h + 1)) + i;

            const dim_size = bigEndianToNative!int(d.dim_size);
            const lbound = bigEndianToNative!int(d.lbound);

            if(dim_size < 0)
                throw new AnswerException(ExceptionType.FATAL_ERROR,
                    "Dimension size is negative ("~to!string(dim_size)~")",
                    __FILE__, __LINE__
                );

            // FIXME: What is lbound in postgresql array reply?
            if(!(lbound == 1))
                throw new AnswerException(ExceptionType.FATAL_ERROR,
                    "Please report if you came across this error! lbound=="~to!string(lbound),
                    __FILE__, __LINE__
                );

            dimsSize[i] = dim_size;

            if(i == 0) // first dimension
                nElems = dim_size;
            else
                nElems *= dim_size;
        }
    }
}

/// Link to the cell of the answer table
immutable struct Array
{
    ArrayProperties ap;
    alias ap this;

    private ubyte[][] elements;
    private bool[] elementIsNULL;

    this(immutable Value cell)
    {
        if(!(cell.format == ValueFormat.BINARY))
            throw new AnswerConvException(ConvExceptionType.NOT_BINARY,
                msg_NOT_BINARY, __FILE__, __LINE__);

        ap = cast(immutable) ArrayProperties(cell);

        // Looping through all elements and fill out index of them
        {
            auto elements = new immutable (ubyte)[][ nElems ];
            auto elementIsNULL = new bool[ nElems ];

            size_t curr_offset = ap.dataOffset;

            for(uint i = 0; i < nElems; ++i)
            {
                ubyte[int.sizeof] size_net; // network byte order
                size_net[] = cell.data[ curr_offset .. curr_offset + size_net.sizeof ];
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
                elements[i] = cell.data[curr_offset .. curr_offset + size];
                curr_offset += size;
            }

            this.elements = elements.idup;
            this.elementIsNULL = elementIsNULL.idup;
        }
    }

    /// Returns number of elements in array
    /// Useful for one-dimensional arrays
    @property size_t length()
    {
        return nElems;
    }

    /// Returns Value struct by index
    /// Useful for one-dimensional arrays
    immutable (Value) opIndex(size_t n)
    {
        return opIndex(n.to!int);
    }

    /// Returns Value struct by index
    /// Useful for one-dimensional arrays
    immutable (Value) opIndex(int n)
    {
        return getValue(n);
    }
    
    /// Returns Value struct
    /// Useful for multidimensional arrays
    immutable (Value) getValue( ... )
    {
        auto n = coords2Serial( _argptr, _arguments );
        
        // it is legal to cast here because immutable value will be returned
        Value r = Value(cast(ubyte[]) elements[n], OID, elementIsNULL[n], ValueFormat.BINARY);

        return cast(immutable) r;
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

        if(!(dimsSize.length == args.length))
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

/// Answer creation exception
/// Useful for analyze error data
class AnswerCreationException : Dpq2Exception
{
    immutable(Result) result;
    alias result this;

    this(immutable(Result) result, string file, size_t line)
    {
        this.result = result;

        super(result.resultErrorMessage(), file, line);
    }
}

/// Answer exception types
enum ExceptionType
{
    FATAL_ERROR,
    COLUMN_NOT_FOUND, /// Column is not found
    OUT_OF_RANGE
}

/// Exception
class AnswerException : Dpq2Exception
{
    const ExceptionType type; /// Exception type

    this(ExceptionType t, string msg, string file, size_t line) pure @safe
    {
        type = t;
        super(msg, file, line);
    }
}

package immutable msg_NOT_BINARY = "Format of the column is not binary";

/// Conversion exception types
enum ConvExceptionType
{
    NOT_ARRAY, /// Format of the value isn't array
    NOT_BINARY, /// Format of the column isn't binary
    NOT_TEXT, /// Format of the column isn't text string
    NOT_IMPLEMENTED, /// Support of this type isn't implemented (or format isn't matches to specified D type)
    SIZE_MISMATCH /// Result value size is not matched to the received Postgres value
}

class AnswerConvException : ConvException
{
    const ConvExceptionType type; /// Exception type

    this(ConvExceptionType t, string msg, string file, size_t line) pure @safe
    {
        type = t;
        super(msg, file, line);
    }
}

void _integration_test( string connParam )
{
    import core.exception: AssertError;

    auto conn = new Connection(connParam);

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
        assert(e.columnExists("field_name"));
        assert(!e.columnExists("foo"));
    }

    QueryParams p;
    p.resultFormat = ValueFormat.BINARY;
    p.sqlCommand = "SELECT "~
        "-32761::smallint, "~
        "-2147483646::integer as integer_value, "~
        "'first line\nsecond line'::text, "~
        "array[[[1,  2, 3], "~
               "[4,  5, 6]], "~
               
              "[[7,  8, 9], "~
              "[10, 11,12]], "~
              
              "[[13,14,NULL], "~
               "[16,17,18]]]::integer[] as test_array, "~
        "NULL::smallint,"~
        "array[11,22,NULL,44]::integer[] as small_array, "~
        "array['1','23',NULL,'789A']::text[] as text_array, "~
        "array[]::text[] as empty_array";

    auto r = conn.execParams(p);

    {
        assert( r[0].isNULL(4) );
        assert( !r[0].isNULL(2) );

        assert( r.OID(3) == OidType.Int4Array );
        assert( r.isSupportedArray(3) );
        assert( !r.isSupportedArray(2) );
        auto v = r[0]["test_array"];
        assert( v.isSupportedArray );
        assert( !r[0][2].isSupportedArray );
        auto a = v.asArray;
        assert( a.OID == OidType.Int4 );
        assert( a.getValue(2,1,2).as!PGinteger == 18 );
        assert( a.isNULL(2,0,2) );
        assert( !a.isNULL(2,1,2) );
        assert( r[0]["small_array"].asArray[1].as!PGinteger == 22 );
        assert( r[0]["small_array"].asArray[2].isNull );
        assert( r[0]["text_array"].asArray[2].isNull );
        assert( r.columnName(3) == "test_array" );
        assert( r[0].columnName(3) == "test_array" );
        assert( r[0]["empty_array"].asArray.nElems == 0 );
        assert( r[0]["empty_array"].asArray.dimsSize.length == 0 );
        assert( r[0]["empty_array"].asArray.length == 0 );
        assert( r[0]["text_array"].asArray.length == 4 );
        assert( r[0]["test_array"].asArray.length == 18 );

        // Access to NULL cell
        {
            bool isNullFlag = false;
            try
                cast(void) r[0][4].as!PGsmallint;
            catch(AssertError)
                isNullFlag = true;
            finally
                assert(isNullFlag);
        }

        // Access to NULL array element
        {
            bool isNullFlag = false;
            try
                cast(void) r[0]["small_array"].asArray[2].as!PGinteger;
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
    conn.sendQueryParams(p);
    while( conn.getResult() !is null ){}
    assert( conn.getResult() is null ); // removes null answer at the end

    {
        // Range test
        auto rowsRange = rangify(r);
        size_t count = 0;

        foreach(row; rowsRange)
            foreach(elem; rangify(row))
                count++;

        assert(count == 8);
    }

    //assert(r.toString.length > 40);

    {
        bool exceptionFlag = false;

        try r[0]["integer_value"].as!PGtext;
        catch(AnswerConvException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 5); // error message check
        }
        finally
            assert(exceptionFlag);
    }

    {
        bool exceptionFlag = false;

        try conn.exec("WRONG SQL QUERY");
        catch(AnswerCreationException e)
        {
            exceptionFlag = true;
            assert(e.msg.length > 20); // error message check

            version(LDC) destroy(e); // before Derelict unloads its bindings (prevents SIGSEGV)
        }
        finally
            assert(exceptionFlag);
    }
}
