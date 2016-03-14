module dpq2.types.from_bson;

@trusted:

import dpq2;
import vibe.data.bson;
import std.bitmanip: nativeToBigEndian;

/// Default type will be used for NULL values
Value bsonToValue(Bson v, OidType defaultType = OidType.Text)
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

    {
        Value v = bsonToValue(Bson.emptyArray);
    }
}

private Value bsonArrayToValue(ref Bson bsonArr)
{
    if(bsonArr.length == 0)
    {
        // Empty array
        // ValueFormat.TEXT because type of array isn't known -
        // this gives an opportunity to detect type of array by Postgres
        return Value(ValueFormat.TEXT, OidType.Unknown);
    }

    ArrayProperties ap;

    // Detect array type
    foreach(bElem; bsonArr)
    {
        if(bElem.type != Bson.Type.null_ && ap.OID == OidType.Unknown)
        {
            ap.OID = bsonToValue(bElem).oidType;
            break;
        }
    }

    if(ap.OID == OidType.Unknown)
        throw new AnswerConvException(ConvExceptionType.NOT_ARRAY, "Array type unknown", __FILE__, __LINE__);

    ubyte[int.sizeof] nullValue() pure
    {
        return [0xff, 0xff, 0xff, 0xff]; //NULL magic number
    }

    ubyte[] rawValue(Value v) pure
    {
        if(v.isNull)
        {
            return nullValue().dup;
        }
        else
        {
            return v._data.length.to!uint.nativeToBigEndian ~ v._data;
        }
    }

    ubyte[][] values;

    // Fill array
    foreach(bElem; bsonArr)
    {
        if(bElem.type == Bson.Type.null_)
        {
            values ~= nullValue();
        }
        else
        {
            Value v = bsonToValue(bElem);

            if(ap.OID != v.oidType)
                throw new AnswerConvException(
                        ConvExceptionType.NOT_ARRAY,
                        "Bson (which used for creating "~ap.OID.to!string~" array) also contains value of type "~v.oidType.to!string,
                        __FILE__, __LINE__
                    );

            values ~= rawValue(v);
        }

        ap.nElems++;
    }

    ap.dimsSize.length = 1;
    ap.dimsSize[0] = values.length.to!int;

    ArrayHeader_net h;
    h.ndims = nativeToBigEndian(ap.dimsSize.length.to!int);
    h.OID = nativeToBigEndian(cast(Oid) ap.OID);

    Dim_net dim;
    dim.dim_size = nativeToBigEndian(ap.dimsSize[0]);
    dim.lbound = nativeToBigEndian(1);

    ubyte[] r;
    r ~= (cast(ubyte*) &h)[0 .. h.sizeof];
    r ~= (cast(ubyte*) &dim)[0 .. dim.sizeof];

    foreach(ref v; values)
    {
        r ~= v;
    }

    import std.stdio;
    writeln(ap);
    writeln(h);
    writeln(dim);
    writeln(values);
    writeln(r);

    return Value(r, ap.OID.oidType2arrayType, false, ValueFormat.BINARY);
}

unittest
{
    Bson bsonArray = Bson(
        [Bson(123)]//, Bson(456), Bson(null)]
    );

    Value v = bsonToValue(bsonArray);

    import std.stdio;
    writeln(v);
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
            throw new AnswerConvException( // TODO: rename it to ValueConvException and move to value.d
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format "~type.to!(immutable(char)[])~" doesn't supported by Bson array to Value converter",
                    __FILE__, __LINE__
                );
    }
}
