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

import vibe.data.json: Json, parseJsonString;
import vibe.data.bson: Bson;
import std.traits;
import std.uuid;
import std.datetime;
import std.traits: isScalarType;
import std.typecons : Nullable;
import std.bitmanip: bigEndianToNative;
import std.conv: to;

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

private alias VF = ValueFormat;
private alias AE = ValueConvException;
private alias ET = ConvExceptionType;

/// Returns cell value as native string based type from text or binary formatted field
T as(T)(in Value v) pure @trusted
if(is(T : string))
{
    if(v.format == VF.BINARY)
    {
        if(!(
            v.oidType == OidType.Text ||
            v.oidType == OidType.FixedString ||
            v.oidType == OidType.VariableString ||
            v.oidType == OidType.Numeric ||
            v.oidType == OidType.Json ||
            v.oidType == OidType.Jsonb
        ))
            throwTypeComplaint(v.oidType, "Text, FixedString, VariableString, Numeric, Json or Jsonb", __FILE__, __LINE__);

        if(v.oidType == OidType.Numeric)
            return rawValueToNumeric(v.data).to!T;
    }

    return valueAsString(v).to!T;
}

/// Returns value as D type value from binary formatted field
T as(T)(in Value v)
if(!is(T : string) && !is(T == Bson))
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    static if (is(T == Nullable!R, R))
    {
        if (v.isNull) return T.init;
        return T(binaryValueAs!(TemplateArgsOf!T[0])(v));
    }
    else return binaryValueAs!T(v);
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

string valueAsString(in Value v) pure
{
    if (v.isNull) return null;
    return (cast(const(char[])) v.data).to!string;
}

/// Returns value as bytes from binary formatted field
T binaryValueAs(T)(in Value v)
if(is(T : const ubyte[]))
{
    if(!(v.oidType == OidType.ByteArray))
        throwTypeComplaint(v.oidType, "immutable ubyte[]", __FILE__, __LINE__);

    return v.data;
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
