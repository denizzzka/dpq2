module dpq2.types.to_d_types;

import dpq2.answer;
import dpq2.oids;
import dpq2.types.numeric: rawValueToNumeric;
import dpq2.types.time: as, TimeStampWithoutTZ;

import vibe.data.json: Json, parseJsonString;

import std.traits;
import std.uuid;
import std.datetime;

// Supported PostgreSQL binary types
alias PGboolean =       bool; /// boolean
alias PGsmallint =      short; /// smallint
alias PGinteger =       int; /// integer
alias PGbigint =        long; /// bigint
alias PGreal =          float; /// real
alias PGdouble_precision = double; /// double precision
alias PGtext =          string; /// text
alias PGnumeric =       string; /// numeric represented as string
alias PGbytea =         const ubyte[]; /// bytea
alias PGuuid =          UUID; /// UUID
alias PGdate =          Date; /// Date (no time of day)
alias PGtime_without_time_zone = TimeOfDay; /// Time of day (no date)
alias PGtimestamp_without_time_zone = TimeStampWithoutTZ; /// Both date and time (no time zone)
alias PGjson =          Json; /// json

package void throwTypeComplaint(OidType receivedType, string expectedType, string file, size_t line)
{
    throw new AnswerException(
            ExceptionType.NOT_IMPLEMENTED,
            "Format of the column ("~to!string(receivedType)~") doesn't match to D native "~expectedType,
            file, line
        );
}

private alias VF = ValueFormat;
private alias AE = AnswerException;
private alias ET = ExceptionType;

/// Returns value as bytes from binary formatted field
@property T as(T)(in Value v)
if( is( T == const(ubyte[]) ) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    if(!(v.oidType == OidType.ByteArray))
        throwTypeComplaint(v.oidType, "ubyte[] or string", __FILE__, __LINE__);

    return v.value;
}

/// Returns cell value as native string type
@property string as(T)(in Value v)
if(is(T == string))
{
    if(v.format == VF.BINARY)
    {
        if(!(v.oidType == OidType.Text || v.oidType == OidType.Numeric))
            throwTypeComplaint(v.oidType, "string", __FILE__, __LINE__);

        if(v.oidType == OidType.Numeric)
            return rawValueToNumeric(v.value);
    }

    return to!string( cast(const(char[])) v.value );
}

/// Returns cell value as native integer or decimal values
///
/// Postgres type "numeric" is oversized and not supported by now
@property T as(T)(in Value v)
if( isNumeric!(T) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    static if(isIntegral!(T))
        if(!isNativeInteger(v.oidType))
            throwTypeComplaint(v.oidType, "integral types", __FILE__, __LINE__);

    static if(isFloatingPoint!(T))
        if(!isNativeFloat(v.oidType))
            throwTypeComplaint(v.oidType, "floating point types", __FILE__, __LINE__);

    if(!(v.value.length == T.sizeof))
        throw new AE(ET.SIZE_MISMATCH,
            to!string(v.oidType)~" length ("~to!string(v.value.length)~") isn't equal to native D type "~
                to!string(typeid(T))~" size ("~to!string(T.sizeof)~")",
            __FILE__, __LINE__);

    ubyte[T.sizeof] s = v.value[0..T.sizeof];
    return bigEndianToNative!(T)(s);
}

/// Returns UUID as native UUID value
@property UUID as(T)(in Value v)
if( is( T == UUID ) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    if(!(v.oidType == OidType.UUID))
        throwTypeComplaint(v.oidType, "UUID", __FILE__, __LINE__);

    if(!(v.value.length == 16))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres UUID size", __FILE__, __LINE__);

    UUID r;
    r.data = v.value;
    return r;
}

/// Returns boolean as native bool value
@property bool as(T)(in Value v)
if( is( T == bool ) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    if(!(v.oidType == OidType.Bool))
        throwTypeComplaint(v.oidType, "bool", __FILE__, __LINE__);

    if(!(v.value.length == 1))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres boolean size", __FILE__, __LINE__);

    return v.value[0] != 0;
}

/// Returns Vibe.d's Json
@property Json as(T)(in Value v)
if( is( T == Json ) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    if(!(v.oidType == OidType.Json))
        throwTypeComplaint(v.oidType, "json", __FILE__, __LINE__);

    // represent value as text and parse it to json
    auto t = Value(v.value, OidType.Text);
    return parseJsonString(t.as!PGtext);
}

void _integration_test( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(T)(T nativeValue, string pgType, string pgValue)
        {
            params.sqlCommand = "SELECT "~pgValue~"::"~pgType~" as d_type_test_value";
            auto answer = conn.exec(params);
            Value v = answer[0][0].get;
            auto result = v.as!T;

            assert(result == nativeValue, "Received unexpected value\nreceived pgType="~to!string(v.oidType)~"\nexpected nativeType="~to!string(typeid(T))~
                "\nsent pgValue="~pgValue~"\nexpected nativeValue="~to!string(nativeValue)~"\nresult="~to!string(result));
        }

        alias C = testIt; // "C" means "case"

        C!PGboolean(true, "boolean", "true");
        C!PGboolean(false, "boolean", "false");
        C!PGsmallint(-32_761, "smallint", "-32761");
        C!PGinteger(-2_147_483_646, "integer", "-2147483646");
        C!PGbigint(-9_223_372_036_854_775_806, "bigint", "-9223372036854775806");
        C!PGreal(-12.3456f, "real", "-12.3456");
        C!PGdouble_precision(-1234.56789012345, "double precision", "-1234.56789012345");
        C!PGtext("first line\nsecond line", "text", "'first line\nsecond line'");
        C!PGbytea([0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21],
            "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)
        C!PGuuid(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640"), "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");

        // numeric testing
        C!PGnumeric("NaN", "numeric", "'NaN'");

        const string[] numericTests = [
            "42",
            "-42",
            "0",
            "0.0146328",
            "0.0007",
            "0.007",
            "0.07",
            "0.7",
            "7",
            "70",
            "700",
            "7000",
            "70000",

            "7.0",
            "70.0",
            "700.0",
            "7000.0",
            "70000.000",

            "2354877787627192443",
            "2354877787627192443.0",
            "2354877787627192443.00000",
            "-2354877787627192443.00000"
        ];

        foreach(i, s; numericTests)
            C!PGnumeric(s, "numeric", s);

        // date and time testing
        C!PGdate(Date(2016, 01, 8), "date", "'January 8, 2016'");
        C!PGtime_without_time_zone(TimeOfDay(12, 34, 56), "time without time zone", "'12:34:56'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ(DateTime(1997, 12, 17, 7, 37, 16), FracSec.from!"usecs"(12)), "timestamp without time zone", "'1997-12-17 07:37:16.000012'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ.max, "timestamp without time zone", "'infinity'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ.min, "timestamp without time zone", "'-infinity'");

        // json
        C!PGjson(Json(["integer": Json(123), "float": Json(123.456), "text_string": Json("This is a text string")]), "json",
            "'{\"integer\": 123, \"float\": 123.456,\"text_string\": \"This is a text string\"}'");
    }
}
