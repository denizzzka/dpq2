module dpq2.types.from_bson;

@trusted:

import dpq2;
import vibe.data.bson;
import std.bitmanip: nativeToBigEndian;

/// Default type will be used for NULL value and for array without detected type
Value bsonToValue(Bson v, OidType defaultType = OidType.Unknown)
{
    if(v.type == Bson.Type.array)
        return bsonArrayToValue(v, defaultType);
    else
        return bsonValueToValue(v, defaultType);
}

private:

Value bsonValueToValue(Bson v, OidType defaultType)
{
    Value ret;

    with(Bson.Type)
    switch(v.type)
    {
        case null_:
            ret = Value(ValueFormat.BINARY, defaultType);
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

    {
        Value v = bsonToValue(Bson.emptyArray);
    }
}

Value bsonArrayToValue(ref Bson bsonArr, OidType defaultType)
{
    if(bsonArr.length == 0)
    {
        // Special case: empty array
        // ValueFormat.TEXT because type of array isn't known -
        // this gives an opportunity to detect type of array by Postgres
        return Value(ValueFormat.TEXT, OidType.Unknown);
    }

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
    ubyte[][] rawValues;

    void recursive(ref Bson bsonArr, int dimension)
    {
        if(dimension > ap.dimsSize.length)
            ap.dimsSize ~= bsonArr.length.to!int;

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
                    Value v = bsonValueToValue(bElem, defaultType);

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

    recursive(bsonArr, 1);

    if(ap.OID == OidType.Unknown) ap.OID = defaultType;

    ArrayHeader_net h;
    h.ndims = nativeToBigEndian(ap.dimsSize.length.to!int);
    h.OID = nativeToBigEndian(ap.OID.to!Oid);

    ubyte[] r; // TODO: rename to ret
    r ~= (cast(ubyte*) &h)[0 .. h.sizeof];

    foreach(i; 0 .. ap.dimsSize.length)
    {
        Dim_net dim;
        dim.dim_size = nativeToBigEndian(ap.dimsSize[i]);
        dim.lbound = nativeToBigEndian!int(1);

        r ~= (cast(ubyte*) &dim)[0 .. dim.sizeof];
    }

    foreach(ref v; rawValues)
    {
        r ~= v;
    }

    return Value(r, ap.OID.oidType2arrayType, false, ValueFormat.BINARY);
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
