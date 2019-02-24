///
module dpq2.conv.from_d_types;

@safe:

public import dpq2.conv.arrays : isArrayType, toValue;
public import dpq2.conv.geometric : toValue;
import dpq2.conv.time : POSTGRES_EPOCH_DATE, TimeStamp, TimeStampUTC;
import dpq2.oids : detectOidTypeFromNative, oidConvTo, OidType;
import dpq2.value : Value, ValueFormat;

import std.bitmanip: nativeToBigEndian;
import std.datetime.date: Date, DateTime, TimeOfDay;
import std.datetime.systime: SysTime;
import std.datetime.timezone: LocalTime, TimeZone, UTC;
import std.traits: isImplicitlyConvertible, isNumeric, isInstanceOf, OriginalType, Unqual;
import std.typecons : Nullable;
import std.uuid: UUID;
import vibe.data.json: Json;
import money: currency;

/// Converts Nullable!T to Value
Value toValue(T)(T v)
if (is(T == Nullable!R, R) && !(isArrayType!(typeof(v.get))))
{
    if (v.isNull)
        return Value(ValueFormat.BINARY, detectOidTypeFromNative!T);
    else
        return toValue(v.get);
}

/// ditto
Value toValue(T)(T v)
if (is(T == Nullable!R, R) && (isArrayType!(typeof(v.get))))
{
    import dpq2.conv.arrays : arrToValue = toValue; // deprecation import workaround
    import std.range : ElementType;

    if (v.isNull)
        return Value(ValueFormat.BINARY, detectOidTypeFromNative!(ElementType!(typeof(v.get))).oidConvTo!"array");
    else
        return arrToValue(v.get);
}

///
Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

///
Value toValue(T)(T v)
if(isInstanceOf!(currency, T) &&  T.amount.sizeof == 8)
{
    return Value(v.amount.nativeToBigEndian.dup, OidType.Money, false, ValueFormat.BINARY);
}

unittest
{
    import dpq2.conv.to_d_types: PGTestMoney;

    const pgtm = PGTestMoney("123.45");

    Value v = pgtm.toValue;

    assert(v.oidType == OidType.Money);
    assert(v.as!PGTestMoney == pgtm);
}

/**
    Converts types implicitly convertible to string to PG Value.
    Note that if string is null it is written as an empty string.
    If NULL is a desired DB value, Nullable!string can be used instead.
*/
Value toValue(T)(T v, ValueFormat valueFormat = ValueFormat.BINARY) @trusted
if(is(T : string))
{
    import std.string : representation;

    static assert(isImplicitlyConvertible!(T, string));
    auto buf = (cast(string) v).representation;

    if(valueFormat == ValueFormat.TEXT) buf ~= 0; // for prepareArgs only

    return Value(buf, OidType.Text, false, valueFormat);
}

/// Constructs Value from array of bytes
Value toValue(T)(T v)
if(is(T : immutable(ubyte)[]))
{
    return Value(v, detectOidTypeFromNative!(ubyte[]), false, ValueFormat.BINARY);
}

/// Constructs Value from boolean
Value toValue(T : bool)(T v) @trusted
if (!is(T == Nullable!R, R))
{
    immutable ubyte[] buf = [ v ? 1 : 0 ];

    return Value(buf, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

/// Constructs Value from Date
Value toValue(T)(T v)
if (is(Unqual!T == Date))
{
    import std.conv: to;
    import dpq2.value;
    import dpq2.conv.time: POSTGRES_EPOCH_JDATE;

    long mj_day = v.modJulianDay;

    // max days isn't checked because Phobos Date days value always fits into Postgres Date
    if (mj_day < -POSTGRES_EPOCH_JDATE)
        throw new ValueConvException(
                ConvExceptionType.DATE_VALUE_OVERFLOW,
                "Date value doesn't fit into Postgres binary Date",
                __FILE__, __LINE__
            );

    enum mj_pg_epoch = POSTGRES_EPOCH_DATE.modJulianDay;
    long days = mj_day - mj_pg_epoch;

    return Value(nativeToBigEndian(days.to!int).dup, OidType.Date, false);
}

/// Constructs Value from TimeOfDay
Value toValue(T)(T v)
if (is(Unqual!T == TimeOfDay))
{
    long us = ((60L * v.hour + v.minute) * 60 + v.second) * 1_000_000;

    return Value(nativeToBigEndian(us).dup, OidType.Time, false);
}

/// Constructs Value from TimeStamp or from TimeStampUTC
Value toValue(T)(T v)
if (is(Unqual!T == TimeStamp) || is(Unqual!T == TimeStampUTC))
{
    long us; /// microseconds

    if(v.isLater) // infinity
        us = us.max;
    else if(v.isEarlier) // -infinity
        us = us.min;
    else
    {
        enum mj_pg_epoch = POSTGRES_EPOCH_DATE.modJulianDay;
        long j = modJulianDayForIntYear(v.date.year, v.date.month, v.date.day) - mj_pg_epoch;
        us = (((j * 24 + v.time.hour) * 60 + v.time.minute) * 60 + v.time.second) * 1_000_000 + v.fracSec.total!"usecs";
    }

    return Value(
            nativeToBigEndian(us).dup,
            is(Unqual!T == TimeStamp) ? OidType.TimeStamp : OidType.TimeStampWithZone,
            false
        );
}

private auto modJulianDayForIntYear(const int year, const ubyte month, const short day) pure
{
    // Wikipedia magic:

    const a = (14 - month) / 12;
    const y = year + 4800 - a;
    const m = month + a * 12 - 3;

    const jd = day + (m*153+2)/5 + y*365 + y/4 - y/100 + y/400 - 32045;

    return jd - 2_400_001;
}
unittest
{
    assert(modJulianDayForIntYear(1858, 11, 17) == 0);
    assert(modJulianDayForIntYear(2010, 8, 24) == 55_432);
    assert(modJulianDayForIntYear(1999, 7, 6) == 51_365);
}

/++
    Constructs Value from DateTime
    It uses Timestamp without TZ as a resulting PG type
+/
Value toValue(T)(T v)
if (is(Unqual!T == DateTime))
{
    return TimeStamp(v).toValue;
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

/// Constructs Value from UUID
Value toValue(T)(T v)
if (is(Unqual!T == UUID))
{
    return Value(v.data.dup, OidType.UUID);
}

/// Constructs Value from Json
Value toValue(T)(T v)
if (is(Unqual!T == Json))
{
    auto r = toValue(v.toString);
    r.oidType = OidType.Json;

    return r;
}

version(unittest)
import dpq2.conv.to_d_types : as;

unittest
{
    Value v = toValue(cast(short) 123);

    assert(v.oidType == OidType.Int2);
    assert(v.as!short == 123);
}

unittest
{
    Value v = toValue(-123.456);

    assert(v.oidType == OidType.Float8);
    assert(v.as!double == -123.456);
}

unittest
{
    Value v = toValue("Test string");

    assert(v.oidType == OidType.Text);
    assert(v.as!string == "Test string");
}

// string Null values
@system unittest
{
    {
        import core.exception: AssertError;
        import std.exception: assertThrown;

        auto v = Nullable!string.init.toValue;
        assert(v.oidType == OidType.Text);
        assert(v.isNull);

        assertThrown!AssertError(v.as!string);
        assert(v.as!(Nullable!string).isNull);
    }

    {
        string s;
        auto v = s.toValue;
        assert(v.oidType == OidType.Text);
        assert(!v.isNull);
    }
}

unittest
{
    immutable ubyte[] buf = [0, 1, 2, 3, 4, 5];
    Value v = toValue(buf);

    assert(v.oidType == OidType.ByteArray);
    assert(v.as!(const ubyte[]) == buf);
}

unittest
{
    Value t = toValue(true);
    Value f = toValue(false);

    assert(t.as!bool == true);
    assert(f.as!bool == false);
}

unittest
{
    Value v = toValue(Nullable!long(1));
    Value nv = toValue(Nullable!bool.init);

    assert(!v.isNull);
    assert(v.oidType == OidType.Int8);
    assert(v.as!long == 1);

    assert(nv.isNull);
    assert(nv.oidType == OidType.Bool);
}

unittest
{
    import std.datetime : DateTime;

    Value v = toValue(Nullable!TimeStamp(TimeStamp(DateTime(2017, 1, 2))));

    assert(!v.isNull);
    assert(v.oidType == OidType.TimeStamp);
}

unittest
{
    // Date: '2018-1-15'
    auto d = Date(2018, 1, 15);
    auto v = toValue(d);

    assert(v.oidType == OidType.Date);
    assert(v.as!Date == d);
}

unittest
{
    auto d = immutable Date(2018, 1, 15);
    auto v = toValue(d);

    assert(v.oidType == OidType.Date);
    assert(v.as!Date == d);
}

unittest
{
    // Date: '2000-1-1'
    auto d = Date(2000, 1, 1);
    auto v = toValue(d);

    assert(v.oidType == OidType.Date);
    assert(v.as!Date == d);
}

unittest
{
    // Date: '0010-2-20'
    auto d = Date(10, 2, 20);
    auto v = toValue(d);

    assert(v.oidType == OidType.Date);
    assert(v.as!Date == d);
}

unittest
{
    // Date: max (always fits into Postgres Date)
    auto d = Date.max;
    auto v = toValue(d);

    assert(v.oidType == OidType.Date);
    assert(v.as!Date == d);
}

unittest
{
    // Date: min (overflow)
    import std.exception: assertThrown;
    import dpq2.value: ValueConvException;

    auto d = Date.min;
    assertThrown!ValueConvException(d.toValue);
}

unittest
{
    // DateTime
    auto d = const DateTime(2018, 2, 20, 1, 2, 3);
    auto v = toValue(d);

    assert(v.oidType == OidType.TimeStamp);
    assert(v.as!DateTime == d);
}

unittest
{
    // Nullable!DateTime
    import std.typecons : nullable;
    auto d = nullable(DateTime(2018, 2, 20, 1, 2, 3));
    auto v = toValue(d);

    assert(v.oidType == OidType.TimeStamp);
    assert(v.as!(Nullable!DateTime) == d);

    d.nullify();
    v = toValue(d);
    assert(v.oidType == OidType.TimeStamp);
    assert(v.as!(Nullable!DateTime).isNull);
}

unittest
{
    // TimeOfDay: '14:29:17'
    auto tod = TimeOfDay(14, 29, 17);
    auto v = toValue(tod);

    assert(v.oidType == OidType.Time);
    assert(v.as!TimeOfDay == tod);
}

unittest
{
    // SysTime: '2017-11-13T14:29:17.075678Z'
    auto t = SysTime.fromISOExtString("2017-11-13T14:29:17.075678Z");
    auto v = toValue(t);

    assert(v.oidType == OidType.TimeStampWithZone);
    assert(v.as!SysTime == t);
}

unittest
{
    import core.time : usecs;
    import std.datetime.date : DateTime;

    // TimeStamp: '2017-11-13 14:29:17.075678'
    auto t = TimeStamp(DateTime(2017, 11, 13, 14, 29, 17), 75_678.usecs);
    auto v = toValue(t);

    assert(v.oidType == OidType.TimeStamp);
    assert(v.as!TimeStamp == t);
}

unittest
{
    auto j = Json(["foo":Json("bar")]);
    auto v = j.toValue;

    assert(v.oidType == OidType.Json);
    assert(v.as!Json == j);

    auto nj = Nullable!Json(j);
    auto nv = nj.toValue;
    assert(nv.oidType == OidType.Json);
    assert(!nv.as!(Nullable!Json).isNull);
    assert(nv.as!(Nullable!Json).get == j);
}
