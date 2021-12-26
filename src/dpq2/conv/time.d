/**
*   PostgreSQL time types binary format.
*
*   Copyright: © 2014 DSoftOut
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.conv.time;

@safe:

import dpq2.result;
import dpq2.oids: OidType;
import dpq2.value: throwTypeComplaint;

import core.time;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime: SysTime;
import std.datetime.timezone: LocalTime, TimeZone, UTC;
import std.bitmanip: bigEndianToNative, nativeToBigEndian;
import std.math;
import std.conv: to;

/++
    Returns value timestamp with time zone as SysTime

    Note that SysTime has a precision in hnsecs and PG TimeStamp in usecs.
    It means that PG value will have 10 times lower precision.
    And as both types are using long for internal storage it also means that PG TimeStamp can store greater range of values than SysTime.

    Because of these differences, it can happen that database value will not fit to the SysTime range of values.
+/
SysTime binaryValueAs(T)(in Value v) @trusted
if( is( T == SysTime ) )
{
    if(!(v.oidType == OidType.TimeStampWithZone))
        throwTypeComplaint(v.oidType, "timestamp with time zone", __FILE__, __LINE__);

    if(!(v.data.length == long.sizeof))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp with time zone type", __FILE__, __LINE__);

    auto t = rawTimeStamp2nativeTime!TimeStampUTC(bigEndianToNative!long(v.data.ptr[0..long.sizeof]));
    return SysTime(t.dateTime, t.fracSec, UTC());
}

pure:

/// Returns value data as native Date
Date binaryValueAs(T)(in Value v) @trusted
if( is( T == Date ) )
{
    if(!(v.oidType == OidType.Date))
        throwTypeComplaint(v.oidType, "Date", __FILE__, __LINE__);

    if(!(v.data.length == uint.sizeof))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres date type", __FILE__, __LINE__);

    int jd = bigEndianToNative!uint(v.data.ptr[0..uint.sizeof]);
    int year, month, day;
    j2date(jd, year, month, day);

    // TODO: support PG Date like TTimeStamp manner and remove this check
    if(year > short.max)
        throw new ValueConvException(ConvExceptionType.DATE_VALUE_OVERFLOW,
            "Year "~year.to!string~" is bigger than supported by std.datetime.Date", __FILE__, __LINE__);

    return Date(year, month, day);
}

/// Returns value time without time zone as native TimeOfDay
TimeOfDay binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeOfDay ) )
{
    if(!(v.oidType == OidType.Time))
        throwTypeComplaint(v.oidType, "time without time zone", __FILE__, __LINE__);

    if(!(v.data.length == TimeADT.sizeof))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres time without time zone type", __FILE__, __LINE__);

    return time2tm(bigEndianToNative!TimeADT(v.data.ptr[0..TimeADT.sizeof]));
}

/// Returns value timestamp without time zone as TimeStamp
TimeStamp binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeStamp ) )
{
    if(!(v.oidType == OidType.TimeStamp))
        throwTypeComplaint(v.oidType, "timestamp without time zone", __FILE__, __LINE__);

    if(!(v.data.length == long.sizeof))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp without time zone type", __FILE__, __LINE__);

    return rawTimeStamp2nativeTime!TimeStamp(
        bigEndianToNative!long(v.data.ptr[0..long.sizeof])
    );
}

/// Returns value timestamp with time zone as TimeStampUTC
TimeStampUTC binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeStampUTC ) )
{
    if(!(v.oidType == OidType.TimeStampWithZone))
        throwTypeComplaint(v.oidType, "timestamp with time zone", __FILE__, __LINE__);

    if(!(v.data.length == long.sizeof))
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp with time zone type", __FILE__, __LINE__);

    return rawTimeStamp2nativeTime!TimeStampUTC(
        bigEndianToNative!long(v.data.ptr[0..long.sizeof])
    );
}

/// Returns value timestamp without time zone as DateTime (it drops the fracSecs from the database value)
DateTime binaryValueAs(T)(in Value v) @trusted
if( is( T == DateTime ) )
{
    return v.binaryValueAs!TimeStamp.dateTime;
}

///
enum InfinityState : byte
{
    NONE = 0, ///
    INFINITY_MIN = -1, ///
    INFINITY_MAX = 1, ///
}

///
struct PgDate
{
    int year; ///
    ubyte month; ///
    ubyte day; ///

    /// '-infinity', earlier than all other dates
    static PgDate earlier() pure { return PgDate(int.min, 0, 0); }

    /// 'infinity', later than all other dates
    static PgDate later() pure { return PgDate(int.max, 0, 0); }

    bool isEarlier() const pure { return year == earlier.year; } /// '-infinity'
    bool isLater() const pure { return year == later.year; } /// 'infinity'
}

///
static toPgDate(Date d) pure
{
    return PgDate(d.year, d.month, d.day);
}

/++
    Structure to represent PostgreSQL Timestamp with/without time zone
+/
struct TTimeStamp(bool isWithTZ)
{
    /**
     * Date and time of TimeStamp
     *
     * If value is '-infinity' or '+infinity' it will be equal PgDate.min or PgDate.max
     */
    PgDate date;
    TimeOfDay time; ///
    Duration fracSec; /// fractional seconds, 1 microsecond resolution

    ///
    this(DateTime dt, Duration fractionalSeconds = Duration.zero) pure
    {
        this(dt.date.toPgDate, dt.timeOfDay, fractionalSeconds);
    }

    ///
    this(PgDate d, TimeOfDay t = TimeOfDay(), Duration fractionalSeconds = Duration.zero) pure
    {
        date = d;
        time = t;
        fracSec = fractionalSeconds;
    }

    ///
    void throwIfNotFitsToDate() const
    {
        if(date.year > short.max)
            throw new ValueConvException(ConvExceptionType.DATE_VALUE_OVERFLOW,
                "Year "~date.year.to!string~" is bigger than supported by std.datetime", __FILE__, __LINE__);
    }

    ///
    DateTime dateTime() const pure
    {
        if(infinity != InfinityState.NONE)
            throw new ValueConvException(ConvExceptionType.DATE_VALUE_OVERFLOW,
                "TTimeStamp value is "~infinity.to!string, __FILE__, __LINE__);

        throwIfNotFitsToDate();

        return DateTime(Date(date.year, date.month, date.day), time);
    }

    invariant()
    {
        assert(fracSec < 1.seconds, "fracSec can't be more than 1 second but contains "~fracSec.to!string);
        assert(fracSec >= Duration.zero, "fracSec is negative: "~fracSec.to!string);
        assert(fracSec % 1.usecs == 0.hnsecs, "fracSec have 1 microsecond resolution but contains "~fracSec.to!string);
    }

    bool isEarlier() const pure { return date.isEarlier; } /// '-infinity'
    bool isLater() const pure { return date.isLater; } /// 'infinity'

    /// Returns infinity state
    InfinityState infinity() const pure
    {
        with(InfinityState)
        {
            if(isEarlier) return INFINITY_MIN;
            if(isLater) return INFINITY_MAX;

            return NONE;
        }
    }

    unittest
    {
        assert(TTimeStamp.min == TTimeStamp.min);
        assert(TTimeStamp.max == TTimeStamp.max);
        assert(TTimeStamp.min != TTimeStamp.max);

        assert(TTimeStamp.earlier != TTimeStamp.later);
        assert(TTimeStamp.min != TTimeStamp.earlier);
        assert(TTimeStamp.max != TTimeStamp.later);

        assert(TTimeStamp.min.infinity == InfinityState.NONE);
        assert(TTimeStamp.max.infinity == InfinityState.NONE);
        assert(TTimeStamp.earlier.infinity == InfinityState.INFINITY_MIN);
        assert(TTimeStamp.later.infinity == InfinityState.INFINITY_MAX);
    }

    /// Returns the TimeStamp farthest in the past which is representable by TimeStamp.
    static immutable(TTimeStamp) min()
    {
        /*
        Postgres low value is 4713 BC but here is used -4712 because
        "Date uses the Proleptic Gregorian Calendar, so it assumes the
        Gregorian leap year calculations for its entire length. As per
        ISO 8601, it treats 1 B.C. as year 0, i.e. 1 B.C. is 0, 2 B.C.
        is -1, etc." (Phobos docs). But Postgres isn't uses ISO 8601
        for date calculation.
        */
        return TTimeStamp(PgDate(-4712, 1, 1), TimeOfDay.min, Duration.zero);
    }

    /// Returns the TimeStamp farthest in the future which is representable by TimeStamp.
    static immutable(TTimeStamp) max()
    {
        enum maxFract = 1.seconds - 1.usecs;

        return TTimeStamp(PgDate(294276, 12, 31), TimeOfDay(23, 59, 59), maxFract);
    }

    /// '-infinity', earlier than all other time stamps
    static immutable(TTimeStamp) earlier() pure { return TTimeStamp(PgDate.earlier); }

    /// 'infinity', later than all other time stamps
    static immutable(TTimeStamp) later() pure { return TTimeStamp(PgDate.later); }

    ///
    string toString() const
    {
        import std.format;

        return format("%04d-%02d-%02d %s %s", date.year, date.month, date.day, time, fracSec.toString);
    }
}

alias TimeStamp = TTimeStamp!false; /// Unknown TZ timestamp
alias TimeStampUTC = TTimeStamp!true; /// Assumed that this is UTC timestamp

unittest
{
    auto t = TimeStamp(DateTime(2017, 11, 13, 14, 29, 17), 75_678.usecs);
    assert(t.dateTime.hour == 14);
}

unittest
{
    auto dt = DateTime(2017, 11, 13, 14, 29, 17);
    auto t = TimeStamp(dt, 75_678.usecs);

    assert(t.dateTime == dt); // test the implicit conversion to DateTime
}

unittest
{
    auto t = TimeStampUTC(
            DateTime(2017, 11, 13, 14, 29, 17),
            75_678.usecs
        );

    assert(t.dateTime.hour == 14);
    assert(t.fracSec == 75_678.usecs);
}

unittest
{
    import std.exception : assertThrown;

    auto e = TimeStampUTC.earlier;
    auto l = TimeStampUTC.later;

    assertThrown!ValueConvException(e.dateTime.hour == 14);
    assertThrown!ValueConvException(l.dateTime.hour == 14);
}

/// Oid tests
unittest
{
    assert(detectOidTypeFromNative!TimeStamp == OidType.TimeStamp);
    assert(detectOidTypeFromNative!TimeStampUTC == OidType.TimeStampWithZone);
    assert(detectOidTypeFromNative!SysTime == OidType.TimeStampWithZone);
    assert(detectOidTypeFromNative!Date == OidType.Date);
    assert(detectOidTypeFromNative!TimeOfDay == OidType.Time);
}

///
struct TimeOfDayWithTZ
{
    TimeOfDay time; ///
    TimeTZ tzSec; /// Time zone offset from UTC in seconds with east of UTC being negative
}

/// Returns value time with time zone as TimeOfDayWithTZ
TimeOfDayWithTZ binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeOfDayWithTZ ) )
{
    if(!(v.oidType == OidType.TimeWithZone))
        throwTypeComplaint(v.oidType, "time with time zone", __FILE__, __LINE__);

    enum recSize = TimeADT.sizeof + TimeTZ.sizeof;
    static assert(recSize == 12);

    if(v.data.length != recSize)
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres time with time zone type", __FILE__, __LINE__);

    return TimeOfDayWithTZ(
        time2tm(bigEndianToNative!TimeADT(v.data.ptr[0 .. TimeADT.sizeof])),
        bigEndianToNative!TimeTZ(v.data.ptr[TimeADT.sizeof .. recSize])
    );
}

package enum POSTGRES_EPOCH_DATE = Date(2000, 1, 1);
package enum POSTGRES_EPOCH_JDATE = POSTGRES_EPOCH_DATE.julianDay;
static assert(POSTGRES_EPOCH_JDATE == 2_451_545); // value from Postgres code

private:

T rawTimeStamp2nativeTime(T)(long raw)
if(is(T == TimeStamp) || is(T == TimeStampUTC))
{
    import core.stdc.time: time_t;

    if(raw == long.max) return T.later; // infinity
    if(raw == long.min) return T.earlier; // -infinity

    pg_tm tm;
    fsec_t ts;

    if(timestamp2tm(raw, tm, ts) < 0)
        throw new ValueConvException(
            ConvExceptionType.OUT_OF_RANGE, "Timestamp is out of range",
        );

    TimeStamp ret = raw_pg_tm2nativeTime(tm, ts);

    static if(is(T == TimeStamp))
        return ret;
    else
        return TimeStampUTC(ret.dateTime, ret.fracSec);
}

TimeStamp raw_pg_tm2nativeTime(pg_tm tm, fsec_t ts)
{
    return TimeStamp(
        PgDate(
            tm.tm_year,
            cast(ubyte) tm.tm_mon,
            cast(ubyte) tm.tm_mday
        ),
        TimeOfDay(
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        ),
        ts.dur!"usecs"
    );
}

// Here is used names from the original Postgresql source

void j2date(int jd, out int year, out int month, out int day)
{
    enum MONTHS_PER_YEAR = 12;

    jd += POSTGRES_EPOCH_JDATE;

    uint julian = jd + 32044;
    uint quad = julian / 146097;
    uint extra = (julian - quad * 146097) * 4 + 3;
    julian += 60 + quad * 3 + extra / 146097;
    quad = julian / 1461;
    julian -= quad * 1461;
    int y = julian * 4 / 1461;
    julian = ((y != 0) ? ((julian + 305) % 365) : ((julian + 306) % 366))
        + 123;
    year = (y+ quad * 4) - 4800;
    quad = julian * 2141 / 65536;
    day = julian - 7834 * quad / 256;
    month = (quad + 10) % MONTHS_PER_YEAR + 1;
}

private alias long Timestamp;
private alias long TimestampTz;
private alias long TimeADT;
private alias int  TimeTZ;
private alias long TimeOffset;
private alias int  fsec_t;      /* fractional seconds (in microseconds) */

void TMODULO(ref long t, ref long q, double u)
{
    q = cast(long)(t / u);
    if (q != 0) t -= q * cast(long)u;
}

TimeOfDay time2tm(TimeADT time)
{
    immutable long USECS_PER_HOUR  = 3600000000;
    immutable long USECS_PER_MINUTE = 60000000;
    immutable long USECS_PER_SEC = 1000000;

    int tm_hour = cast(int)(time / USECS_PER_HOUR);
    time -= tm_hour * USECS_PER_HOUR;
    int tm_min = cast(int)(time / USECS_PER_MINUTE);
    time -= tm_min * USECS_PER_MINUTE;
    int tm_sec = cast(int)(time / USECS_PER_SEC);
    time -= tm_sec * USECS_PER_SEC;

    return TimeOfDay(tm_hour, tm_min, tm_sec);
}

struct pg_tm
{
    int         tm_sec;
    int         tm_min;
    int         tm_hour;
    int         tm_mday;
    int         tm_mon;         /* origin 0, not 1 */
    int         tm_year;        /* relative to 1900 */
    int         tm_wday;
    int         tm_yday;
    int         tm_isdst;
    long        tm_gmtoff;
    string      tm_zone;
}

alias pg_time_t = long;

enum USECS_PER_DAY       = 86_400_000_000UL;
enum USECS_PER_HOUR      = 3_600_000_000UL;
enum USECS_PER_MINUTE    = 60_000_000UL;
enum USECS_PER_SEC       = 1_000_000UL;

/**
* timestamp2tm() - Convert timestamp data type to POSIX time structure.
*
* Note that year is _not_ 1900-based, but is an explicit full value.
* Also, month is one-based, _not_ zero-based.
* Returns:
*   0 on success
*  -1 on out of range
*
* If attimezone is null, the global timezone (including possibly brute forced
* timezone) will be used.
*/
int timestamp2tm(Timestamp dt, out pg_tm tm, out fsec_t fsec)
{
    Timestamp   date;
    Timestamp   time;
    pg_time_t   utime;

    time = dt;
    TMODULO(time, date, USECS_PER_DAY);

    if (time < 0)
    {
        time += USECS_PER_DAY;
        date -= 1;
    }

    j2date(cast(int) date, tm.tm_year, tm.tm_mon, tm.tm_mday);
    dt2time(time, tm.tm_hour, tm.tm_min, tm.tm_sec, fsec);

    return 0;
}

void dt2time(Timestamp jd, out int hour, out int min, out int sec, out fsec_t fsec)
{
    TimeOffset  time;

    time = jd;
    hour = cast(int)(time / USECS_PER_HOUR);
    time -= hour * USECS_PER_HOUR;
    min = cast(int)(time / USECS_PER_MINUTE);
    time -= min * USECS_PER_MINUTE;
    sec = cast(int)(time / USECS_PER_SEC);
    fsec = cast(int)(time - sec*USECS_PER_SEC);
}
