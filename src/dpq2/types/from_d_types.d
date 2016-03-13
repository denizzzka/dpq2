module dpq2.types.from_d_types;

@safe:
package:

import dpq2;
import std.bitmanip: nativeToBigEndian;
import std.traits: isNumeric;

Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, v.detectOidType, false, ValueFormat.BINARY);
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
}

Value toValue(T)(T v) @trusted
if(is(T == string))
{
    ubyte[] buf = cast(ubyte[]) v;
    return Value(buf, v.detectOidType, false, ValueFormat.BINARY);
}

unittest
{
    Value v = toValue("Test string");

    assert(v.oidType == OidType.Text);
    assert(v.as!string == "Test string");
}

private OidType detectOidType(T)(T v)
{
    with(OidType)
    {
        static if(is(T == string)){ return Text; } else
        static if(is(T == short)){ return Int2; } else
        static if(is(T == int)){ return Int4; } else
        static if(is(T == long)){ return Int8; } else
        static if(is(T == float)){ return Float4; } else
        static if(is(T == double)){ return Float8; } else

        static assert(false, "Unsupported D type: "~T.stringof);
    }
}
