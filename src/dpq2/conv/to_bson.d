module dpq2.conv.to_bson;

import dpq2.value: Value, ValueFormat;
import dpq2.oids: OidType;
import dpq2.result: ArrayProperties;
import dpq2.exception;
import dpq2.conv.to_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
import vibe.data.bson;
import std.uuid;
import std.datetime: SysTime, dur, TimeZone;
import std.bitmanip: bigEndianToNative;
import std.conv: to;

Bson as(T)(in Value v, immutable TimeZone tz = null)
if(is(T == Bson))
{
    if(v.isNull)
    {
        return Bson(null);
    }
    else
    {
        if(v.isSupportedArray && ValueFormat.BINARY)
            return arrayValueToBson(v, tz);
        else
            return rawValueToBson(v, tz);
    }
}

private:

Bson arrayValueToBson(in Value cell, immutable TimeZone tz)
{
    const ap = ArrayProperties(cell);

    // empty array
    if(ap.dimsSize.length == 0) return Bson.emptyArray;

    size_t curr_offset = ap.dataOffset;

    Bson recursive(size_t dimNum)
    {
        const dimSize = ap.dimsSize[dimNum];
        Bson[] res = new Bson[dimSize];

        foreach(elemNum; 0..dimSize)
        {
            if(dimNum < ap.dimsSize.length - 1)
            {
                res[elemNum] = recursive(dimNum + 1);
            }
            else
            {
                ubyte[int.sizeof] size_net; // network byte order
                size_net[] = cell.data[ curr_offset .. curr_offset + size_net.sizeof ];
                uint size = bigEndianToNative!uint( size_net );

                curr_offset += size_net.sizeof;

                Bson b;
                if(size == size.max) // NULL magic number
                {
                    b = Bson(null);
                    size = 0;
                }
                else
                {
                    auto v = Value(cast(ubyte[]) cell.data[curr_offset .. curr_offset + size], ap.OID, false);
                    b = v.as!Bson(tz);
                }

                curr_offset += size;
                res[elemNum] = b;
            }
        }

        return Bson(res);
    }

    return recursive(0);
}

Bson rawValueToBson(in Value v, immutable TimeZone tz = null)
{
    if(v.format == ValueFormat.TEXT)
    {
        const text = v.valueAsString;

        if(v.oidType == OidType.Json)
        {
            return Bson(text.parseJsonString);
        }

        return Bson(text);
    }

    Bson res;

    with(OidType)
    with(Bson.Type)
    switch(v.oidType)
    {
        case OidType.Bool:
            bool n = v.binaryValueAs!PGboolean;
            res = Bson(n);
            break;

        case Int2:
            auto n = to!int(v.binaryValueAs!PGsmallint);
            res = Bson(n);
            break;

        case Int4:
            int n = v.binaryValueAs!PGinteger;
            res = Bson(n);
            break;

        case Int8:
            long n = v.binaryValueAs!PGbigint;
            res = Bson(n);
            break;

        case Float8:
            double n = v.binaryValueAs!PGdouble_precision;
            res = Bson(n);
            break;

        case Numeric:
            res = Bson(rawValueToNumeric(v.data));
            break;

        case Text:
        case FixedString:
            res = Bson(v.valueAsString);
            break;

        case ByteArray:
            auto b = BsonBinData(BsonBinData.Type.userDefined, v.data.idup);
            res = Bson(b);
            break;

        case UUID:
            res = Bson(v.binaryValueAs!PGuuid);
            break;

        case TimeStamp:
            auto ts = v.binaryValueAs!PGtimestamp_without_time_zone;
            auto time = BsonDate(SysTime(ts.dateTime, tz));
            long usecs = ts.fracSec.total!"usecs";
            res = Bson(["time": Bson(time), "usecs": Bson(usecs)]);
            break;

        case Json:
        case Jsonb:
            vibe.data.json.Json json = binaryValueAs!PGjson(v);
            res = Bson(json);
            break;

        default:
            throw new AnswerConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format of the column ("~to!(immutable(char)[])(v.oidType)~") doesn't supported by Value to Bson converter",
                    __FILE__, __LINE__
                );
    }

    return res;
}

public void _integration_test( string connParam )
{
    import dpq2.connection: Connection;
    import dpq2.args: QueryParams;
    import std.uuid;
    import std.datetime: SysTime, DateTime, UTC;

    auto conn = new Connection(connParam);

    // text answer tests
    {
        auto a = conn.exec(
                "SELECT 123::int8 as int_num_value,"~
                       "'text string'::text as text_value,"~
                       "'123.456'::json as json_numeric_value,"~
                       "'\"json_value_string\"'::json as json_text_value"
            );

        auto r = a[0]; // first row

        assert(r["int_num_value"].as!Bson == Bson("123"));
        assert(r["text_value"].as!Bson == Bson("text string"));
        assert(r["json_numeric_value"].as!Bson == Bson(123.456));
        assert(r["json_text_value"].as!Bson == Bson("json_value_string"));
    }

    // binary answer tests
    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(Bson bsonValue, string pgType, string pgValue)
        {
            params.sqlCommand = "SELECT "~pgValue~"::"~pgType~" as bson_test_value";
            auto answer = conn.execParams(params);

            immutable Value v = answer[0][0];
            Bson bsonRes = v.as!Bson(UTC());

            if(v.isNull || !v.isSupportedArray) // standalone
            {
                if(pgType == "numeric") pgType = "string"; // bypass for numeric values represented as strings

                assert(bsonRes == bsonValue, "Received unexpected value\nreceived bsonType="~to!string(bsonValue.type)~"\nexpected nativeType="~pgType~
                    "\nsent pgValue="~pgValue~"\nexpected bsonValue="~to!string(bsonValue)~"\nresult="~to!string(bsonRes));
            }
            else // arrays
            {
                assert(bsonRes.type == Bson.Type.array && bsonRes.toString == bsonValue.toString,
                    "pgType="~pgType~" pgValue="~pgValue~" bsonValue="~to!string(bsonValue));
            }
        }

        alias C = testIt; // "C" means "case"

        C(Bson(null), "text", "null");
        C(Bson(null), "integer", "null");
        C(Bson(true), "boolean", "true");
        C(Bson(false), "boolean", "false");
        C(Bson(-32_761), "smallint", "-32761");
        C(Bson(-2_147_483_646), "integer", "-2147483646");
        C(Bson(-9_223_372_036_854_775_806), "bigint", "-9223372036854775806");
        C(Bson(-1234.56789012345), "double precision", "-1234.56789012345");
        C(Bson("first line\nsecond line"), "text", "'first line\nsecond line'");
        C(Bson("12345 "), "char(6)", "'12345'");
        C(Bson("-487778762.918209326"), "numeric", "-487778762.918209326");

        C(Bson(BsonBinData(
                    BsonBinData.Type.userDefined,
                    [0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21]
                )),
                "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)

        C(Bson(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")),
                "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");

        C(Bson([
                Bson([Bson([Bson("1")]),Bson([Bson("22")]),Bson([Bson("333")])]),
                Bson([Bson([Bson("4")]),Bson([Bson(null)]),Bson([Bson("6")])])
            ]), "text[]", "'{{{1},{22},{333}},{{4},{null},{6}}}'");

        C(Bson.emptyArray, "text[]", "'{}'");

        C(Bson(["time": Bson(BsonDate(SysTime(DateTime(1997, 12, 17, 7, 37, 16), UTC()))), "usecs": Bson(cast(long) 12)]), "timestamp without time zone", "'1997-12-17 07:37:16.000012'");

        C(Bson(Json(["float_value": Json(123.456), "text_str": Json("text string")])), "json", "'{\"float_value\": 123.456,\"text_str\": \"text string\"}'");

        C(Bson(Json(["float_value": Json(123.456), "text_str": Json("text string")])), "jsonb", "'{\"float_value\": 123.456,\"text_str\": \"text string\"}'");
    }
}
