/**
*   PostgreSQL time types binary format.
*   
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.types.time;

import dpq2.answer;
import dpq2.oids;

import std.datetime;
import std.bitmanip: bigEndianToNative;
import std.math;
import core.stdc.time: time_t;

/// Returns value data as native Date
@property Date binaryValueAs(T)(in Value v)
if( is( T == Date ) )
{
    if(!(v.oidType == OidType.Date))
        throwTypeComplaint(v.oidType, "Date", __FILE__, __LINE__);

    if(!(v.value.length == uint.sizeof))
        throw new AnswerException(ExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres date type", __FILE__, __LINE__);

    int jd = bigEndianToNative!uint(v.value.ptr[0..uint.sizeof]);
    int year, month, day;
    j2date(jd, year, month, day);

    return Date(year, month, day);
}

/// Returns value time without time zone as native TimeOfDay
@property TimeOfDay binaryValueAs(T)(in Value v)
if( is( T == TimeOfDay ) )
{
    if(!(v.oidType == OidType.Time))
        throwTypeComplaint(v.oidType, "time without time zone", __FILE__, __LINE__);

    if(!(v.value.length == TimeADT.sizeof))
        throw new AnswerException(ExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres time without time zone type", __FILE__, __LINE__);

    return time2tm(bigEndianToNative!TimeADT(v.value.ptr[0..TimeADT.sizeof]));
}

/// Returns value timestamp without time zone as TimeStampWithoutTZ
@property TimeStampWithoutTZ binaryValueAs(T)(in Value v)
if( is( T == TimeStampWithoutTZ ) )
{
    if(!(v.oidType == OidType.TimeStamp))
        throwTypeComplaint(v.oidType, "timestamp without time zone", __FILE__, __LINE__);

    if(!(v.value.length == long.sizeof))
        throw new AnswerException(ExceptionType.SIZE_MISMATCH,
            "Value length isn't equal to Postgres timestamp without time zone type", __FILE__, __LINE__);

    return rawTimeStamp2nativeTime(bigEndianToNative!long(v.value.ptr[0..long.sizeof]));
}

struct TimeStampWithoutTZ
{
    DateTime dateTime;
    FracSec fracSec; /// fractional seconds

    static max()
    {
        return TimeStampWithoutTZ(DateTime.max, FracSec.from!"hnsecs"(long.max));
    }

    static min()
    {
        return TimeStampWithoutTZ(DateTime.min, FracSec.zero);
    }
}

private:

TimeStampWithoutTZ rawTimeStamp2nativeTime(long raw)
{
    version(Have_Int64_TimeStamp)
    {
        if(raw >= time_t.max) return TimeStampWithoutTZ.max;
        if(raw <= time_t.min) return TimeStampWithoutTZ.min;
    }

    pg_tm tm;
    fsec_t ts;

    if(timestamp2tm(raw, tm, ts) < 0)
        throw new AnswerException(
            ExceptionType.OUT_OF_RANGE, "Timestamp is out of range",
            __FILE__, __LINE__
        );

    return raw_pg_tm2nativeTime(tm, ts);
}

TimeStampWithoutTZ raw_pg_tm2nativeTime(pg_tm tm, fsec_t ts)
{
    TimeStampWithoutTZ res;

    res.dateTime = DateTime(
            tm.tm_year,
            tm.tm_mon,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        );

    version(Have_Int64_TimeStamp)
    {
        res.fracSec = FracSec.from!"usecs"(ts);
    }
    else
    {
        res.fracSec = FracSec.from!"usecs"((cast(long)(ts * 10e6)));
    }

    return res;
}

pure:

// Here is used names from the original Postgresql source

void j2date(int jd, out int year, out int month, out int day)
{
    enum POSTGRES_EPOCH_JDATE = 2451545;
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
    private alias double Timestamp;
    private alias double TimestampTz;
    private alias double TimeADT;
    private alias double TimeOffset;
    private alias double fsec_t;    /* fractional seconds (in seconds) */
    
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

alias long pg_time_t;

immutable ulong SECS_PER_DAY = 86400;
immutable ulong POSTGRES_EPOCH_JDATE = 2451545;
immutable ulong UNIX_EPOCH_JDATE     = 2440588;

immutable ulong USECS_PER_DAY    = 86_400_000_000;
immutable ulong USECS_PER_HOUR   = 3_600_000_000;
immutable ulong USECS_PER_MINUTE = 60_000_000;
immutable ulong USECS_PER_SEC    = 1_000_000;

immutable ulong SECS_PER_HOUR   = 3600;
immutable ulong SECS_PER_MINUTE = 60;

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
