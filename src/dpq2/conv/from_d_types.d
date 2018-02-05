module dpq2.conv.from_d_types;

@safe:

import dpq2.conv.time : POSTGRES_EPOCH_DATE, TimeStampWithoutTZ;
import dpq2.oids : detectOidTypeFromNative, OidType;
import dpq2.value : Value, ValueFormat;

import std.bitmanip: nativeToBigEndian;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime : LocalTime, SysTime, TimeZone, UTC;
import std.traits: isNumeric, TemplateArgsOf, Unqual;
import std.typecons : Nullable;

/// Converts Nullable!T to Value
Value toValue(T)(T v)
if (is(T == Nullable!R, R))
{
    if (v.isNull)
        return Value(ValueFormat.BINARY, detectOidTypeFromNative!(TemplateArgsOf!T[0]));
    else
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
    import std.conv: to;

    auto days = (v - POSTGRES_EPOCH_DATE).total!"days".to!int;

    return Value(nativeToBigEndian(days).dup, OidType.Date, false);
}

/// Constructs Value from TimeOfDay
Value toValue(T)(T v)
if (is(Unqual!T == TimeOfDay))
{
    long us = ((60L * v.hour + v.minute) * 60 + v.second) * 1_000_000;

    return Value(nativeToBigEndian(us).dup, OidType.Time, false);
}

/// Constructs Value from TimeStampWithoutTZ
Value toValue(T)(T v)
if (is(Unqual!T == TimeStampWithoutTZ))
{
    long j = v.dateTime.modJulianDay - POSTGRES_EPOCH_DATE.modJulianDay; // FIXME: use POSTGRES_EPOCH_JDATE here
    long us = (((j * 24 + v.hour) * 60 + v.minute) * 60 + v.second) * 1_000_000 + v.fracSec.total!"usecs";

    return Value(nativeToBigEndian(us).dup, OidType.TimeStamp, false);
}

/++
    Constructs Value from DateTime
    It uses Timestamp without TZ as a resulting PG type
+/
Value toValue(T)(T v)
if (is(Unqual!T == DateTime))
{
    return TimeStampWithoutTZ(v).toValue;
}

/++
    Constructs Value from SysTime
    Note that SysTime has a precision in hnsecs and PG TimeStamp in usecs.
    It means that PG value will have 10 times lower precision.
    And as both types are using long for internal storage it also means that PG TimeStamp can store greater range of values than SysTime.
+/
Value toValue(T)(T v)
if (is(Unqual!T == SysTime))
{
    long us = (v - SysTime(POSTGRES_EPOCH_DATE, UTC())).total!"usecs";

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

    //FIXME: Not working currently
    // {
    //     import std.datetime : DateTime;
    //     Value v = toValue(Nullable!TimeStampWithoutTZ(TimeStampWithoutTZ(DateTime(2017, 1, 2))));

    //     assert(v.isNull);
    //     assert(v.oidType == OidType.TimeStamp);
    // }

    {
        // Date: '2018-1-15'
        auto d = Date(2018, 1, 15);
        auto v = toValue(d);

        assert(v.oidType == OidType.Date);
        assert(v.as!Date == d);
    }

    {
        auto d = immutable Date(2018, 1, 15);
        auto v = toValue(d);

        assert(v.oidType == OidType.Date);
        assert(v.as!Date == d);
    }

    {
        // Date: '2000-1-1'
        auto d = Date(2000, 1, 1);
        auto v = toValue(d);

        assert(v.oidType == OidType.Date);
        assert(v.as!Date == d);
    }

    {
        // Date: '0010-2-20'
        auto d = Date(10, 2, 20);
        auto v = toValue(d);

        assert(v.oidType == OidType.Date);
        assert(v.as!Date == d);
    }

    {
        // DateTime
        auto d = const DateTime(2018, 2, 20, 1, 2, 3);
        auto v = toValue(d);

        assert(v.oidType == OidType.TimeStamp);
        assert(v.as!DateTime == d);
    }

    {
        // TimeOfDay: '14:29:17'
        auto tod = TimeOfDay(14, 29, 17);
        auto v = toValue(tod);

        assert(v.oidType == OidType.Time);
        assert(v.as!TimeOfDay == tod);
    }

    {
        // SysTime: '2017-11-13T14:29:17.075678Z'
        auto t = SysTime.fromISOExtString("2017-11-13T14:29:17.075678Z");
        auto v = toValue(t);

        assert(v.oidType == OidType.TimeStampWithZone);
        assert(v.as!SysTime == t);
    }

    {
        import core.time : usecs;
        import std.datetime.date : DateTime;

        // TimeStampWithoutTZ: '2017-11-13 14:29:17.075678'
        auto t = TimeStampWithoutTZ(DateTime(2017, 11, 13, 14, 29, 17), 75_678.usecs);
        auto v = toValue(t);

        assert(v.oidType == OidType.TimeStamp);
        assert(v.as!TimeStampWithoutTZ == t);
    }
}
