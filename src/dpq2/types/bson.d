module dpq2.types.bson;

import dpq2.answer;
import dpq2.oids;

import vibe.data.bson;

@property
Bson toBson(const Value v)
{
    if(!(v.format == ValueFormat.BINARY))
        throw new AnswerException(ExceptionType.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    Bson res;

    with(OidType)
    with(Bson.Type)
    switch(v.oidType)
    {
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

            assert(answer[0][0].toBson.type == bsonValue.type);
            assert(answer[0][0].toBson == bsonValue, "pgType="~pgType~" pgValue="~pgValue~
                " bsonType="~to!string(bsonValue.type)~" bsonValue="~to!string(bsonValue));
        }

        alias C = testIt; // "C" means "case"

        C(Bson(-32_761), "smallint", "-32761");
        C(Bson(-2_147_483_646), "integer", "-2147483646");
        C(Bson(-9_223_372_036_854_775_806), "bigint", "-9223372036854775806");
        //C(Bson(-12.3456f), "real", "-12.3456"); // FIXME: https://github.com/rejectedsoftware/vibe.d/issues/1403
        C(Bson(-1234.56789012345), "double precision", "-1234.56789012345");
        C(Bson("first line\nsecond line"), "text", "'first line\nsecond line'");
    }
}
