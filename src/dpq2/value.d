///
module dpq2.value;

import dpq2.oids;

@safe:

/**
Represents table cell or argument value

Internally it is a ubyte[].
If it returned by Answer methods it contains a reference to the data of
the server answer and it can not be accessed after Answer is destroyed.
*/
struct Value
{
    private
    {
        bool _isNull = true;
        OidType _oidType = OidType.Undefined;

        ValueFormat _format;
    }

    package immutable(ubyte)[] _data;

    // FIXME:
    // The pointer returned by PQgetvalue points to storage that is part of the PGresult structure.
    // One should not modify the data it points to, and one must explicitly copy the data into other
    // storage if it is to be used past the lifetime of the PGresult structure itself.
    // Thus, it is need to store reference to Answer here to ensure that result is still available.
    // (Also see DIP1000)
    /// ctor
    this(immutable(ubyte)[] data, in OidType oidType, bool isNull = false, in ValueFormat format = ValueFormat.BINARY) inout pure
    {
        import std.exception: enforce;

        //TODO: it is possible to skip this check for fixed-size values?
        enforce(data.length <= int.max, `data.length is too big for use as Postgres value`);

        this._data = data;
        this._format = format;
        this._oidType = oidType;
        this._isNull = isNull;
    }

    /// Null Value constructor
    this(in ValueFormat format, in OidType oidType) pure
    {
        this._format = format;
        this._oidType = oidType;
    }

    @safe const pure nothrow scope @nogc
    {
        /// Indicates if the value is NULL
        bool isNull()
        {
            return _isNull;
        }

        /// Indicates if the value is array type
        bool isArray()
        {
            return dpq2.oids.isSupportedArray(oidType);
        }
        alias isSupportedArray = isArray; //TODO: deprecate

        /// Returns Oid of the value
        OidType oidType()
        {
            return _oidType;
        }

        /// Returns ValueFormat representation (text or binary)
        ValueFormat format()
        {
            return _format;
        }
    }

    package void oidType(OidType type) @safe pure nothrow @nogc
    {
        _oidType = type;
    }

    //TODO: replace template by return modifier
    immutable(ubyte)[] data()() pure const scope
    {
        import std.exception;
        import core.exception;

        enforce!AssertError(!isNull, "Attempt to read SQL NULL value", __FILE__, __LINE__);

        return _data;
    }

    ///
    string toString() const @trusted
    {
        import dpq2.conv.to_d_types;
        import std.conv: to;
        import std.variant;

        return this.as!Variant.toString~"::"~oidType.to!string~"("~(format == ValueFormat.TEXT? "t" : "b")~")";
    }
}

@system unittest
{
    import dpq2.conv.to_d_types;
    import core.exception: AssertError;

    Value v = Value(ValueFormat.BINARY, OidType.Int4);

    bool exceptionFlag = false;

    try
        cast(void) v.as!int;
    catch(AssertError e)
        exceptionFlag = true;

    assert(exceptionFlag);
}

///
enum ValueFormat : int {
    TEXT, ///
    BINARY ///
}

import std.conv: to, ConvException;

/// Conversion exception types
enum ConvExceptionType
{
    NOT_ARRAY, /// Format of the value isn't array
    NOT_BINARY, /// Format of the column isn't binary
    NOT_TEXT, /// Format of the column isn't text string
    NOT_IMPLEMENTED, /// Support of this type isn't implemented (or format isn't matches to specified D type)
    SIZE_MISMATCH, /// Value size is not matched to the Postgres value or vice versa
    CORRUPTED_JSONB, /// Corrupted JSONB value
    DATE_VALUE_OVERFLOW, /// Date value isn't fits to Postgres binary Date value
    DIMENSION_MISMATCH, /// Array dimension size is not matched to the Postgres array
    CORRUPTED_ARRAY, /// Corrupted array value
    OUT_OF_RANGE, /// Index is out of range
    TOO_PRECISE, /// Too precise value can't be stored in destination variable
}

/// Value conversion exception
class ValueConvException : ConvException
{
    const ConvExceptionType type; /// Exception type

    this(ConvExceptionType t, string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure @safe
    {
        type = t;
        super(msg, file, line, next);
    }
}

package void throwTypeComplaint(OidType receivedType, in string expectedType, string file = __FILE__, size_t line = __LINE__) pure
{
    throw new ValueConvException(
            ConvExceptionType.NOT_IMPLEMENTED,
            "Format of the column ("~to!string(receivedType)~") doesn't match to D native "~expectedType,
            file, line
        );
}

//TODO: use for all ConvExceptionType.SIZE_MISMATCH checks
package void enforceSize(T)(const ref T binaryData, size_t sz, string msg, string file = __FILE__, size_t line = __LINE__)
{
    if(!(binaryData.length >= sz))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH, msg, file, line);
}
