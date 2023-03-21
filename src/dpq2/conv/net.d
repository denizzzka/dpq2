module dpq2.conv.net;

import dpq2.conv.to_d_types;
import dpq2.oids : OidType;
import dpq2.value;

import std.bitmanip : bigEndianToNative;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.socket : AddressFamily;
import std.traits : hasMember;


enum PG_TYPE : ushort {
	INET_ADDR = 0,
	CIDR_ADDR = 1
}

template isNetworkAddress(T) {
	enum isNetworkAddress = hasMember!(T, "isInet") && __traits(compiles, typeof(T.isInet));
}

struct NetworkAddress {
	AddressFamily family;
	ubyte netmask;
	PG_TYPE type;
	ubyte addressLen;
	ubyte[] address;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= uint.sizeof, "cannot construct network address with insufficient data");

		this._data = binaryData;

		this.family = binaryData[0].to!AddressFamily;
		this.netmask = binaryData[1];
		this.type = binaryData[2].to!PG_TYPE;
		this.addressLen = binaryData[3];

		binaryData = binaryData[4..$];

		assert(this.addressLen <= binaryData.length, "data shorter than address length");
		assert(this.addressLen, "zero address length?");

		this.address = binaryData[0..this.addressLen].dup;
	}

	bool isInet() @property { return type == PG_TYPE.INET_ADDR; }
	bool isCidr() @property { return type == PG_TYPE.CIDR_ADDR; }

	auto toString() {
		switch (this.family) {
			case AddressFamily.INET:
				return format("%(%d.%)/%d", this.address[0..this.addressLen], this.netmask);

			case AddressFamily.INET6:
				return format("%(%x:%)/%d", this.address[0..this.addressLen].to!(ushort[]), this.netmask);

			default:
				return format("NetowrkAddress(%d,%d,%d,%d,%s)", this.family, this.netmask, this.type, this.addressLen, this.address);
		}
	}
}

package:

/// Convert Value to native network address type
N binaryValueAs(N)(in Value v) @trusted
if (isNetworkAddress!N)
{
	return N(v.data);
}