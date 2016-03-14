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
        import dpq2.types.to_bson;
        import std.conv: to;

        return toBson(this).toString~"::"~oidType.to!string;
    }
}

@trusted unittest
{
    import dpq2.types.to_d_types;
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
