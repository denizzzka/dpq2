module dpq2.conv.from_d_types;

@safe:

import dpq2;
import std.bitmanip: nativeToBigEndian;
import std.traits: isNumeric;

@property Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

@property Value toValue(T)(T v, ValueFormat valueFormat = ValueFormat.BINARY) @trusted
if(is(T == string))
{
    if(valueFormat == ValueFormat.TEXT) v = v~'\0'; // for prepareArgs only

    ubyte[] buf = cast(ubyte[]) v;

    return Value(buf, detectOidTypeFromNative!T, false, valueFormat);
}

@property Value toValue(T)(T v)
if(is(T == ubyte[]))
{
    return Value(v, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

@property Value toValue(T : bool)(T v) @trusted
{
    ubyte[] buf;
    buf.length = 1;
    buf[0] = (v ? 1 : 0);

    return Value(buf, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

unittest
{
    {
        Value v = toValue(cast(short) 123);

        assert(v.oidType == OidType.Int2);
        assert(v.as!short == 123);
    }

    {
        Value v = toValue(-123.456);

        assert(v.oidType == OidType.Float8);
        assert(v.as!double == -123.456);
    }

    {
        Value v = toValue("Test string");

        assert(v.oidType == OidType.Text);
        assert(v.as!string == "Test string");
    }

    {
        ubyte[] buf = [0, 1, 2, 3, 4, 5];
        Value v = toValue(buf.dup);

        assert(v.oidType == OidType.ByteArray);
        assert(v.as!(const ubyte[]) == buf);
    }

    {
        Value t = toValue(true);
        Value f = toValue(false);

        assert(t.as!bool == true);
        assert(f.as!bool == false);
    }
}
