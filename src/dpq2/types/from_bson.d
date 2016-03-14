module dpq2.types.from_bson;

@trusted:

import dpq2;
import vibe.data.bson;

/// Default type will be used for NULL values
Value bsonToValue(Bson v, OidType defaultType = OidType.Text)
{
    Value ret;

    with(Bson.Type)
    switch(v.type)
    {
        case null_:
            ret = Value(null, defaultType, true, ValueFormat.BINARY);
            break;

        case int_:
            ret = v.get!int.toValue;
            break;

        case long_:
            ret = v.get!long.toValue;
            break;

        case double_:
            ret = v.get!double.toValue;
            break;

        case Bson.Type.string:
            ret = v.get!(immutable(char)[]).toValue;
            break;

        case Bson.Type.array:
            ret = bsonArrayToValue(v);
            break;

        default:
            throw new AnswerConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format "~v.type.to!(immutable(char)[])~" doesn't supported by Bson to Value converter",
                    __FILE__, __LINE__
                );
    }

    return ret;
}

unittest
{
    {
        Value v1 = bsonToValue(Bson(123));
        Value v2 = (123).toValue;

        assert(v1.as!int == v2.as!int);
    }

    {
        Value v1 = bsonToValue(Bson("Test string"));
        Value v2 = ("Test string").toValue;

        assert(v1.as!string == v2.as!string);
    }
}

private Value bsonArrayToValue(ref Bson v)
{
    ArrayProperties ap;

    ArrayHeader_net h;

    Value ret;

    return ret;
}

private OidType oidType2arrayType(OidType type)
{
    with(OidType)
    switch(type)
    {
        case Text:
            return TextArray;

        case Int2:
            return Int2Array;

        case Int4:
            return Int4Array;

        case Int8:
            return Int8Array;

        case Float4:
            return Float4Array;

        case Float8:
            return Float8Array;

        default:
            throw new AnswerConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format "~type.to!(immutable(char)[])~" doesn't supported by Bson array to Value converter",
                    __FILE__, __LINE__
                );
    }
}
