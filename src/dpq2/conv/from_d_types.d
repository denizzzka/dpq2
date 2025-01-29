///
module dpq2.conv.from_d_types;

@safe:

public import dpq2.conv.arrays : isArrayType, toValue, isStaticArrayString;
public import dpq2.conv.geometric : isGeometricType, toValue;
import dpq2.conv.time : POSTGRES_EPOCH_DATE, TimeStamp, TimeStampUTC, TimeOfDayWithTZ, Interval;
import dpq2.conv.ranges;
import dpq2.oids : detectOidTypeFromNative, oidConvTo, OidType;
import dpq2.value : Value, ValueFormat;

import std.bitmanip: nativeToBigEndian, BitArray, append;
import std.datetime.date: Date, DateTime, TimeOfDay;
import std.datetime.systime: SysTime;
import std.datetime.timezone: LocalTime, TimeZone, UTC;
import std.traits: isImplicitlyConvertible, isNumeric, isInstanceOf, OriginalType, Unqual, isSomeString, TemplateOf;
import std.typecons : Nullable;
import std.uuid: UUID;
import vibe.data.json: Json;
import money: currency;

/// Converts Nullable!T to Value
Value toValue(T)(T v)
if (is(T == Nullable!R, R) && !(isArrayType!(typeof(v.get))) && !isGeometricType!(typeof(v.get)))
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

/// ditto
Value toValue(T)(T v)
if (is(T == Nullable!R, R) && isGeometricType!(typeof(v.get)))
{
    import dpq2.conv.geometric : geoToValue = toValue; // deprecation import workaround

    if (v.isNull)
        return Value(ValueFormat.BINARY, detectOidTypeFromNative!T);
    else
        return geoToValue(v.get);
}

///
Value toValue(T)(T v)
if(isNumeric!(T))
{
    return Value(v.nativeToBigEndian.dup, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

/// Convert money.currency to PG value
///
/// Caution: here is no check of fractional precision while conversion!
/// See also: PostgreSQL's "lc_monetary" description and "money" package description
Value toValue(T)(T v)
if(isInstanceOf!(currency, T) &&  T.amount.sizeof == 8)
{
    return Value(v.amount.nativeToBigEndian.dup, OidType.Money, false, ValueFormat.BINARY);
}

unittest
{
    import dpq2.conv.to_d_types: PGTestMoney;

    const pgtm = PGTestMoney(-123.45);

    Value v = pgtm.toValue;

    assert(v.oidType == OidType.Money);
    assert(v.as!PGTestMoney == pgtm);
}

/// Convert std.bitmanip.BitArray to PG value
Value toValue(T)(T v) @trusted
if(is(Unqual!T == BitArray))
{
    import std.array : appender;
    import core.bitop : bitswap;

    size_t len = v.length / 8 + (v.length % 8 ? 1 : 0);
    auto data = cast(size_t[])v;
    auto buffer = appender!(const ubyte[])();
    buffer.append!uint(cast(uint)v.length);
    foreach (d; data[0 .. v.dim])
    {
        //FIXME: DMD Issue 19693
        version(DigitalMars)
            auto ntb = nativeToBigEndian(softBitswap(d));
        else
            auto ntb = nativeToBigEndian(bitswap(d));
        foreach (b; ntb[0 .. len])
        {
            buffer.append!ubyte(b);
        }

    }
    return Value(buffer.data.dup, detectOidTypeFromNative!T, false, ValueFormat.BINARY);
}

/// Reverses the order of bits - needed because of dmd Issue 19693
/// https://issues.dlang.org/show_bug.cgi?id=19693
package N softBitswap(N)(N x) pure
    if (is(N == uint) || is(N == ulong))
{
    import core.bitop : bswap;
    // swap 1-bit pairs:
    enum mask1 = cast(N) 0x5555_5555_5555_5555L;
    x = ((x >> 1) & mask1) | ((x & mask1) << 1);
    // swap 2-bit pairs:
    enum mask2 = cast(N) 0x3333_3333_3333_3333L;
    x = ((x >> 2) & mask2) | ((x & mask2) << 2);
    // swap 4-bit pairs:
    enum mask4 = cast(N) 0x0F0F_0F0F_0F0F_0F0FL;
    x = ((x >> 4) & mask4) | ((x & mask4) << 4);

    // reverse the order of all bytes:
    x = bswap(x);

    return x;
}

@trusted unittest
{
    import std.bitmanip : BitArray;

    auto varbit = BitArray([1,0,1,1,0]);

    Value v = varbit.toValue;

    assert(v.oidType == OidType.VariableBitString);
    assert(v.as!BitArray == varbit);

    // test softBitswap
    assert (softBitswap!uint( 0x8000_0100 ) == 0x0080_0001);
    foreach (i; 0 .. 32)
        assert (softBitswap!uint(1 << i) == 1 << 32 - i - 1);

    assert (softBitswap!ulong( 0b1000000000000000000000010000000000000000100000000000000000000001)
            == 0b1000000000000000000000010000000000000000100000000000000000000001);
    assert (softBitswap!ulong( 0b1110000000000000000000010000000000000000100000000000000000000001)
        == 0b1000000000000000000000010000000000000000100000000000000000000111);
    foreach (i; 0 .. 64)
        assert (softBitswap!ulong(1UL << i) == 1UL << 64 - i - 1);

}

/**
    Converts types implicitly convertible to string to PG Value.
    Note that if string is null it is written as an empty string.
    If NULL is a desired DB value, Nullable!string can be used instead.
*/
Value toValue(T)(T v, ValueFormat valueFormat = ValueFormat.BINARY) @trusted
if(isSomeString!T || isStaticArrayString!T)
{
    static if(is(T == string))
    {
        import std.string : representation;

        static assert(isImplicitlyConvertible!(T, string));
        auto buf = (cast(string) v).representation;

        if(valueFormat == ValueFormat.TEXT) buf ~= 0; // for prepareArgs only

        return Value(buf, OidType.Text, false, valueFormat);
    }
    else
    {
        // convert to a string
        import std.conv : to;
        return toValue(v.to!string, valueFormat);
    }
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

private long convTimeOfDayToPG(in TimeOfDay v) pure
{
    return ((60L * v.hour + v.minute) * 60 + v.second) * 1_000_000;
}

/// Constructs Value from TimeOfDay
Value toValue(T)(T v)
if (is(Unqual!T == TimeOfDay))
{
    return Value(v.convTimeOfDayToPG.nativeToBigEndian.dup, OidType.Time);
}

/// Constructs Value from TimeOfDay
Value toValue(T)(T v)
if (is(Unqual!T == TimeOfDayWithTZ))
{
    const buf = v.time.convTimeOfDayToPG.nativeToBigEndian ~ v.tzSec.nativeToBigEndian;
    assert(buf.length == 12);

    return Value(buf.dup, OidType.TimeWithZone);
}

/// Constructs Value from Interval
Value toValue(T)(T v)
if (is(Unqual!T == Interval))
{
    const buf = v.usecs.nativeToBigEndian ~ v.days.nativeToBigEndian ~ v.months.nativeToBigEndian;
    assert(buf.length == 16);

    return Value(buf.dup, OidType.TimeInterval);
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
    import dpq2.value: ValueConvException, ConvExceptionType;
    import core.time;
    import std.conv: to;

    long usecs;
    int hnsecs;
    v.fracSecs.split!("usecs", "hnsecs")(usecs, hnsecs);

    if(hnsecs)
        throw new ValueConvException(
            ConvExceptionType.TOO_PRECISE,
            "fracSecs have 1 microsecond resolution but contains "~v.fracSecs.to!string
        );

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

Value toRecordValue(Value[] elements)
{
    import std.array : appender;
    auto buffer = appender!(ubyte[])();
    buffer ~= nativeToBigEndian!int(cast(int)elements.length)[];
    foreach (element; elements)
    {
        buffer ~= nativeToBigEndian!int(element.oidType)[];
        if (element.isNull) {
            buffer ~= nativeToBigEndian!int(-1)[];
        } else {
            buffer ~= nativeToBigEndian!int(cast(int)element.data.length)[];
            buffer ~= element.data;
        }
    }

    return Value(buffer.data.idup, OidType.Record);
}

/// Constructs Value from Ranges
Value toValue(R)(R r)
if (__traits(isSame, TemplateOf!R, Range))
{
    static if (is(R == Int4Range))  return Value(r.rawData.idup, OidType.Int4Range);
    static if (is(R == Int8Range))  return Value(r.rawData.idup, OidType.Int8Range);
    static if (is(R == NumRange))   return Value(r.rawData.idup, OidType.NumRange);
    static if (is(R == DateRange))  return Value(r.rawData.idup, OidType.DateRange);
    static if (is(R == TsRange))    return Value(r.rawData.idup, OidType.TimeStampRange);
    static if (is(R == TsTzRange))  return Value(r.rawData.idup, OidType.TimeStampWithZoneRange);
}

/// Constructs Value from Multiranges
Value toValue(M)(M m)
if (__traits(isSame, TemplateOf!M, MultiRange))
{
    static if (is(M == Int4MultiRange)) return Value(m._data.idup, OidType.Int4MultiRange);
    static if (is(M == Int8MultiRange)) return Value(m._data.idup, OidType.Int8MultiRange);
    static if (is(M == NumMultiRange))  return Value(m._data.idup, OidType.NumMultiRange);
    static if (is(M == DateMultiRange)) return Value(m._data.idup, OidType.DateMultiRange);
    static if (is(M == TsMultiRange))   return Value(m._data.idup, OidType.TimeStampMultiRange);
    static if (is(M == TsTzMultiRange)) return Value(m._data.idup, OidType.TimeStampWithZoneMultiRange);
}

version(unittest)
import dpq2.conv.to_d_types : as, deserializeRecord;

unittest
{
    import std.stdio;
    Value[] vals = [toValue(17.34), toValue(Nullable!long(17)), toValue(Nullable!long.init)];
    Value v = vals.toRecordValue;
    assert(deserializeRecord(v) == vals);
}

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
    auto t = TimeOfDayWithTZ(
        TimeOfDay(14, 29, 17),
        -3600 * 7 // Negative means TZ == +07
    );

    auto v = toValue(t);

    assert(v.oidType == OidType.TimeWithZone);
    assert(v.as!TimeOfDayWithTZ == t);
}

unittest
{
    auto t = Interval(
        -123,
        -456,
        -789
    );

    auto v = toValue(t);

    assert(v.oidType == OidType.TimeInterval);
    assert(v.as!Interval == t);
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
    import core.time: dur;
    import std.exception: assertThrown;
    import dpq2.value: ValueConvException;

    auto t = SysTime.fromISOExtString("2017-11-13T14:29:17.075678Z");
    t += dur!"hnsecs"(1);

    // TOO_PRECISE
    assertThrown!ValueConvException(t.toValue);
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

unittest
{
    import dpq2.conv.to_d_types : as;
    char[2] arr;
    auto v = arr.toValue();
    assert(v.oidType == OidType.Text);
    assert(!v.isNull);

    auto varr = v.as!string;
    assert(varr.length == 2);
}
