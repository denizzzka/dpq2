/**
*   PostgreSQL time types binary format.
*
*   Copyright: © 2014 DSoftOut
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.conv.time;

@safe:

import dpq2.result;
import dpq2.oids;
import dpq2.conv.to_d_types: throwTypeComplaint;
import dpq2.exception;

import core.time;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.datetime.systime : LocalTime, SysTime, TimeZone, UTC;
import std.bitmanip: bigEndianToNative, nativeToBigEndian;
import std.math;
import core.stdc.time: time_t;

/// Returns value data as native Date
Date binaryValueAs(T)(in Value v) @trusted
if( is( T == Date ) )
{
    if(!(v.oidType == OidType.Date))
        throwTypeComplaint(v.oidType, "Date", __FILE__, __LINE__);

    if(!(v.data.length == uint.sizeof))
        throw new AnswerConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres date type", __FILE__, __LINE__);

    int jd = bigEndianToNative!uint(v.data.ptr[0..uint.sizeof]);
    int year, month, day;
    j2date(jd, year, month, day);

    return Date(year, month, day);
}

/// Returns value time without time zone as native TimeOfDay
TimeOfDay binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeOfDay ) )
{
    if(!(v.oidType == OidType.Time))
        throwTypeComplaint(v.oidType, "time without time zone", __FILE__, __LINE__);

    if(!(v.data.length == TimeADT.sizeof))
        throw new AnswerConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres time without time zone type", __FILE__, __LINE__);

    return time2tm(bigEndianToNative!TimeADT(v.data.ptr[0..TimeADT.sizeof]));
}

/// Returns value timestamp without time zone as TimeStampWithoutTZ
TimeStampWithoutTZ binaryValueAs(T)(in Value v) @trusted
if( is( T == TimeStampWithoutTZ ) )
{
    if(!(v.oidType == OidType.TimeStamp))
        throwTypeComplaint(v.oidType, "timestamp without time zone", __FILE__, __LINE__);

    if(!(v.data.length == long.sizeof))
        throw new AnswerConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp without time zone type", __FILE__, __LINE__);

    return rawTimeStamp2nativeTime!T(
        bigEndianToNative!long(v.data.ptr[0..long.sizeof])
    );
}

/// Returns value timestamp with time zone as SysTime
SysTime binaryValueAs(T)(in Value v) @trusted
if( is( T == SysTime ) )
{
    if(!(v.oidType == OidType.TimeStampWithZone))
        throwTypeComplaint(v.oidType, "timestamp with time zone", __FILE__, __LINE__);

    if(!(v.data.length == long.sizeof))
        throw new AnswerConvException(ConvExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp with time zone type", __FILE__, __LINE__);

    return rawTimeStamp2nativeTime!T(
        bigEndianToNative!long(v.data.ptr[0..long.sizeof])
    );
}

/++
    Structure to represent PostgreSQL's Timestamp without time zone type.
    It is assumed to be in Local Time.
+/
struct TimeStampWithoutTZ
{
    DateTime dateTime; /// date and time of TimeStamp
    Duration fracSec; /// fractional seconds

    invariant()
    {
        import std.conv : to;
        assert(fracSec >= Duration.zero, fracSec.to!string);
        assert(fracSec < 1.seconds, fracSec.to!string);
    }

    /// Returns the TimeStampWithoutTZ farthest in the future which is representable by TimeStampWithoutTZ.
    static max()
    {
        return TimeStampWithoutTZ(DateTime.max, long.max.hnsecs);
    }

    /// Returns the TimeStampWithoutTZ farthest in the past which is representable by TimeStampWithoutTZ.
    static min()
    {
        return TimeStampWithoutTZ(DateTime.min, Duration.zero);
    }

    /// Converts the value to SysTime with possibility to set the time zone it's in
    SysTime toSysTime(immutable TimeZone tz = LocalTime()) const
    {
        return SysTime(dateTime, fracSec, tz);
    }

    /++
        Creates timestamp without timezone from SysTime.
        It takes the resulting date and time from the SysTime and drops the time zone information.
    +/
    static TimeStampWithoutTZ fromSysTime(in SysTime time)
    {
        return TimeStampWithoutTZ(
            DateTime(time.year, time.month, time.day, time.hour, time.minute, time.second),
            time.fracSecs
        );
    }

    unittest
    {
        {
            import std.datetime.systime : Clock;

            auto t = Clock.currTime; // TZ = local time
            auto ts = TimeStampWithoutTZ.fromSysTime(t);
            auto uts = ts.toSysTime; // TZ = local time

            assert(t.timezone.name == LocalTime().name);
            assert(uts.timezone.name == LocalTime().name);
            assert(t.hour == ts.dateTime.hour);
            assert(ts.dateTime.hour == uts.hour);
            assert(t.hour == uts.hour);

            t = Clock.currTime(UTC()); // TZ = UTC
            ts = TimeStampWithoutTZ.fromSysTime(t);
            uts = ts.toSysTime; // TZ = local time

            assert(t.hour == ts.dateTime.hour);
            assert(ts.dateTime.hour == uts.hour);
            assert(t.hour == uts.hour);
        }
        {
            auto t = TimeStampWithoutTZ(DateTime(2017, 11, 13, 14, 29, 17), 75_678.usecs);
            assert(t.dateTime.hour == 14);
        }
        {
            // check timezone is dropped
            auto t = TimeStampWithoutTZ.fromSysTime(SysTime.fromISOExtString("2017-11-13T14:29:17.075678+02"));
            assert(t.dateTime.hour == 14);
        }
    }
}

package enum POSTGRES_EPOCH_DATE = Date(2000, 1, 1);

private:

T rawTimeStamp2nativeTime(T)(long raw)
if (is(T == TimeStampWithoutTZ) || (is(T == SysTime)))
{
    version(Have_Int64_TimeStamp)
    {
        if(raw >= time_t.max) return T.max;
        if(raw <= time_t.min) return T.min;
    }

    pg_tm tm;
    fsec_t ts;

    if(timestamp2tm(raw, tm, ts) < 0)
        throw new AnswerException(
            ExceptionType.OUT_OF_RANGE, "Timestamp is out of range",
            __FILE__, __LINE__
        );

    return raw_pg_tm2nativeTime!T(tm, ts);
}

T raw_pg_tm2nativeTime(T)(pg_tm tm, fsec_t ts)
if (is(T == TimeStampWithoutTZ) || (is(T == SysTime)))
{
    auto dateTime = DateTime(
            tm.tm_year,
            tm.tm_mon,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        );

    version(Have_Int64_TimeStamp)
    {
        auto fracSec = dur!"usecs"(ts);
    }
    else
    {
        auto fracSec = dur!"usecs"((cast(long)(ts * 10e6)));
    }

    static if (is(T == TimeStampWithoutTZ)) return TimeStampWithoutTZ(dateTime, fracSec);
    else return SysTime(dateTime, fracSec, UTC());
}

// Here is used names from the original Postgresql source

void j2date(int jd, out int year, out int month, out int day)
{
    enum MONTHS_PER_YEAR = 12;
    enum POSTGRES_EPOCH_JDATE = 2_451_545;

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

version(Have_Int64_TimeStamp)
{
    private alias long Timestamp;
    private alias long TimestampTz;
    private alias long TimeADT;
    private alias long TimeOffset;
    private alias int  fsec_t;      /* fractional seconds (in microseconds) */

    void TMODULO(ref long t, ref long q, double u)
    {
        q = cast(long)(t / u);
        if (q != 0) t -= q * cast(long)u;
    }
}
else
{
    private alias Timestamp = double;
    private alias TimestampTz = double;
    private alias TimeADT = double;
    private alias TimeOffset = double;
    private alias fsec_t = double;    /* fractional seconds (in seconds) */

    void TMODULO(T)(ref double t, ref T q, double u)
        if(is(T == double) || is(T == int))
    {
        q = cast(T)((t < 0) ? ceil(t / u) : floor(t / u));
        if (q != 0) t -= rint(q * u);
    }

    double TIMEROUND(double j)
    {
        enum TIME_PREC_INV = 10000000000.0;
        return rint((cast(double) j) * TIME_PREC_INV) / TIME_PREC_INV;
    }
}

TimeOfDay time2tm(TimeADT time)
{
    version(Have_Int64_TimeStamp)
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
    else
    {
        enum SECS_PER_HOUR = 3600;
        enum SECS_PER_MINUTE = 60;

        double      trem;
        int tm_hour, tm_min, tm_sec;
    recalc:
        trem = time;
        TMODULO(trem, tm_hour, cast(double) SECS_PER_HOUR);
        TMODULO(trem, tm_min, cast(double) SECS_PER_MINUTE);
        TMODULO(trem, tm_sec, 1.0);
        trem = TIMEROUND(trem);
        /* roundoff may need to propagate to higher-order fields */
        if (trem >= 1.0)
        {
            time = ceil(time);
            goto recalc;
        }

        return TimeOfDay(tm_hour, tm_min, tm_sec);
    }
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

    version(Have_Int64_TimeStamp)
    {
        time = dt;
        TMODULO(time, date, USECS_PER_DAY);

        if (time < 0)
        {
            time += USECS_PER_DAY;
            date -= 1;
        }

        j2date(cast(int) date, tm.tm_year, tm.tm_mon, tm.tm_mday);
        dt2time(time, tm.tm_hour, tm.tm_min, tm.tm_sec, fsec);
    } else
    {
        time = dt;
        TMODULO(time, date, cast(double) SECS_PER_DAY);

        if (time < 0)
        {
            time += SECS_PER_DAY;
            date -= 1;
        }

    recalc_d:
        j2date(cast(int) date, tm.tm_year, tm.tm_mon, tm.tm_mday);
    recalc_t:
        dt2time(time, tm.tm_hour, tm.tm_min, tm.tm_sec, fsec);

        fsec = TSROUND(fsec);
        /* roundoff may need to propagate to higher-order fields */
        if (fsec >= 1.0)
        {
            time = cast(Timestamp)ceil(time);
            if (time >= cast(double) SECS_PER_DAY)
            {
                time = 0;
                date += 1;
                goto recalc_d;
            }
            goto recalc_t;
        }
    }

    return 0;
}

void dt2time(Timestamp jd, out int hour, out int min, out int sec, out fsec_t fsec)
{
    TimeOffset  time;

    time = jd;
    version(Have_Int64_TimeStamp)
    {
        hour = cast(int)(time / USECS_PER_HOUR);
        time -= hour * USECS_PER_HOUR;
        min = cast(int)(time / USECS_PER_MINUTE);
        time -= min * USECS_PER_MINUTE;
        sec = cast(int)(time / USECS_PER_SEC);
        fsec = cast(int)(time - sec*USECS_PER_SEC);
    } else
    {
        hour = cast(int)(time / SECS_PER_HOUR);
        time -= hour * SECS_PER_HOUR;
        min = cast(int)(time / SECS_PER_MINUTE);
        time -= min * SECS_PER_MINUTE;
        sec = cast(int)time;
        fsec = cast(int)(time - sec);
    }
}
