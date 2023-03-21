module dpq2.conv.tsearch;

import dpq2.conv.to_d_types;
import dpq2.oids : OidType;
import dpq2.value;

import std.bitmanip : bigEndianToNative;
import std.conv : to;
import std.exception : enforce;
import std.stdio : writefln;
import std.string : fromStringz;
import std.traits : hasMember;


template isTsQuery(T) {
	enum isTsQuery = hasMember!(T, "tokens") && __traits(compiles, typeof(T.tokens));
}

template isTsVector(T) {
	enum isTsVector = hasMember!(T, "lexemes") && __traits(compiles, typeof(T.lexemes));
}

enum TsTokenType : ubyte {
	TS_TYPE_VAL = 1,
	TS_TYPE_OPER = 2
}

enum TsOperator : ubyte {
	TS_OPER_NOT = 1,
	TS_OPER_AND = 2,
	TS_OPER_OR = 3,
	TS_OPER_PHRASE = 4
}

struct TsToken {
	TsTokenType type;
	union {
		struct Oper {
			TsOperator operator;
			ushort distance;
		}
		Oper oper;
		struct Value {
			ubyte weight;
			bool prefix;
			string value;
		}
		Value val;
	}
}

struct TsLexeme {
	string value;
	ushort[] wordEntryPos;

	static ushort weightAsNumber(ushort wordEntry) { return wordEntry >> 14; }
	static char weightAsChar(ushort wordEntry) { return 'D' - (wordEntry >> 14); }
	static ushort pos(ushort wordEntry) { return wordEntry & 0x3FFF; }
}

struct TsQuery {
	TsToken[] tokens;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= uint.sizeof, "cannot construct text search query with insufficient data");

		this._data = binaryData;

		auto count = binaryData[0..uint.sizeof].bigEndianToNative!uint;

		binaryData = binaryData[uint.sizeof..$];

		assert(count, "zero token count?");

		for (uint i = 0; i < count; i++) {
			TsToken token;

			token.type = binaryData[0..ubyte.sizeof].bigEndianToNative!ubyte.to!TsTokenType;
			binaryData = binaryData[ubyte.sizeof..$];

			final switch (token.type) {
				case TsTokenType.TS_TYPE_VAL:
					token.val.weight = binaryData[0..ubyte.sizeof].bigEndianToNative!ubyte;
					binaryData = binaryData[ubyte.sizeof..$];

					token.val.prefix = binaryData[0..ubyte.sizeof].bigEndianToNative!ubyte.to!bool;
					binaryData = binaryData[ubyte.sizeof..$];

					token.val.value = fromStringz(cast(char*)binaryData.ptr).to!string;
					binaryData = binaryData[token.val.value.length+1..$];
					break;

				case TsTokenType.TS_TYPE_OPER:
					token.oper.operator = binaryData[0..ubyte.sizeof].bigEndianToNative!ubyte.to!TsOperator;
					binaryData = binaryData[ubyte.sizeof..$];

					if (token.oper.operator == TsOperator.TS_OPER_PHRASE) {
						token.oper.distance = binaryData[0..ushort.sizeof].bigEndianToNative!ushort;
						binaryData = binaryData[ushort.sizeof..$];
					}
					break;
			}
			this.tokens ~= token;
		}
	}

	size_t length() @property { return tokens.length; }

	auto opIndex(size_t idx) {
		enforce(idx < this.tokens.length, "tokens index out of bounds: " ~ this.tokens.length.to!string ~ "/" ~ idx.to!string);
		return tokens[idx];
	}

	int opApply(scope int delegate(size_t, ref TsToken) dg)
	{
		foreach (i, val; tokens) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}

	int opApplyReverse(scope int delegate(size_t, ref TsToken) dg)
	{
		foreach_reverse (i, val; tokens) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}

	auto rawData() @property { return _data.dup; }
}

struct TsVector {
	TsLexeme[] lexemes;

	immutable(ubyte)[] _data;

	this(immutable(ubyte)[] binaryData) {
		enforce(binaryData.length >= uint.sizeof, "cannot construct text search vector with insufficient data");

		this._data = binaryData;

		auto count = binaryData[0..uint.sizeof].bigEndianToNative!uint;

		binaryData = binaryData[uint.sizeof..$];

		assert(count, "zero lexeme count?");

		for (uint i = 0; i < count; i++) {
			TsLexeme lexeme;

			lexeme.value = fromStringz(cast(char*)binaryData.ptr).to!string;
			binaryData = binaryData[lexeme.value.length+1..$];

			auto posCount = binaryData[0..ushort.sizeof].bigEndianToNative!ushort;
			binaryData = binaryData[ushort.sizeof..$];

			for (uint j = 0; j < posCount; j++) {
				lexeme.wordEntryPos ~= binaryData[0..ushort.sizeof].bigEndianToNative!ushort;
				binaryData = binaryData[ushort.sizeof..$];
			}
			this.lexemes ~= lexeme;
		}
	}

	size_t length() @property { return lexemes.length; }

	auto opIndex(size_t idx) {
		enforce(idx < this.lexemes.length, "lexemes index out of bounds: " ~ this.lexemes.length.to!string ~ "/" ~ idx.to!string);
		return lexemes[idx];
	}

	int opApply(scope int delegate(size_t, ref TsLexeme) dg)
	{
		foreach (i, val; lexemes) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}

	int opApplyReverse(scope int delegate(size_t, ref TsLexeme) dg)
	{
		foreach_reverse (i, val; lexemes) {
			if (auto result = dg(i, val))
				return result;
		}
		return 0;
	}

	auto rawData() @property { return _data.dup; }
}

package:

/// Convert Value to native text search query type
TQ binaryValueAs(TQ)(in Value v) @trusted
if (isTsQuery!TQ)
{
	return TQ(v.data);
}

/// Convert Value to native text search vector type
TV binaryValueAs(TV)(in Value v) @trusted
if (isTsVector!TV)
{
	return TV(v.data);
}