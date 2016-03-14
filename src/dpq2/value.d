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
        assert(!isNull, "Attempt to read NULL value");

        return _data;
    }

    @property
    bool isSupportedArray() const
    {
        return dpq2.oids.isSupportedArray(oidType);
    }

    string toString() const @trusted
    {
        import dpq2.types.to_bson;
        import std.conv: to;

        return toBson(this).toString~"::"~oidType.to!string;
    }
}

enum ValueFormat : int {
    TEXT,
    BINARY
}
