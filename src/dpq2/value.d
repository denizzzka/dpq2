module dpq2.value;

@safe:

import dpq2.oids;

/// Minimal Postgres value
struct Value
{
    bool isNull = true;
    OidType oidType = OidType.Undefined;

    package ValueFormat format;
    private ubyte[] _data;

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
}

enum ValueFormat : int {
    TEXT,
    BINARY
}
