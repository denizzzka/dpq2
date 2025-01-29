module dpq2.conv.bit;

import dpq2.conv.to_d_types;
import dpq2.oids : OidType;
import dpq2.value;

import std.bitmanip : bigEndianToNative;
import std.conv : to;
import std.exception : enforce;
import std.traits : hasMember;


template isBitString(T) {
	enum isBitString = hasMember!(T, "bits") && __traits(compiles, typeof(T.bits));
}

struct BitString {
	uint stringLen;
	ubyte[] bits;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= uint.sizeof, "cannot construct bit string with insufficient data");

		this._data = binaryData;

		this.stringLen = binaryData[0..uint.sizeof].bigEndianToNative!uint;
		assert(this.stringLen, "zero bit string length?");

		binaryData = binaryData[uint.sizeof..$];
		assert(binaryData.length >= this.byteLen, "data shorter than bit string length");

		this.bits = binaryData[0..this.byteLen].dup;
	}

	auto byteLen() @property { return (this.stringLen + 7) / 8; }

	auto rawData() @property { return _data.dup; }
}

package:

/// Convert Value to native network address type
N binaryValueAs(N)(in Value v) @trusted
if (isBitString!N)
{
	return N(v.data);
}