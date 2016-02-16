/**
*   PostgreSQL numeric format
*
*   Copyright: © 2014 DSoftOut
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.types.numeric;

private pure // inner representation from libpq sources
{
    alias NumericDigit = ushort;
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
	int          dscale;
	ubyte[]      str;
	ubyte*       cp;
	ubyte*       endcp;
	int          i;
	int          d;
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

	str = new ubyte[i + dscale + DEC_DIGITS + 2];
	cp = str.ptr;

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

	return (cast(char*) str).fromStringz;
    }
}

import std.conv: to;
import std.string: fromStringz;
import std.bitmanip: bigEndianToNative;

package string rawValueToNumeric(in ubyte[] v)
{
    import dpq2.result: AnswerException, ExceptionType;

    struct NumericVar_net // network byte order
    {
	ubyte[2] num; // num of digits
        ubyte[2] weight;
        ubyte[2] sign;
        ubyte[2] dscale;
    }

    if(!(v.length >= NumericVar_net.sizeof))
        throw new AnswerException(ExceptionType.SIZE_MISMATCH,
            "Value length ("~to!string(v.length)~") less than it is possible for numeric type",
            __FILE__, __LINE__);

    NumericVar_net* h = cast(NumericVar_net*) v.ptr;

    NumericVar res;
    res.weight = bigEndianToNative!short(h.weight);
    res.sign   = bigEndianToNative!ushort(h.sign);
    res.dscale = bigEndianToNative!ushort(h.dscale);

    auto len = (v.length - NumericVar_net.sizeof) / NumericDigit.sizeof;

    res.digits = new NumericDigit[len];

    size_t offset = NumericVar_net.sizeof;
    foreach(i; 0 .. len)
    {
	res.digits[i] = bigEndianToNative!NumericDigit(
		(&(v[offset]))[0..NumericDigit.sizeof]
	    );
	offset += NumericDigit.sizeof;
    }

    return numeric_out(res);
}
