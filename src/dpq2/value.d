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

    @property
    inout (ubyte[]) data() pure inout
    {
        import std.exception;
        import core.exception;

        enforceEx!AssertError(!isNull, "Attempt to read NULL value", __FILE__, __LINE__);

        return _data;
    }

    @property
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
