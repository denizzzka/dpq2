///
module dpq2.conv.to_d_types;

@safe:

import dpq2.value;
import dpq2.oids: OidType, isNativeInteger, isNativeFloat;
import dpq2.connection: Connection;
import dpq2.query: QueryParams;
import dpq2.result: msg_NOT_BINARY;
import dpq2.conv.from_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
import dpq2.conv.time: binaryValueAs, TimeStamp, TimeStampUTC;
import dpq2.conv.geometric: binaryValueAs, Line;
import dpq2.conv.arrays : binaryValueAs;

import vibe.data.json: Json, parseJsonString;
import vibe.data.bson: Bson;
import std.traits;
import std.uuid;
import std.datetime;
import std.traits: isScalarType;
import std.variant: Variant;
import std.typecons : Nullable;
import std.bitmanip: bigEndianToNative, BitArray;
import std.conv: to;
version (unittest) import std.exception : assertThrown;

// Supported PostgreSQL binary types
alias PGboolean =       bool; /// boolean
alias PGsmallint =      short; /// smallint
alias PGinteger =       int; /// integer
alias PGbigint =        long; /// bigint
alias PGreal =          float; /// real
alias PGdouble_precision = double; /// double precision
alias PGtext =          string; /// text
alias PGnumeric =       string; /// numeric represented as string
alias PGbytea =         immutable(ubyte)[]; /// bytea
alias PGuuid =          UUID; /// UUID
alias PGdate =          Date; /// Date (no time of day)
alias PGtime_without_time_zone = TimeOfDay; /// Time of day (no date)
alias PGtimestamp = TimeStamp; /// Both date and time without time zone
alias PGtimestamptz = TimeStampUTC; /// Both date and time stored in UTC time zone
alias PGjson =          Json; /// json or jsonb
alias PGline =          Line; /// Line (geometric type)
alias PGvarbit =        BitArray; /// BitArray

private alias VF = ValueFormat;
private alias AE = ValueConvException;
private alias ET = ConvExceptionType;

/**
    Returns cell value as a Variant type.
*/
T as(T : Variant, bool nullablePayload = true)(in Value v)
{
    import dpq2.conv.to_variant;

    return v.toVariant!nullablePayload;
}

/**
    Returns cell value as a Nullable type using the underlying type conversion after null check.
*/
T as(T : Nullable!R, R)(in Value v)
{
    if (v.isNull)
        return T.init;
    else
        return T(v.as!R);
}

/**
    Returns cell value as a native string based type from text or binary formatted field.
    Throws: AssertError if the db value is NULL.
*/
T as(T)(in Value v) pure @trusted
if(is(T : const(char)[]) && !is(T == Nullable!R, R))
{
    if(v.format == VF.BINARY)
    {
        if(!(
            v.oidType == OidType.Text ||
            v.oidType == OidType.FixedString ||
            v.oidType == OidType.VariableString ||
            v.oidType == OidType.Numeric ||
            v.oidType == OidType.Json ||
            v.oidType == OidType.Jsonb ||
            v.oidType == OidType.Name
        ))
            throwTypeComplaint(v.oidType, "Text, FixedString, VariableString, Name, Numeric, Json or Jsonb", __FILE__, __LINE__);
    }

    if(v.format == VF.BINARY && v.oidType == OidType.Numeric)
        return rawValueToNumeric(v.data); // special case for 'numeric' which represented in dpq2 as string
    else
        return v.valueAsString;
}

@system unittest
{
    import core.exception: AssertError;

    auto v = Value(ValueFormat.BINARY, OidType.Text);

    assert(v.isNull);
    assertThrown!AssertError(v.as!string == "");
    assert(v.as!(Nullable!string).isNull == true);
}

/**
    Returns value as D type value from binary formatted field.
    Throws: AssertError if the db value is NULL.
*/
T as(T)(in Value v)
if(!is(T : const(char)[]) && !is(T == Bson) && !is(T == Variant) && !is(T == Nullable!R,R))
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    return binaryValueAs!T(v);
}

@system unittest
{
    auto v = Value([1], OidType.Int4, false, ValueFormat.TEXT);
    assertThrown!AE(v.as!int);
}

Value[] deserializeRecord(in Value v)
{
    if(!(v.oidType == OidType.Record))
        throwTypeComplaint(v.oidType, "record", __FILE__, __LINE__);

    if(!(v.data.length >= uint.sizeof))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't enough to hold a size", __FILE__, __LINE__);

    immutable(ubyte)[] data = v.data;
    uint entries = bigEndianToNative!uint(v.data[0 .. uint.sizeof]);
    data = data[uint.sizeof .. $];

    Value[] ret = new Value[entries];

    foreach (ref res; ret) {
        if (!(data.length >= 2*int.sizeof))
            throw new AE(ET.SIZE_MISMATCH,
                "Value length isn't enough to hold an oid and a size", __FILE__, __LINE__);
        OidType oidType = cast(OidType)bigEndianToNative!int(data[0 .. int.sizeof]);
        data = data[int.sizeof .. $];
        int size = bigEndianToNative!int(data[0 .. int.sizeof]);
        data = data[int.sizeof .. $];

        if (size == -1)
        {
            res = Value(null, oidType, true);
            continue;
        }
        assert(size >= 0);
        if (!(data.length >= size))
            throw new AE(ET.SIZE_MISMATCH,
                "Value length isn't enough to hold object body", __FILE__, __LINE__);
        immutable(ubyte)[] resData = data[0 .. size];
        data = data[size .. $];
        res = Value(resData, oidType);
    }

    return ret;
}

package:

/*
 * Something was broken in DMD64 D Compiler v2.079.0-rc.1 so I made this "tunnel"
 * TODO: remove it and replace by direct binaryValueAs calls
 */
auto tunnelForBinaryValueAsCalls(T)(in Value v)
{
    return binaryValueAs!T(v);
}

char[] valueAsString(in Value v) pure
{
    return (cast(const(char[])) v.data).to!(char[]);
}

/// Returns value as bytes from binary formatted field
T binaryValueAs(T)(in Value v)
if(is(T : const ubyte[]))
{
    if(!(v.oidType == OidType.ByteArray))
        throwTypeComplaint(v.oidType, "immutable ubyte[]", __FILE__, __LINE__);

    return v.data;
}

@system unittest
{
    auto v = Value([1], OidType.Bool);
    assertThrown!ValueConvException(v.binaryValueAs!(const ubyte[]));
}

/// Returns cell value as native integer or decimal values
///
/// Postgres type "numeric" is oversized and not supported by now
T binaryValueAs(T)(in Value v)
if( isNumeric!(T) )
{
    static if(isIntegral!(T))
        if(!isNativeInteger(v.oidType))
            throwTypeComplaint(v.oidType, "integral types", __FILE__, __LINE__);

    static if(isFloatingPoint!(T))
        if(!isNativeFloat(v.oidType))
            throwTypeComplaint(v.oidType, "floating point types", __FILE__, __LINE__);

    if(!(v.data.length == T.sizeof))
        throw new AE(ET.SIZE_MISMATCH,
            to!string(v.oidType)~" length ("~to!string(v.data.length)~") isn't equal to native D type "~
                to!string(typeid(T))~" size ("~to!string(T.sizeof)~")",
            __FILE__, __LINE__);

    ubyte[T.sizeof] s = v.data[0..T.sizeof];
    return bigEndianToNative!(T)(s);
}

@system unittest
{
    auto v = Value([1], OidType.Bool);
    assertThrown!ValueConvException(v.binaryValueAs!int);
    assertThrown!ValueConvException(v.binaryValueAs!float);

    v = Value([1], OidType.Int4);
    assertThrown!ValueConvException(v.binaryValueAs!int);
}

/// Returns UUID as native UUID value
UUID binaryValueAs(T)(in Value v)
if( is( T == UUID ) )
{
    if(!(v.oidType == OidType.UUID))
        throwTypeComplaint(v.oidType, "UUID", __FILE__, __LINE__);

    if(!(v.data.length == 16))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres UUID size", __FILE__, __LINE__);

    UUID r;
    r.data = v.data;
    return r;
}

@system unittest
{
    auto v = Value([1], OidType.Int4);
    assertThrown!ValueConvException(v.binaryValueAs!UUID);

    v = Value([1], OidType.UUID);
    assertThrown!ValueConvException(v.binaryValueAs!UUID);
}

/// Returns boolean as native bool value
bool binaryValueAs(T : bool)(in Value v)
if (!is(T == Nullable!R, R))
{
    if(!(v.oidType == OidType.Bool))
        throwTypeComplaint(v.oidType, "bool", __FILE__, __LINE__);

    if(!(v.data.length == 1))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres boolean size", __FILE__, __LINE__);

    return v.data[0] != 0;
}

@system unittest
{
    auto v = Value([1], OidType.Int4);
    assertThrown!ValueConvException(v.binaryValueAs!bool);

    v = Value([1,2], OidType.Bool);
    assertThrown!ValueConvException(v.binaryValueAs!bool);
}

/// Returns Vibe.d's Json
Json binaryValueAs(T)(in Value v) @trusted
if( is( T == Json ) )
{
    import dpq2.conv.jsonb: jsonbValueToJson;

    Json res;

    switch(v.oidType)
    {
        case OidType.Json:
            // represent value as text and parse it into Json
            string t = v.valueAsString;
            res = parseJsonString(t);
            break;

        case OidType.Jsonb:
            res = v.jsonbValueToJson;
            break;

        default:
            throwTypeComplaint(v.oidType, "json or jsonb", __FILE__, __LINE__);
    }

    return res;
}

@system unittest
{
    auto v = Value([1], OidType.Int4);
    assertThrown!ValueConvException(v.binaryValueAs!Json);
}

import money: currency, roundingMode;

/// Returns money type
///
/// Caution: here is no check of fractional precision while conversion!
/// See also: PostgreSQL's "lc_monetary" description and "money" package description
T binaryValueAs(T)(in Value v) @trusted
if( isInstanceOf!(currency, T) &&  T.amount.sizeof == 8 )
{
    import std.format: format;

    if(v.data.length != T.amount.sizeof)
        throw new AE(
            ET.SIZE_MISMATCH,
            format(
                "%s length (%d) isn't equal to D money type %s size (%d)",
                v.oidType.to!string,
                v.data.length,
                typeid(T).to!string,
                T.amount.sizeof
            )
        );

    T r;

    r.amount = v.data[0 .. T.amount.sizeof].bigEndianToNative!long;

    return r;
}

package alias PGTestMoney = currency!("TEST_CURR", 2); //TODO: roundingMode.UNNECESSARY

unittest
{
    auto v = Value([1], OidType.Money);
    assertThrown!ValueConvException(v.binaryValueAs!PGTestMoney);
}

T binaryValueAs(T)(in Value v) @trusted
if( is(T == BitArray) )
{
    import core.bitop : bitswap;
    import std.bitmanip;
    import std.format: format;
    import std.range : chunks;

    if(v.data.length < int.sizeof)
        throw new AE(
            ET.SIZE_MISMATCH,
            format(
                "%s length (%d) is less than minimum int type size (%d)",
                v.oidType.to!string,
                v.data.length,
                int.sizeof
            )
        );

    auto data = v.data;
    size_t len = data.read!int;
    size_t[] newData;
    foreach (ch; data.chunks(size_t.sizeof))
    {
        ubyte[size_t.sizeof] tmpData;
        tmpData[0 .. ch.length] = ch[];

        // DMD Issue 19693
        version(DigitalMars)
            auto re = softBitswap(bigEndianToNative!size_t(tmpData));
        else
            auto re = bitswap(bigEndianToNative!size_t(tmpData));
        newData ~= re;
    }
    return T(newData, len);
}

unittest
{
    auto v = Value([1], OidType.VariableBitString);
    assertThrown!ValueConvException(v.binaryValueAs!BitArray);
}
