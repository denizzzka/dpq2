module dpq2.conv.from_d_types;

@safe:

import dpq2.conv.time : POSTGRES_EPOCH_DATE, TimeStampWithoutTZ;
import dpq2.oids : detectOidTypeFromNative, OidType;
import dpq2.value : Value, ValueFormat;
import std.bitmanip: nativeToBigEndian;
import std.datetime.date : Date, TimeOfDay;
import std.datetime.systime : SysTime, UTC;
import std.traits: isNumeric, TemplateArgsOf, Unqual;
import std.typecons : Nullable;

/// Converts Nullable!T to Value
Value toValue(T)(T v)
    if (is(T == Nullable!R, R))
{
    if (v.isNull) return Value(null, detectOidTypeFromNative!(TemplateArgsOf!T[0]), true);
    return toValue(v.get);
}

Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

Value toValue(T)(T v, ValueFormat valueFormat = ValueFormat.BINARY) @trusted
if(is(T == string))
{
    if(valueFormat == ValueFormat.TEXT) v = v~'\0'; // for prepareArgs only

    ubyte[] buf = cast(ubyte[]) v;

    return Value(buf, detectOidTypeFromNative!T, false, valueFormat);
}

Value toValue(T)(T v)
if(is(T == ubyte[]))
{
    return Value(v, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

Value toValue(T : bool)(T v) @trusted
if (!is(T == Nullable!R, R))
{
    ubyte[] buf;
    buf.length = 1;
    buf[0] = (v ? 1 : 0);

    return Value(buf, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

/// Constructs Value from Date
Value toValue(T)(T v)
if (is(Unqual!T == Date))
{
    auto days = cast(int)(v - POSTGRES_EPOCH_DATE).total!"days";
    return Value(nativeToBigEndian(days).dup, OidType.Date, false);
}

/// Constructs Value from TimeOfDay
Value toValue(T)(T v)
if (is(Unqual!T == TimeOfDay))
{
    long ms = (v.second + v.minute*60L + v.hour*3_600L)*1_000_000;
    return Value(nativeToBigEndian(ms).dup, OidType.Time, false);
}

/// Constructs Value from TimeStampWithoutTZ
Value toValue(T)(T v)
if (is(Unqual!T == TimeStampWithoutTZ))
{
    auto val = toValue(cast(SysTime)v); // works similarly to SysTime, but TZ is not used for conversion
    val.oidType = OidType.TimeStamp;
    return val;
}

/// Constructs Value from SysTime
Value toValue(T)(T v)
if (is(Unqual!T == SysTime))
{
    auto us = (v - SysTime(POSTGRES_EPOCH_DATE, UTC())).total!"usecs";
    return Value(nativeToBigEndian(us).dup, OidType.TimeStampWithZone, false);
}

unittest
{
    import dpq2.conv.to_d_types : as;

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

    {
        Value v = toValue(Nullable!long(1));
        Value nv = toValue(Nullable!bool.init);

        assert(!v.isNull);
        assert(v.oidType == OidType.Int8);
        assert(v.as!long == 1);

        assert(nv.isNull);
        assert(nv.oidType == OidType.Bool);
    }

    {
        // Date: '2018-1-15' -> [0, 0, 25, 189]
        auto d = Date(2018, 1, 15);
        auto v = toValue(d);

        assert(v.data == [0, 0, 25, 189]);
        assert(v.as!Date == d);
    }

    {
        // Date: '2000-1-1' -> [0, 0, 0, 0]
        auto d = Date(2000, 1, 1);
        auto v = toValue(d);

        assert(v.data == [0, 0, 0, 0]);
        assert(v.as!Date == d);
    }

    {
        // Date: '0010-2-20' -> [255, 244, 233, 2]
        auto d = Date(10, 2, 20);
        auto v = toValue(d);

        assert(v.data == [255, 244, 233, 2]);
        assert(v.as!Date == d);
    }

    {
        // TimeOfDay: '14:29:17' -> [0, 0, 0, 12, 36, 204, 169, 64]
        auto tod = TimeOfDay(14, 29, 17);
        auto v = toValue(tod);

        assert(v.data == [0, 0, 0, 12, 36, 204, 169, 64]);
        assert(v.as!TimeOfDay == tod);
    }

    {
        // SysTime: '2017-11-13T14:29:17.075678Z' -> [0, 2, 0, 220, 221, 47, 16, 222]
        auto t = SysTime.fromISOExtString("2017-11-13T14:29:17.075678Z");
        auto v = toValue(t);

        assert(v.data == [0, 2, 0, 220, 221, 47, 16, 222]);
        assert(v.as!SysTime == t);
    }

    {
        import core.time : usecs;
        import std.datetime.date : DateTime;

        // TimeStampWithoutTZ: '2017-11-13 14:29:17.075678' -> [0, 2, 0, 220, 221, 47, 16, 222]
        auto t = TimeStampWithoutTZ(DateTime(2017, 11, 13, 14, 29, 17), 75_678.usecs);
        auto v = toValue(t);

        assert(v.data == [0, 2, 0, 220, 221, 47, 16, 222]);
        assert(v.as!TimeStampWithoutTZ == t);
    }
}
