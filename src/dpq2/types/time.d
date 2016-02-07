/**
*   PostgreSQL time types binary format.
*   
*   There are following supported libpq formats:
*   <ul>
*   <li>$(B date) - handles year, month, day. Corresponding D type - $(B std.datetime.Date).</li>
*   <li>$(B abstime) - unix time in seconds without timezone. Corresponding D type - $(B PGAbsTime) 
*        wrapper around $(B std.datetime.SysTime).</li>
*   <li>$(B reltime) - seconds count positive or negative for representation of time durations.
*        Corresponding D type - $(B PGRelTime) wrapper around $(B core.time.Duration). Note that
*        D's duration holds hnsecs count, but reltime precise at least seconds.</li>
*   <li>$(B time) - day time without time zone. Corresponding D type - $(B PGTime) wrapper around
*        $(B std.datetime.TimeOfDay).</li>
*   <li>$(B time with zone) - day time with time zone. Corresponding D type - $(B PGTimeWithZone)
*        structure that can be casted to $(B std.datetime.TimeOfDay) and $(B std.datetime.SimpleTimeZone).</li>
*   <li>$(B interval) - time duration (modern replacement for $(B reltime)). Corresponding D time - 
*        $(B TimeInterval) that handles microsecond, day and month counts.</li>
*   <li>$(B tinterval) - interval between two points in time. Consists of two abstime values: begin and end.
*        Correponding D type - $(B PGInterval) wrapper around $(B std.datetime.Interval).</li>
*   </ul>
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

pure:
package:

Date rawValueToDate(in ubyte[] val)
{
    assert(val.length == uint.sizeof);

    uint jd = bigEndianToNative!uint(val.ptr[0..uint.sizeof]);

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
    int year = (y+ quad * 4) - 4800;
    quad = julian * 2141 / 65536;
    int day = julian - 7834 * quad / 256;
    int month = (quad + 10) % MONTHS_PER_YEAR + 1;

    return Date(year, month, day);
}

import std.math;

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

TimeOfDay rawValueToTimeOfDay(in ubyte[] val)
{
    TimeADT time = bigEndianToNative!TimeADT(val.ptr[0..TimeADT.sizeof]);

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

/+
import core.stdc.time;
import std.bitmanip;
import vibe.data.bson;
import std.math;

/**
*   Represents PostgreSQL Time with TimeZone.
*   Time zone is stored as UTC offset in seconds without DST.
*/
struct PGTimeWithZone
{
    int hour, minute, second, timeZoneOffset;
    
    this(TimeOfDay tm, const SimpleTimeZone tz) pure
    {
        hour = tm.hour;
        minute = tm.minute;
        second = tm.second;
        
        static if (__VERSION__ < 2066) {
        	timeZoneOffset = cast(int)tz.utcOffset.dur!"minutes".total!"seconds";
    	} else {
    		timeZoneOffset = cast(int)tz.utcOffset.total!"seconds";
    	}
    }
    
    T opCast(T)() const if(is(T == TimeOfDay))
    {
        return TimeOfDay(hour, minute, second);
    }
    
    T opCast(T)() const if(is(T == immutable SimpleTimeZone))
    {
        return new immutable SimpleTimeZone(dur!"seconds"(timeZoneOffset));
    }
}

PGTimeWithZone convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeWithZone)
{
    assert(val.length == 12);
    return PGTimeWithZone(time2tm(val.read!TimeADT), new immutable SimpleTimeZone(-val.read!int.dur!"seconds"));
}

/**
*   PostgreSQL time interval isn't same with D std.datetime one.
*   It is simple Duration.
*
*   Consists of: microseconds $(B time), $(B day) count and $(B month) count.
*   Libpq uses different represantation for $(B time), but i store only 
*   in usecs format.
*/
struct TimeInterval
{
    // in microseconds
    long        time;           /* all time units other than days, months and
                                 * years */
    int         day;            /* days, after time for alignment */
    int         month;          /* months and years, after time for alignment */
    
    this(ubyte[] arr)
    {
        assert(arr.length == TimeOffset.sizeof + 2*int.sizeof);
        version(Have_Int64_TimeStamp)
        {
            time  = arr.read!long;
        }
        else
        {
            time  = cast(long)(arr.read!double * 10e6);
        }
        
        day   = arr.read!int;
        month = arr.read!int;
    }
}

TimeInterval convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeInterval)
{
    return TimeInterval(val);
}

/**
*   Wrapper around std.datetime.Interval to handle [de]serializing
*   acceptable for JSON-RPC and still conform with libpq format.
*
*   Note: libpq representation of abstime slightly different from
*   std.datetime, thats why time converted to string could differ
*   a lot for PostgreSQL and SysTime (about 9000-15000 seconds nonconstant 
*   offset). 
*/
struct PGInterval
{
    private Interval!SysTime interval;
    alias interval this;

    this(Interval!SysTime val)
    {
    	interval = val;
    }
    
    static PGInterval fromBson(Bson bson)
    {
        auto begin = SysTime.fromISOExtString(bson.begin.get!string);
        auto end   = SysTime.fromISOExtString(bson.end.get!string);
        return PGInterval(Interval!SysTime(begin, end));
    }
    
    Bson toBson() const
    {
        Bson[string] map;
        map["begin"] = Bson(interval.begin.toISOExtString);
        map["end"]   = Bson(interval.end.toISOExtString);
        return Bson(map);
    }
}

/// Avoiding linking problems when std.datetime.Interval invariant isn't generated
/// by dmd. See at: std.datetime.Interval:18404
private debug extern(C) void _D3std8datetime36__T8IntervalTS3std8datetime7SysTimeZ8Interval11__invariantMxFNaZv()
{
	
}

PGInterval convert(PQType type)(ubyte[] val)
    if(type == PQType.Interval)
{
    assert(val.length == 3*int.sizeof);
    auto state = val.read!int;
    auto beg = SysTime(unixTimeToStdTime(val.read!int), UTC());
    auto end = SysTime(unixTimeToStdTime(val.read!int), UTC());

    return PGInterval(Interval!SysTime(beg, end));
}
 
private
{
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
    struct pg_tz;
    
    immutable ulong SECS_PER_DAY = 86400;
    immutable ulong POSTGRES_EPOCH_JDATE = 2451545;
    immutable ulong UNIX_EPOCH_JDATE     = 2440588;
    
    immutable ulong USECS_PER_DAY    = 86_400_000_000;
    immutable ulong USECS_PER_HOUR   = 3_600_000_000;
    immutable ulong USECS_PER_MINUTE = 60_000_000;
    immutable ulong USECS_PER_SEC    = 1_000_000;
    
    immutable ulong SECS_PER_HOUR   = 3600;
    immutable ulong SECS_PER_MINUTE = 60;
    
    /*
     *  Round off to MAX_TIMESTAMP_PRECISION decimal places.
     *  Note: this is also used for rounding off intervals.
     */
    enum TS_PREC_INV = 1000000.0;
    fsec_t TSROUND(fsec_t j)
    {
        return cast(fsec_t)(rint((cast(double) (j)) * TS_PREC_INV) / TS_PREC_INV);
    }
}

 /*
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
private int timestamp2tm(Timestamp dt, out pg_tm tm, out fsec_t fsec)
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

private void dt2time(Timestamp jd, out int hour, out int min, out int sec, out fsec_t fsec)
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

/**
*   Wrapper around std.datetime.SysTime to handle [de]serializing of libpq
*   timestamps (without time zone).
*
*   Note: libpq has two compile configuration with HAS_INT64_TIMESTAMP and
*   without (double timestamp format). The pgator should be compiled with
*   conform flag to operate properly. 
*/
struct PGTimeStamp
{
    private SysTime time;
    alias time this;
    
    this(SysTime time)
    {
        this.time = time;
    }
    
    this(pg_tm tm, fsec_t ts)
    {
        time = SysTime(Date(tm.tm_year, tm.tm_mon, tm.tm_mday), UTC());
        time += (tm.tm_hour % 24).dur!"hours";
        time += (tm.tm_min % 60).dur!"minutes";
        time += (tm.tm_sec  % 60).dur!"seconds";
        version(Have_Int64_TimeStamp)
        {
            time += ts.dur!"usecs";
        } else
        {
            time += (cast(long)(ts*10e6)).dur!"usecs";
        }
    }
    
    static PGTimeStamp fromBson(Bson bson)
    {
        auto val = SysTime.fromISOExtString(bson.get!string);
        return PGTimeStamp(val);
    }
    
    Bson toBson() const
    {
        return Bson(time.toISOExtString);
    }
}

PGTimeStamp convert(PQType type)(ubyte[] val)
    if(type == PQType.TimeStamp)
{
    auto raw = val.read!long;
    
    version(Have_Int64_TimeStamp)
    {
        if(raw >= time_t.max)
        {
            return PGTimeStamp(SysTime.max);
        }
        if(raw <= time_t.min)
        {
            return PGTimeStamp(SysTime.min);
        }
    }
    
    pg_tm tm;
    fsec_t ts;
    
    if(timestamp2tm(raw, tm, ts) < 0)
        throw new Exception("Timestamp is out of range!");

    return PGTimeStamp(tm, ts);
}

/**
*   Wrapper around std.datetime.SysTime to handle [de]serializing of libpq
*   time stamps with time zone.
*
*   Timezone is acquired from PQparameterStatus call for TimeZone parameter.
*   Database server doesn't send any info about time zone to client, the
*   time zone is important only while showing time to an user.
*
*   Note: libpq has two compile configuration with HAS_INT64_TIMESTAMP and
*   without (double time stamp format). The pgator should be compiled with
*   conform flag to operate properly. 
*/
struct PGTimeStampWithZone
{
    private SysTime time;
    alias time this;
    
    this(SysTime time)
    {
        this.time = time;
    }
    
    this(pg_tm tm, fsec_t ts, immutable TimeZone zone)
    {    
        time = SysTime(Date(tm.tm_year, tm.tm_mon, tm.tm_mday), UTC());
        time.timezone = zone;
        time += tm.tm_hour.dur!"hours";
        time += tm.tm_min.dur!"minutes";
        time += tm.tm_sec.dur!"seconds";
        version(Have_Int64_TimeStamp)
        {
            time += ts.dur!"usecs";
        } else
        {
            time += (cast(long)(ts*10e6)).dur!"usecs";
        }
    }
    
    static PGTimeStampWithZone fromBson(Bson bson)
    {
        auto val = SysTime.fromISOExtString(bson.get!string);
        return PGTimeStampWithZone(val);
    }
    
    Bson toBson() const
    {
        return Bson(time.toISOExtString);
    }
}

PGTimeStampWithZone convert(PQType type)(ubyte[] val, shared IConnection conn)
    if(type == PQType.TimeStampWithZone)
{
    auto raw = val.read!long;
    
    version(Have_Int64_TimeStamp)
    {
        if(raw >= time_t.max)
        {
            return PGTimeStampWithZone(SysTime.max);
        }
        if(raw <= time_t.min)
        {
            return PGTimeStampWithZone(SysTime.min);
        }
    }
    
    pg_tm tm;
    fsec_t ts;
    
    if(timestamp2tm(raw, tm, ts) < 0)
        throw new Exception("Timestamp is out of range!");

    return PGTimeStampWithZone(tm, ts, conn.timeZone);
}


version(IntegrationTest2)
{
    import pgator.db.pq.types.test;
    import pgator.db.pool;
    import std.random;
    import std.algorithm;
    import std.encoding;
    import dlogg.log;
    import dlogg.buffered;
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Date)
    {
        strictLogger.logInfo("Testing Date...");
        auto dformat = pool.dateFormat;
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        assert(queryValue(logger, pool, "'1999-01-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'January 8, 1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'1999-Jan-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'Jan-08-1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'08-Jan-1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'19990108'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'990108'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'1999.008'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'J2451187'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        assert(queryValue(logger, pool, "'January 8, 99 BC'::date").deserializeBson!Date.toISOExtString == "-0098-01-08");
           
        if(dformat.orderFormat == DateFormat.OrderFormat.MDY)
        {
            assert(queryValue(logger, pool, "'1/8/1999'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'1/18/1999'::date").deserializeBson!Date.toISOExtString == "1999-01-18");
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2003-01-02");
            assert(queryValue(logger, pool, "'08-Jan-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'Jan-08-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        } 
        else if(dformat.orderFormat == DateFormat.OrderFormat.DMY)
        {
            assert(queryValue(logger, pool, "'1/8/1999'::date").deserializeBson!Date.toISOExtString == "1999-08-01");
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2003-02-01");
            assert(queryValue(logger, pool, "'08-Jan-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
            assert(queryValue(logger, pool, "'Jan-08-99'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        }
        else if(dformat.orderFormat == DateFormat.OrderFormat.YMD)
        {
            assert(queryValue(logger, pool, "'01/02/03'::date").deserializeBson!Date.toISOExtString == "2001-02-03");
            assert(queryValue(logger, pool, "'99-Jan-08'::date").deserializeBson!Date.toISOExtString == "1999-01-08");
        }

    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.AbsTime)
    {
        strictLogger.logInfo("Testing AbsTime...");
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'Dec 20 20:45:53 1986 GMT'::abstime").deserializeBson!PGAbsTime;
        assert(res.time == SysTime.fromSimpleString("1986-Dec-20 20:45:53Z"));
        
        res = queryValue(logger, pool, "'Mar 8 03:14:04 2014 GMT'::abstime").deserializeBson!PGAbsTime;
        assert(res.time == SysTime.fromSimpleString("2014-Mar-08 03:14:04Z"));
        
        res = queryValue(logger, pool, "'Dec 20 20:45:53 1986 +3'::abstime").deserializeBson!PGAbsTime;
        assert(res.time == SysTime.fromSimpleString("1986-Dec-20 20:45:53+03"));
        
        res = queryValue(logger, pool, "'Mar 8 03:14:04 2014 +3'::abstime").deserializeBson!PGAbsTime;
        assert(res.time == SysTime.fromSimpleString("2014-Mar-08 03:14:04+03"));
        
    }
     
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.RelTime)
    {
        strictLogger.logInfo("Testing RelTime...");
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'2 week 3 day 4 hour 5 minute 6 second'::reltime").deserializeBson!PGRelTime;
        assert(res == 6.dur!"seconds" + 5.dur!"minutes" + 4.dur!"hours" + 3.dur!"days" + 2.dur!"weeks");
        
        res = queryValue(logger, pool, "'2 week 3 day 4 hour 5 minute 6 second ago'::reltime").deserializeBson!PGRelTime;
        assert(res == (-6).dur!"seconds" + (-5).dur!"minutes" + (-4).dur!"hours" + (-3).dur!"days" + (-2).dur!"weeks");
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Time)
    {
        strictLogger.logInfo("Testing Time...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Server timestamp format is: ", pool.timestampFormat));
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }

        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05:06.789'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05:06'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05'::time").deserializeBson!PGTime).toISOExtString == "04:05:00");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'040506'::time").deserializeBson!PGTime).toISOExtString == "04:05:06");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05 AM'::time").deserializeBson!PGTime).toISOExtString == "04:05:00");
        assert((cast(TimeOfDay)queryValue(logger, pool, "'04:05 PM'::time").deserializeBson!PGTime).toISOExtString == "16:05:00");
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeWithZone)
    {
        strictLogger.logInfo("Testing TimeWithZone...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Server timestamp format is: ", pool.timestampFormat));
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        static if (__VERSION__ < 2066) 
        {
            auto res = queryValue(logger, pool, "'04:05:06.789-8'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05:06-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:00" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
            res = queryValue(logger, pool, "'040506-08'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05:06 PST'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -8);
            res = queryValue(logger, pool, "'2003-04-12 04:05:06 America/New_York'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.dur!"minutes".total!"hours" == -4);
        } else
        {
            auto res = queryValue(logger, pool, "'04:05:06.789-8'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05:06-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05-08:00'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:00" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -8);
            res = queryValue(logger, pool, "'040506-08'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -8);
            res = queryValue(logger, pool, "'04:05:06 PST'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -8);
            res = queryValue(logger, pool, "'2003-04-12 04:05:06 America/New_York'::time with time zone").deserializeBson!PGTimeWithZone;
            assert((cast(TimeOfDay)res).toISOExtString == "04:05:06" && (cast(immutable SimpleTimeZone)res).utcOffset.total!"hours" == -4);
        }
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Interval)
    {
        strictLogger.logInfo("Testing tinterval...");
                
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'[\"Dec 20 20:45:53 1986 GMT\" \"Mar 8 03:14:04 2014 GMT\"]'::tinterval").deserializeBson!PGInterval;
        assert(res.begin == SysTime.fromSimpleString("1986-Dec-20 20:45:53Z"));
        assert(res.end   == SysTime.fromSimpleString("2014-Mar-08 03:14:04Z"));
        
        res = queryValue(logger, pool, "'[\"Dec 20 20:45:53 1986 +3\" \"Mar 8 03:14:04 2014 +3\"]'::tinterval").deserializeBson!PGInterval;
        assert(res.begin == SysTime.fromSimpleString("1986-Dec-20 20:45:53+03"));
        assert(res.end   == SysTime.fromSimpleString("2014-Mar-08 03:14:04+03"));

    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeInterval)
    {
        strictLogger.logInfo("Testing TimeInterval...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Server timestamp format is: ", pool.timestampFormat));
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "'1-2'::interval").deserializeBson!TimeInterval;
        assert(res.time == 0 && res.day == 0 && res.month == 14);
        
        res = queryValue(logger, pool, "'3 4:05:06'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 0);
        
        res = queryValue(logger, pool, "'1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
        
        res = queryValue(logger, pool, "'P1Y2M3DT4H5M6S'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
        
        res = queryValue(logger, pool, "'P0001-02-03T04:05:06'::interval").deserializeBson!TimeInterval;
        assert(res.time.dur!"usecs" == 4.dur!"hours" + 5.dur!"minutes" + 6.dur!"seconds" && res.day == 3 && res.month == 14);
    }
    
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeStamp)
    {
        strictLogger.logInfo("Testing TimeStamp...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Server timestamp format is: ", pool.timestampFormat));
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "TIMESTAMP '2004-10-19 10:23:54'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.fromSimpleString("2004-Oct-19 10:23:54Z"));
        
        res = queryValue(logger, pool, "TIMESTAMP '1999-01-08 04:05:06'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.fromSimpleString("1999-Jan-08 04:05:06Z"));
        
        res = queryValue(logger, pool, "TIMESTAMP 'January 8 04:05:06 1999 PST'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.fromSimpleString("1999-Jan-08 04:05:06Z"));
        
        res = queryValue(logger, pool, "TIMESTAMP 'epoch'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.fromSimpleString("1970-Jan-01 00:00:00Z"));
        
        res = queryValue(logger, pool, "TIMESTAMP 'infinity'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.max);
        
        res = queryValue(logger, pool, "TIMESTAMP '-infinity'").deserializeBson!PGTimeStamp;
        assert(res.time == SysTime.min);
    }
     
    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.TimeStampWithZone)
    {
        strictLogger.logInfo("Testing TimeStampWithZone...");
        scope(failure) 
        {
            version(Have_Int64_TimeStamp) string s = "with Have_Int64_TimeStamp";
            else string s = "without Have_Int64_TimeStamp";
            
            strictLogger.logInfo("============================================");
            strictLogger.logInfo(text("Server timestamp format is: ", pool.timestampFormat));
            strictLogger.logInfo(text("Application was compiled ", s, ". Try to switch the compilation flag."));
            strictLogger.logInfo("============================================");
        }
        
        auto logger = new shared BufferedLogger(strictLogger);
        scope(failure) logger.minOutputLevel = LoggingLevel.Notice;
        scope(exit) logger.finalize;
        
        auto res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE '2004-10-19 10:23:54+02'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.fromSimpleString("2004-Oct-19 10:23:54+02"));
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE '1999-01-08 04:05:06-04'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.fromSimpleString("1999-Jan-08 04:05:06-04"));
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE 'January 8 04:05:06 1999 -8:00'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.fromSimpleString("1999-Jan-08 04:05:06-08"));
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE 'epoch'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.fromSimpleString("1970-Jan-01 00:00:00Z"));
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE 'infinity'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.max);
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE '-infinity'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.min);
        
        res = queryValue(logger, pool, "TIMESTAMP WITH TIME ZONE '2014-11-20 15:47:25+07'").deserializeBson!PGTimeStampWithZone;
        assert(res.time == SysTime.fromSimpleString("2014-Nov-20 15:47:25+07"));
    }
}
+/
