module dpq2.value;

@safe:

import dpq2.oids;

/// Minimal Postgres value
struct Value
{
    private
    {
        bool _isNull = true;
        OidType _oidType = OidType.Undefined;

        ValueFormat _format;
    }

    package ubyte[] _data;

    // FIXME:
    // The pointer returned by PQgetvalue points to storage that is part of the PGresult structure.
    // One should not modify the data it points to, and one must explicitly copy the data into other
    // storage if it is to be used past the lifetime of the PGresult structure itself.
    // Thus, it is need to store reference to Answer here to ensure that result is still available.

    this(ubyte[] data, in OidType oidType, bool isNull, in ValueFormat format = ValueFormat.BINARY) pure
    {
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

    @safe const pure nothrow @nogc
    {
        /// Indicates if the value is NULL
        bool isNull()
        {
            return _isNull;
        }

        /// Indicates if the value is supported array type
        bool isSupportedArray()
        {
            return dpq2.oids.isSupportedArray(oidType);
        }

        /// Returns OidType of the value
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

    inout (ubyte[]) data() pure inout
    {
        import std.exception;
        import core.exception;

        enforceEx!AssertError(!isNull, "Attempt to read NULL value", __FILE__, __LINE__);

        return _data;
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
