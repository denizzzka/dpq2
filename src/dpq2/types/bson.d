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
            int n = cast(int) v.as!PGsmallint;
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
            params.sqlCommand = "SELECT "~pgValue~"::"~pgType~" as sql_test_value";
            auto answer = conn.exec(params);

            assert(answer[0][0].toBson == bsonValue, "pgType="~pgType~" pgValue="~pgValue~" nativeValue="~to!string(bsonValue));
        }

        alias C = testIt; // "C" means "case"

        C(Bson(-32_761), "smallint", "-32761");
        C(Bson("first line\nsecond line"), "text", "'first line\nsecond line'");
    }
}
