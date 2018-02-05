module dpq2.value;

@safe:

import dpq2.oids;

/// Minimal Postgres value
struct Value
{
    bool isNull = true;
    OidType oidType = OidType.Undefined;

    package ValueFormat format;
    package ubyte[] _data;

    // FIXME:
    // The pointer returned by PQgetvalue points to storage that is part of the PGresult structure.
    // One should not modify the data it points to, and one must explicitly copy the data into other
    // storage if it is to be used past the lifetime of the PGresult structure itself.
    // Thus, it is need to store reference to Answer here to ensure that result is still available.

    this(ubyte[] data, in OidType oidType, bool isNull, in ValueFormat format = ValueFormat.BINARY) pure
    {
        this._data = data;
        this.format = format;
        this.oidType = oidType;
        this.isNull = isNull;
    }

    /// Null Value constructor
    this(in ValueFormat format, in OidType oidType) pure
    {
        this.format = format;
        this.oidType = oidType;
    }

    inout (ubyte[]) data() pure inout
    {
        import std.exception;
        import core.exception;

        enforceEx!AssertError(!isNull, "Attempt to read NULL value", __FILE__, __LINE__);

        return _data;
    }

    bool isSupportedArray() const
    {
        return dpq2.oids.isSupportedArray(oidType);
    }

    debug string toString() const @trusted
    {
        import vibe.data.bson: Bson;
        import dpq2.conv.to_bson;
        import std.conv: to;

        return this.as!Bson.toString~"::"~oidType.to!string~"("~(format == ValueFormat.TEXT? "t" : "b")~")";
    }
}

@trusted unittest
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

enum ValueFormat : int {
    TEXT,
    BINARY
}

import std.conv: to, ConvException;

/// Conversion exception types
enum ConvExceptionType
{
    NOT_ARRAY, /// Format of the value isn't array
    NOT_BINARY, /// Format of the column isn't binary
    NOT_TEXT, /// Format of the column isn't text string
    NOT_IMPLEMENTED, /// Support of this type isn't implemented (or format isn't matches to specified D type)
    SIZE_MISMATCH, /// Result value size is not matched to the received Postgres value
    CORRUPTED_JSONB, /// Corrupted JSONB value
    DATE_VALUE_OVERFLOW, /// Date value isn't fits to Postgres binary Date value
}

class ValueConvException : ConvException
{
    const ConvExceptionType type; /// Exception type

    this(ConvExceptionType t, string msg, string file, size_t line) pure @safe
    {
        type = t;
        super(msg, file, line);
    }
}
