module dpq2.types.from_bson;

@trusted:

import dpq2;
import vibe.data.bson;
import std.bitmanip: nativeToBigEndian;

/// Default type will be used for NULL value and for array without detected type
@property Value bsonToValue(Bson v)
{
    if(v.type == Bson.Type.array)
        return bsonArrayToValue(v);
    else
        return bsonValueToValue(v);
}

private:

Value bsonValueToValue(Bson v)
{
    Value ret;

    with(Bson.Type)
    switch(v.type)
    {
        case null_:
            ret = Value(ValueFormat.BINARY, OidType.Unknown);
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

Value bsonArrayToValue(ref Bson bsonArr)
{
    ubyte[] nullValue() pure
    {
        ubyte[] ret = [0xff, 0xff, 0xff, 0xff]; //NULL magic number
        return ret;
    }

    ubyte[] rawValue(Value v) pure
    {
        if(v.isNull)
        {
            return nullValue();
        }
        else
        {
            return v._data.length.to!uint.nativeToBigEndian ~ v._data;
        }
    }

    ArrayProperties ap;
    ubyte[] rawValues;

    void recursive(ref Bson bsonArr, int dimension)
    {
        if(dimension == ap.dimsSize.length)
        {
            ap.dimsSize ~= bsonArr.length.to!int;
        }
        else
        {
            if(ap.dimsSize[dimension] != bsonArr.length)
                throw new AnswerConvException(ConvExceptionType.NOT_ARRAY, "Jagged arrays are unsupported", __FILE__, __LINE__);
        }

        foreach(bElem; bsonArr)
        {
            ap.nElems++;

            switch(bElem.type)
            {
                case Bson.Type.array:
                    recursive(bElem, dimension + 1);
                    break;

                case Bson.Type.null_:
                    rawValues ~= nullValue();
                    break;

                default:
                    Value v = bsonValueToValue(bElem);

                    if(ap.OID == OidType.Unknown)
                    {
                        ap.OID = v.oidType;
                    }
                    else
                    {
                        if(ap.OID != v.oidType)
                            throw new AnswerConvException(
                                    ConvExceptionType.NOT_ARRAY,
                                    "Bson (which used for creating "~ap.OID.to!string~" array) also contains value of type "~v.oidType.to!string,
                                    __FILE__, __LINE__
                                );                    
                    }

                    rawValues ~= rawValue(v);
            }
        }
    }

    recursive(bsonArr, 0);

    // If array empty or contains only NULL values this allows to read it using ::text cast
    if(ap.OID == OidType.Unknown) ap.OID = OidType.Text;

    ArrayHeader_net h;
    h.ndims = nativeToBigEndian(ap.dimsSize.length.to!int);
    h.OID = nativeToBigEndian(ap.OID.to!Oid);

    ubyte[] ret;
    ret ~= (cast(ubyte*) &h)[0 .. h.sizeof];

    foreach(i; 0 .. ap.dimsSize.length)
    {
        Dim_net dim;
        dim.dim_size = nativeToBigEndian(ap.dimsSize[i]);
        dim.lbound = nativeToBigEndian!int(1);

        ret ~= (cast(ubyte*) &dim)[0 .. dim.sizeof];
    }

    ret ~= rawValues;

    return Value(ret, ap.OID.oidType2arrayType, false, ValueFormat.BINARY);
}

unittest
{
    {
        Bson bsonArray = Bson(
            [Bson(123), Bson(155), Bson(null), Bson(0), Bson(null)]
        );

        Value v = bsonToValue(bsonArray);

        assert(v.isSupportedArray);
        assert(v.toBson == bsonArray);
    }

    {
        Bson bsonArray = Bson([
            Bson([Bson(123), Bson(155), Bson(null)]),
            Bson([Bson(0), Bson(null), Bson(155)])
        ]);

        Value v = bsonToValue(bsonArray);

        assert(v.isSupportedArray);
        assert(v.toBson == bsonArray);
    }

    {
        Bson bsonArray = Bson([
            Bson([Bson(123), Bson(155)]),
            Bson([Bson(0)])
        ]);

        bool exceptionFlag = false;

        try
            bsonToValue(bsonArray);
        catch(AnswerConvException e)
        {
            if(e.type == ConvExceptionType.NOT_ARRAY)
                exceptionFlag = true;
        }

        assert(exceptionFlag);
    }
}

OidType oidType2arrayType(OidType type)
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
            throw new AnswerConvException( // TODO: rename it to ValueConvException and move to value.d
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format "~type.to!(immutable(char)[])~" doesn't supported by Bson array to Value converter",
                    __FILE__, __LINE__
                );
    }
}
