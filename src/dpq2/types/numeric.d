/**
*   PostgreSQL numeric format
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.types.numeric;

import dpq2.answer;
import dpq2.oids;

import core.memory;
import std.conv: to;
import std.string: fromStringz;

private // inner representation from libpq sources
{
    alias ushort NumericDigit;
    enum DEC_DIGITS = 4;
    enum NUMERIC_NEG       = 0x4000;
    enum NUMERIC_NAN       = 0xC000;

    struct NumericVar
    {
        int weight;
        int sign;
        int dscale;
        NumericDigit[] digits;
    }

    string numeric_out(in NumericVar num)
    {
        string str;

        if(num.sign == NUMERIC_NAN)
        {
	    return "NaN";
        }

        str = get_str_from_var(num);

        return str;
    }

    /*
     * get_str_from_var() -
     *
     *  Convert a var to text representation (guts of numeric_out).
     *  The var is displayed to the number of digits indicated by its dscale.
     *  Returns a palloc'd string.
     */
    string get_str_from_var(in NumericVar var)
    {
	int         dscale;
	char*       str;
	char*       cp;
	char*       endcp;
	int         i;
	int         d;
	NumericDigit dig;

	static if(DEC_DIGITS > 1)
	{
		NumericDigit d1;
	}

	dscale = var.dscale;

	/*
	 * Allocate space for the result.
	 *
	 * i is set to the # of decimal digits before decimal point. dscale is the
	 * # of decimal digits we will print after decimal point. We may generate
	 * as many as DEC_DIGITS-1 excess digits at the end, and in addition we
	 * need room for sign, decimal point, null terminator.
	 */
	i = (var.weight + 1) * DEC_DIGITS;
	if (i <= 0)
	    i = 1;

	str = cast(char*)GC.malloc(i + dscale + DEC_DIGITS + 2);
	cp = str;

	/*
	 * Output a dash for negative values
	 */
	if (var.sign == NUMERIC_NEG)
	    *cp++ = '-';

	/*
	 * Output all digits before the decimal point
	 */
	if (var.weight < 0)
	{
	    d = var.weight + 1;
	    *cp++ = '0';
	}
	else
	{
	    for (d = 0; d <= var.weight; d++)
	    {
		dig = (d < var.digits.length) ? var.digits[d] : 0;
		/* In the first digit, suppress extra leading decimal zeroes */
		static if(DEC_DIGITS == 4)
		{
		    bool putit = (d > 0);

		    d1 = dig / 1000;
		    dig -= d1 * 1000;
		    putit |= (d1 > 0);
		    if (putit)
			*cp++ = cast(char)(d1 + '0');
		    d1 = dig / 100;
		    dig -= d1 * 100;
		    putit |= (d1 > 0);
		    if (putit)
			*cp++ = cast(char)(d1 + '0');
		    d1 = dig / 10;
		    dig -= d1 * 10;
		    putit |= (d1 > 0);
		    if (putit)
			*cp++ = cast(char)(d1 + '0');
		    *cp++ = cast(char)(dig + '0');
		}
		else static if(DEC_DIGITS == 2)
		{
			d1 = dig / 10;
			dig -= d1 * 10;
			if (d1 > 0 || d > 0)
			    *cp++ = cast(char)(d1 + '0');
			*cp++ = cast(char)(dig + '0');
		}
		else static if(DEC_DIGITS == 1)
		{
		    *cp++ = cast(char)(dig + '0');
		}
		else pragma(error, "unsupported NBASE");
	    }
	}

	/*
	 * If requested, output a decimal point and all the digits that follow it.
	 * We initially put out a multiple of DEC_DIGITS digits, then truncate if
	 * needed.
	 */
	if (dscale > 0)
	{
	    *cp++ = '.';
	    endcp = cp + dscale;
	    for (i = 0; i < dscale; d++, i += DEC_DIGITS)
	    {
		dig = (d >= 0 && d < var.digits.length) ? var.digits[d] : 0;
		static if(DEC_DIGITS == 4)
		{
			d1 = dig / 1000;
			dig -= d1 * 1000;
			*cp++ = cast(char)(d1 + '0');
			d1 = dig / 100;
			dig -= d1 * 100;
			*cp++ = cast(char)(d1 + '0');
			d1 = dig / 10;
			dig -= d1 * 10;
			*cp++ = cast(char)(d1 + '0');
			*cp++ = cast(char)(dig + '0');
		}
		else static if(DEC_DIGITS == 2)
		{
			d1 = dig / 10;
			dig -= d1 * 10;
			*cp++ = cast(char)(d1 + '0');
			*cp++ = cast(char)(dig + '0');
		}
		else static if(DEC_DIGITS == 1)
		{
		    *cp++ = cast(char)(dig + '0');
	    }
	    else pragma(error, "unsupported NBASE");
	    }
	    cp = endcp;
	}

	/*
	 * terminate the string and return it
	 */
	*cp = '\0';
	return str.fromStringz.idup;
    }
}

struct PGNumeric
{
    string payload;

    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink(payload);
    }

    static PGNumeric fromString(string src)
    {
        return PGNumeric(src);
    }
}

PGNumeric convert(OidType type)(ubyte[] val)
if(type == PQType.Numeric)
{
    assert(val.length >= 4*ushort.sizeof);

    NumericVar      value;
    val.read!ushort; // num of digits
    value.weight = val.read!short;
    value.sign = val.read!ushort;
    value.dscale = val.read!ushort;

    auto len = val.length / NumericDigit.sizeof;
    value.digits = new NumericDigit[len];
    foreach(i; 0 .. len)
    {
	    NumericDigit d = val.read!NumericDigit;
	    value.digits[i] = d;
    }

    return PGNumeric(numeric_out(value));
}

package string rawValueToNumeric(in Value v)
{
    return "not implemented";
}

version(IntegrationTest2)
{
    import pgator.db.pool;
    import std.random;
    import std.range;
    import std.math;
    import vibe.data.bson;
    import derelict.pq.pq;
    import dlogg.log;
    import dlogg.buffered;

    void test(PQType type)(shared ILogger strictLogger, shared IConnectionPool pool)
        if(type == PQType.Numeric)
    {
                auto delayed = new shared BufferedLogger(strictLogger);
                scope(exit) delayed.finalize();
                scope(failure) delayed.minOutputLevel = LoggingLevel.Notice;

        void testValue(shared ILogger logger, string val)
        {
            string query;
            if(val == "NaN")
            {
                query = "SELECT '"~val~"'::NUMERIC as test_field";
            } else
            {
                query = "SELECT "~val~"::NUMERIC as test_field";
            }

            logger.logInfo(query);
            auto res = Bson.fromJson(pool.execTransaction([query]).front.toJson);

            logger.logInfo(text(res));
            auto node = res.get!(Bson[string])["test_field"][0];
            if(node.type == Bson.Type.double_)
            {
                auto remote = node.get!double;
                auto local  = val.to!double;
                if(!isNaN(local))
                    assert(remote == local, remote.to!string ~ "!=" ~ val);
                else
                    assert(isNaN(remote), remote.to!string ~ " is not NaN!");
            } else
            {
                auto retval = node.get!string;
                assert(retval == val, retval ~ "!=" ~ val);
            }
        }

        string bigNumber(size_t size)
        {
            auto builder = appender!string;
            immutable digits = "0123456789";
            foreach(i; 0..size)
                builder.put(digits[uniform(0, digits.length)]);
            return builder.data.strip('0');
        }

        strictLogger.logInfo("Testing Numeric...");
        foreach(i; 0..100)
        {
            testValue(delayed, (100*uniform(-1.0, 1.0)).to!string);
        }
        // big numbers
        foreach(i; 0..100)
        {
            testValue(delayed, bigNumber(100) ~ "." ~ bigNumber(100));
        }
        // special cases
        testValue(delayed, "0");
        testValue(delayed, "0.0146328");
        testValue(delayed, "42");
        testValue(delayed, "NaN");
        testValue(delayed, "0.0007");
        testValue(delayed, "0.007");
        testValue(delayed, "0.07");
        testValue(delayed, "0.7");
        testValue(delayed, "7");
        testValue(delayed, "70");
        testValue(delayed, "700");
        testValue(delayed, "7000");
        testValue(delayed, "70000");

        testValue(delayed, "7.0");
        testValue(delayed, "70.0");
        testValue(delayed, "700.0");
        testValue(delayed, "7000.0");
        testValue(delayed, "70000.000");

        testValue(delayed, "2354877787627192443");
        testValue(delayed, "2354877787627192443.0");
        testValue(delayed, "2354877787627192443.00000");
    }
}
