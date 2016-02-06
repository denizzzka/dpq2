module dpq2.types.bson;

import dpq2.answer;
import dpq2.oids;

import vibe.data.bson;
import std.uuid;

@property
Bson toBson(const Nullable!Value v)
{
    if(v.isNull)
        return Bson(null);
    else
        return v.rawValueToBson;
}

@property
Bson toBson(const Value v)
{
    if(v.isArray)
        return arrayValueToBson(v);
    else
        return rawValueToBson(v);
}

private Bson arrayValueToBson(in Value cell)
{
    auto ap = ArrayProperties(cell);
    size_t curr_offset = ap.dataOffset;
    Bson[] res;

    for(uint i = 0; i < ap.nElems; ++i )
    {
        ubyte[int.sizeof] size_net; // network byte order
        size_net[] = cell.value[ curr_offset .. curr_offset + size_net.sizeof ];
        uint size = bigEndianToNative!uint( size_net );

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

        curr_offset += size_net.sizeof;
        curr_offset += size;

        res ~= b;
    }

    return Bson(res);
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

        case Float4:
            auto n = to!double(v.as!PGreal);
            res = Bson(n);
            break;

        case Float8:
            double n = v.as!PGdouble_precision;
            res = Bson(n);
            break;

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

        default:
            throw new AnswerException(
                    ExceptionType.NOT_IMPLEMENTED,
                    "Format of the column (~to!string(v.oidType)~) doesn't supported by Bson converter",
                    __FILE__, __LINE__
                );
    }

    return res;
}

void _integration_test( string connParam )
{
    import std.uuid;

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

            assert(answer[0][0].toBson == bsonValue, "pgType="~pgType~" pgValue="~pgValue~
                " bsonType="~to!string(bsonValue.type)~" bsonValue="~to!string(bsonValue));
        }

        alias C = testIt; // "C" means "case"

        C(Bson(null), "text", "null");
        C(Bson(null), "integer", "null");
        C(Bson(true), "boolean", "true");
        C(Bson(false), "boolean", "false");
        C(Bson(-32_761), "smallint", "-32761");
        C(Bson(-2_147_483_646), "integer", "-2147483646");
        C(Bson(-9_223_372_036_854_775_806), "bigint", "-9223372036854775806");
        //C(Bson(-12.3456f), "real", "-12.3456"); // FIXME: https://github.com/rejectedsoftware/vibe.d/issues/1403
        C(Bson(-1234.56789012345), "double precision", "-1234.56789012345");
        C(Bson("first line\nsecond line"), "text", "'first line\nsecond line'");

        C(Bson(BsonBinData(
                    BsonBinData.Type.userDefined,
                    [0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21]
                )),
                "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)

        C(Uuid2Bson(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")),
                "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");
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
