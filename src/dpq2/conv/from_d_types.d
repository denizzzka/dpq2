module dpq2.conv.from_d_types;

@safe:

import dpq2;
import std.bitmanip: nativeToBigEndian;
import std.traits: isNumeric;

@property Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, detectOidType!T, false, ValueFormat.BINARY);
}

@property Value toValue(T)(T v, ValueFormat valueFormat = ValueFormat.BINARY) @trusted
if(is(T == string))
{
    if(valueFormat == ValueFormat.TEXT) v = v~'\0'; // for prepareArgs only

    ubyte[] buf = cast(ubyte[]) v;

    return Value(buf, detectOidType!T, false, valueFormat);
}

@property Value toValue(T)(T v) @trusted
if(is(T == bool))
{
    ubyte[] buf;
    buf.length = 1;
    buf[0] = (v ? 1 : 0);

    return Value(buf, detectOidType!T, false, ValueFormat.BINARY);
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
        Value t = toValue(true);
        Value f = toValue(false);

        assert(t.as!bool == true);
        assert(f.as!bool == false);
    }
}

private OidType detectOidType(T)()
{
    with(OidType)
    {
        static if(is(T == string)){ return Text; } else
        static if(is(T == bool)){ return Bool; } else
        static if(is(T == short)){ return Int2; } else
        static if(is(T == int)){ return Int4; } else
        static if(is(T == long)){ return Int8; } else
        static if(is(T == float)){ return Float4; } else
        static if(is(T == double)){ return Float8; } else

        static assert(false, "Unsupported D type: "~T.stringof);
    }
}
