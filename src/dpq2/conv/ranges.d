module dpq2.conv.ranges;


import dpq2.conv.time : TimeStamp, TimeStampUTC;
import dpq2.conv.to_d_types;
import dpq2.oids : OidType;
import dpq2.value;

import std.bitmanip : bigEndianToNative;
import std.conv : to;
import std.datetime.date : Date;
import std.exception : enforce;
import std.traits : TemplateOf;


enum PG_RANGE : ubyte {
	/* A range's flags byte contains these bits: */
	EMPTY			= 0x01,			/* range is empty */
	LB_INC			= 0x02,			/* lower bound is inclusive */
	UB_INC			= 0x04,			/* upper bound is inclusive */
	LB_INF			= 0x08,			/* lower bound is -infinity */
	UB_INF			= 0x10,			/* upper bound is +infinity */
	LB_NULL			= 0x20,			/* lower bound is null (NOT USED) */
	UB_NULL			= 0x40,			/* upper bound is null (NOT USED) */
	CONTAIN_EMPTY	= 0x80			/* marks a GiST internal-page entry whose
									 * subtree contains some empty ranges */
}

template isRangeType(T, OidType O) {
	static if (is(T == int)) enum isRangeType = O == OidType.Int4;
	static if (is(T == long)) enum isRangeType = O == OidType.Int8;
	static if (is(T == string)) enum isRangeType = O == OidType.Numeric;
	static if (is(T == TimeStamp)) enum isRangeType = O == OidType.TimeStamp;
	static if (is(T == TimeStampUTC)) enum isRangeType = O == OidType.TimeStampWithZone;
	static if (is(T == Date)) enum isRangeType = O == OidType.Date;
}

template isMultiRange(R) {
	enum isMultiRange = __traits(isSame, TemplateOf!R, MultiRange);
}


struct Range(T, OidType O, size_t CheckSize = T.sizeof)
if (isRangeType!(T,O))
{
	ubyte flags;
	T[2] data;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= 1, "cannot construct range with insufficient data");

		this._data = binaryData;

		this.flags = binaryData[0];
		binaryData = binaryData[1..$];

		if (!isEmpty) {
			if (CheckSize)
				assert(binaryData.length ==
					(isLowerInf || isLowerNull ? 0 : 1)*(uint.sizeof + CheckSize) +
					(isUpperInf || isUpperNull ? 0 : 1)*(uint.sizeof + CheckSize),
					"size of binary data does not match: " ~ _data.to!string ~ ", check size = " ~ CheckSize.to!string ~
					", binaryData.length = " ~ binaryData.length.to!string ~ ", condition = " ~
						isLowerInf.to!string ~ "/" ~ isLowerNull.to!string ~ "/" ~
						isUpperInf.to!string ~ "/" ~ isUpperNull.to!string
				);

			if (!isLowerInf && !isLowerNull) {
				auto size = binaryData[0..uint.sizeof].bigEndianToNative!uint;
				if (CheckSize) assert(size == CheckSize, "unexpected lower bound size");
				binaryData = binaryData[uint.sizeof..$];
				this.data[0] = Value(binaryData[0..size].idup, O).as!T;
				binaryData = binaryData[size..$];
			}

			if (!isUpperInf && !isUpperNull) {
				auto size = binaryData[0..uint.sizeof].bigEndianToNative!uint;
				if (CheckSize) assert(size == CheckSize, "unexpected upper bound size");
				binaryData = binaryData[uint.sizeof..$];
				this.data[1] = Value(binaryData[0..size], O).as!T;
			}
		}
	}

	bool isEmpty() @property { return (flags & PG_RANGE.EMPTY) == PG_RANGE.EMPTY; }
	bool isLowerInc() @property { return (flags & PG_RANGE.LB_INC) == PG_RANGE.LB_INC; }
	bool isUpperInc() @property { return (flags & PG_RANGE.UB_INC) == PG_RANGE.UB_INC; }
	bool isLowerInf() @property { return (flags & PG_RANGE.LB_INF) == PG_RANGE.LB_INF; }
	bool isUpperInf() @property { return (flags & PG_RANGE.UB_INF) == PG_RANGE.UB_INF; }
	bool isLowerNull() @property { return (flags & PG_RANGE.LB_NULL) == PG_RANGE.LB_NULL; }
	bool isUpperNull() @property { return (flags & PG_RANGE.UB_NULL) == PG_RANGE.UB_NULL; }

	T lower() { return data[0]; }
	T upper() { return data[1]; }

	auto rawData() @property { return _data.dup; }
	static auto elementOidType() @property { return O; }
}

struct MultiRange(R)
if (__traits(isSame, TemplateOf!R, Range))
{
	R[] data;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= uint.sizeof, "cannot construct multirange with insufficient data");

		this._data = binaryData;
		binaryData = binaryData[uint.sizeof..$];

		for (uint i = 0; i < this.length; i++) {
			auto size = binaryData[0..uint.sizeof].bigEndianToNative!uint;
			binaryData = binaryData[uint.sizeof..$];
			data ~= R(binaryData[0..size]);
			binaryData = binaryData[size..$];
		}
	}

	size_t length() @property { return _data.length ? _data[0..uint.sizeof].bigEndianToNative!uint : 0; }

	R opIndex(size_t idx) {
		enforce(idx < this.length, "multirange index out of bounds: " ~ this.length.to!string ~ "/" ~ idx.to!string);
		return data[idx];
	}

	int opApply(scope int delegate(size_t, ref R) dg)
	{
		foreach (i, val; data) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}

	int opApplyReverse(scope int delegate(size_t, ref R) dg)
	{
		foreach_reverse (i, val; data) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}
}

alias Range!(int, OidType.Int4) Int4Range;
alias Range!(long, OidType.Int8) Int8Range;
alias Range!(string, OidType.Numeric, 0) NumRange;
alias Range!(TimeStamp, OidType.TimeStamp, 8) TsRange;
alias Range!(TimeStampUTC, OidType.TimeStampWithZone, 8) TsTzRange;
alias Range!(Date, OidType.Date) DateRange;

alias MultiRange!Int4Range Int4MultiRange;
alias MultiRange!Int8Range Int8MultiRange;
alias MultiRange!NumRange NumMultiRange;
alias MultiRange!TsRange TsMultiRange;
alias MultiRange!TsTzRange TsTzMultiRange;
alias MultiRange!DateRange DateMultiRange;

package:

/// Convert Value to native range type
R binaryValueAs(R)(in Value v) @trusted
if (__traits(isSame, TemplateOf!R, Range))
{
	return R(v.data);
}

/// Convert Value to native multirange type
M binaryValueAs(M)(in Value v) @trusted
if (__traits(isSame, TemplateOf!M, MultiRange))
{
	return M(v.data);
}
