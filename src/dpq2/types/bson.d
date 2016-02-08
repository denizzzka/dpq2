module dpq2.types.bson;

import dpq2.answer;
import dpq2.oids;

import vibe.data.bson;
import std.uuid;
import std.datetime: SysTime;

@property
Bson toBson(in Nullable!Value v)
{
    if(v.isNull)
        return Bson(null);
    else
        return toBson(v.get);
}

@property
Bson toBson(in Value v)
{
    if(v.isArray)
        return arrayValueToBson(v);
    else
        return rawValueToBson(v);
}

private Bson arrayValueToBson(in Value cell)
{
    const ap = ArrayProperties(cell);

    size_t curr_offset = ap.dataOffset;

    Bson recursive(size_t dimNum)
    {
        const dimSize = ap.dimsSize[dimNum];
        Bson[] res = new Bson[dimSize];

        foreach(elemNum; 0..dimSize)
        {
            if(dimNum < ap.nDims - 1)
            {
                res[elemNum] = recursive(dimNum + 1);
            }
            else
            {
                ubyte[int.sizeof] size_net; // network byte order
                size_net[] = cell.value[ curr_offset .. curr_offset + size_net.sizeof ];
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
                    auto v = Value(cell.value[curr_offset .. curr_offset + size], ap.OID);
                    b = v.toBson;
                }

                curr_offset += size;
                res[elemNum] = b;
            }
        }

        return Bson(res);
    }

    return recursive(0);
}

private Bson rawValueToBson(const Value v)
{
    if(!(v.format == ValueFormat.BINARY))
        throw new AnswerException(ExceptionType.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    Bson res;

    with(OidType)
    with(Bson.Type)
    switch(v.oidType)
    {
        case OidType.Bool:
            bool n = v.as!PGboolean;
            res = Bson(n);
            break;

        case Int2:
            auto n = to!int(v.as!PGsmallint);
            res = Bson(n);
            break;

        case Int4:
            int n = v.as!PGinteger;
            res = Bson(n);
            break;

        case Int8:
            long n = v.as!PGbigint;
            res = Bson(n);
            break;

        case Float8:
            double n = v.as!PGdouble_precision;
            res = Bson(n);
            break;

        case Numeric:
        case Text:
            res = Bson(v.as!PGtext);
            break;

        case ByteArray:
            auto b = BsonBinData(BsonBinData.Type.userDefined, v.value.idup);
            res = Bson(b);
            break;

        case UUID:
            res = Uuid2Bson(v.as!PGuuid);
            break;

        case TimeStamp:
            auto ts = v.as!PGtimestamp_without_time_zone;
            auto s = SysTime(ts.dateTime, ts.fracSec);
            res = Bson(BsonDate(s));
            break;

        default:
            throw new AnswerException(
                    ExceptionType.NOT_IMPLEMENTED,
                    "Format of the column ("~to!(immutable(char)[])(v.oidType)~") doesn't supported by Bson converter",
                    __FILE__, __LINE__
                );
    }

    return res;
}

void _integration_test( string connParam )
{
    import std.uuid;
    import std.datetime: SysTime, DateTime, dur;

    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(Bson bsonValue, string pgType, string pgValue)
        {
            params.sqlCommand = "SELECT "~pgValue~"::"~pgType~" as bson_test_value";
            auto answer = conn.exec(params);

            Nullable!Value v = answer[0][0];
            Bson bsonRes = toBson(v);

            if(v.isNull || !v.isArray) // standalone
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
        C(Bson("-487778762.918209326"), "numeric", "-487778762.918209326");
        C(Bson(BsonDate(SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(123455)))), "timestamp without time zone", "'1997-12-17 07:37:16.123456'");

        C(Bson(BsonBinData(
                    BsonBinData.Type.userDefined,
                    [0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21]
                )),
                "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)

        C(Uuid2Bson(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")),
                "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");

        C(Bson([
                Bson([Bson([Bson("1")]),Bson([Bson("22")]),Bson([Bson("333")])]),
                Bson([Bson([Bson("4")]),Bson([Bson(null)]),Bson([Bson("6")])])
            ]), "text[]", "'{{{1},{22},{333}},{{4},{null},{6}}}'");
    }
}

private Bson Uuid2Bson(in UUID uuid)
{
    return Bson(BsonBinData(BsonBinData.Type.uuid, uuid.data.idup));
}

private UUID Bson2Uuid(in Bson bson)
{
    const ubyte[16] b = bson.get!BsonBinData().rawData;

    return UUID(b);
}

unittest
{
    auto srcUuid = UUID("00010203-0405-0607-0809-0a0b0c0d0e0f");

    auto b = Uuid2Bson(srcUuid);
    auto u = Bson2Uuid(b);

    assert(b.type == Bson.Type.binData);
    assert(b.get!BsonBinData().type == BsonBinData.Type.uuid);
    assert(u == srcUuid);
}
