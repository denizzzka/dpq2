module dpq2.conv.to_d_types;

@safe:

import dpq2.value: Value, ValueFormat;
import dpq2.oids: OidType, isNativeInteger, isNativeFloat;
import dpq2.connection: Connection;
import dpq2.query: QueryParams;
import dpq2.result: msg_NOT_BINARY;
import dpq2.conv.from_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
import dpq2.conv.time: binaryValueAs, TimeStampWithoutTZ;
import dpq2.exception;

import vibe.data.json: Json, parseJsonString;
import vibe.data.bson: Bson;
import std.traits;
import std.uuid;
import std.datetime;
import std.traits: isScalarType;
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
alias PGbytea =         const ubyte[]; /// bytea
alias PGuuid =          UUID; /// UUID
alias PGdate =          Date; /// Date (no time of day)
alias PGtime_without_time_zone = TimeOfDay; /// Time of day (no date)
alias PGtimestamp_without_time_zone = TimeStampWithoutTZ; /// Both date and time (no time zone)
alias PGjson =          Json; /// json or jsonb

package void throwTypeComplaint(OidType receivedType, string expectedType, string file, size_t line) pure
{
    throw new AnswerConvException(
            ConvExceptionType.NOT_IMPLEMENTED,
            "Format of the column ("~to!string(receivedType)~") doesn't match to D native "~expectedType,
            file, line
        );
}

private alias VF = ValueFormat;
private alias AE = AnswerConvException;
private alias ET = ConvExceptionType;

/// Returns cell value as native string type from text or binary formatted field
string as(T)(in Value v) pure @trusted
if(is(T == string))
{
    if(v.format == VF.BINARY)
    {
        if(!(
            v.oidType == OidType.Text ||
            v.oidType == OidType.FixedString ||
            v.oidType == OidType.Numeric ||
            v.oidType == OidType.Json
        ))
            throwTypeComplaint(v.oidType, "Text, FixedString, Numeric or Json", __FILE__, __LINE__);

        if(v.oidType == OidType.Numeric)
            return rawValueToNumeric(v.data);
    }

    return valueAsString(v);
}

/// Returns value as D type value from binary formatted field
T as(T)(in Value v)
if(!is(T == string) && !is(T == Bson))
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    return binaryValueAs!T(v);
}

package:

string valueAsString(in Value v) pure
{
    return (cast(const(char[])) v.data).to!string;
}

/// Returns value as bytes from binary formatted field
T binaryValueAs(T)(in Value v)
if( is( T == const(ubyte[]) ) )
{
    if(!(v.oidType == OidType.ByteArray))
        throwTypeComplaint(v.oidType, "ubyte[] or string", __FILE__, __LINE__);

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

public void _integration_test( string connParam ) @system
{
    import std.algorithm : endsWith;
    import std.array : replace;
    import std.format : format;
    import std.math : abs;

    auto conn = new Connection(connParam);

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(T)(T nativeValue, string pgType, string pgValue)
        {
            import std.algorithm : strip;
            import std.string : representation;

            // test string to native conversion
            params.sqlCommand = format("SELECT %s::%s as d_type_test_value", pgValue, pgType);
            params.args = null;
            auto answer = conn.execParams(params);
            immutable Value v = answer[0][0];
            auto result = v.as!T;

            assert(result == nativeValue,
                format("Received unexpected value\nreceived pgType=%s\nexpected nativeType=%s\nsent pgValue=%s\nexpected nativeValue=%s\nresult=%s",
                v.oidType, typeid(T), pgValue, nativeValue, result)
            );

            //TODO: Implement toValue for all tested types and remove the condition
            static if (!is(T == UUID) && !is(T == const(ubyte[])) && !is(T == Json) && !is(T == TimeStampWithoutTZ))
            {
                // test binary to text conversion
                params.sqlCommand = "SELECT $1::text";
                params.args = [nativeValue.toValue];
                auto answer2 = conn.execParams(params);
                auto v2 = answer2[0][0];
                auto textResult = v2.as!string.strip(' ');
                pgValue = pgValue.strip('\'');

                assert(textResult == pgValue,
                    format("Received unexpected value\nreceived pgType=%s\nsent nativeType=%s\nsent nativeValue=%s\nexpected pgValue=%s\nresult=%s\nexpectedRepresentation=%s\nreceivedRepresentation=%s",
                    v.oidType, typeid(T), nativeValue, pgValue, textResult, pgValue.representation, textResult.representation)
                );
            }
            else pragma(msg, T, " Is not tested in integration tests!");
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
        C!PGtext("12345 ", "char(6)", "'12345'");
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
        C!PGdate(Date(2016, 01, 8), "date", "'2016-01-08'");
        C!PGtime_without_time_zone(TimeOfDay(12, 34, 56), "time without time zone", "'12:34:56'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12)), "timestamp without time zone", "'1997-12-17 07:37:16.000012'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ.max, "timestamp without time zone", "'infinity'");
        C!PGtimestamp_without_time_zone(TimeStampWithoutTZ.min, "timestamp without time zone", "'-infinity'");

        // systime testing
        auto testTZ = new immutable SimpleTimeZone(2.dur!"hours"); // custom TZ
        auto sysTime = SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12), testTZ); // time in custom TZ
        auto sysTimeText = sysTime.toLocalTime.toISOExtString.replace("T", " "); // expected text to check against

        // append LocalTime offset (SysTime.toISOExtString in LocalTime doesn't append the TZ offset)
        auto splitRes = LocalTime().utcOffsetAt(sysTime.stdTime).split!("hours", "minutes");
        sysTimeText ~= splitRes.hours >= 0 ? "+" : "-";
        sysTimeText ~= format!"%02d"(abs(splitRes.hours));
        if (splitRes.minutes > 0) sysTimeText ~= format!":%02d"(abs(splitRes.minutes));

        C!SysTime(sysTime, "timestamp with time zone", "'"~sysTimeText~"'");

        // json
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string")]), "json", `'{"float_value": 123.456,"text_str": "text string"}'`);

        // json as string
        C!string(`{"float_value": 123.456}`, "json", `'{"float_value": 123.456}'`);

        // jsonb
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string"), "abc": Json(["key": Json("value")])]), "jsonb",
            `'{"float_value": 123.456, "text_str": "text string", "abc": {"key": "value"}}'`);
    }
}
