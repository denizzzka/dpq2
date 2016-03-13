module dpq2.value;

@safe:

import dpq2.oids;

/// Minimal Postgres value
struct Value
{
    bool isNull = true;
    OidType oidType;

    package ValueFormat format;
    package ubyte[] data;

    this(ubyte[] data, in OidType oidType, bool isNull, in ValueFormat format = ValueFormat.BINARY) pure
    {
        this.data = data;
        this.format = format;
        this.oidType = oidType;
        this.isNull = isNull;
    }

    @property
    inout (ubyte[]) value() pure inout // TODO: rename it to "data"
    {
        assert(!isNull, "Attempt to read NULL value");

        return data;
    }

    @property
    void value(string s) pure // TODO: temporary, remove it
    {
        import dpq2.types.from_d_types;

        this = toValue(s);
    }

    @property
    bool isSupportedArray() const
    {
        return dpq2.oids.isSupportedArray(oidType);
    }
}

enum ValueFormat : ubyte {
    TEXT,
    BINARY
}
