module dpq2.types.bson;

import dpq2.answer;
import dpq2.oids;

import vibe.data.bson;

private alias VF = ValueFormat;
private alias AE = AnswerException;
private alias ET = ExceptionType;

@property
Bson toBson(const Value v)
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    Bson res;

    with(OidType)
    with(Bson.Type)
    switch(v.oidType)
    {
        case ByteArray:
            res = Bson(binData, v.value.idup);
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
        void testIt(T)(T nativeValue, string pgType, string pgValue)
        {
            params.sqlCommand = "SELECT "~pgValue~"::"~pgType~" as sql_test_value";
            auto answer = conn.exec(params);

            assert(answer[0][0].as!T == nativeValue, "pgType="~pgType~" pgValue="~pgValue~" nativeType="~to!string(typeid(T))~" nativeValue="~to!string(nativeValue));
        }

        alias C = testIt; // "C" means "case"

        C!PGsmallint(-32_761, "smallint", "-32761");
        C!PGinteger(-2_147_483_646, "integer", "-2147483646");
    }
}
