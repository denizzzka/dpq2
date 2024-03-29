///
module dpq2.conv.from_bson;

import dpq2.value;
import dpq2.oids;
import dpq2.result: ArrayProperties, ArrayHeader_net, Dim_net;
import dpq2.conv.from_d_types;
import dpq2.conv.to_d_types;
import vibe.data.bson;
import std.bitmanip: nativeToBigEndian;
import std.conv: to;

/// Default type will be used for NULL value and for array without detected type
Value bsonToValue(Bson v, OidType defaultType = OidType.Undefined)
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

        case Bson.Type.object:
            ret = v.toJson.toString.toValue;
            ret.oidType = OidType.Json;
            break;

        case bool_:
            ret = v.get!bool.toValue;
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
            throw new ValueConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format "~v.typeInternal.to!(immutable(char)[])~" doesn't supported by Bson to Value converter",
                    __FILE__, __LINE__
                );
    }

    return ret;
}

//TODO: remove when vibe/data/bson.d removes deprecated types names
/// Bson.Type without deprecated items
package enum BsonTypeWODeprecated : ubyte
{
		end        = 0x00,  /// End marker - should never occur explicitly
		double_    = 0x01,  /// A 64-bit floating point value
		string     = 0x02,  /// A UTF-8 string
		object     = 0x03,  /// An object aka. dictionary of string to Bson
		array      = 0x04,  /// An array of BSON values
		binData    = 0x05,  /// Raw binary data (ubyte[])
		undefined  = 0x06,  /// Deprecated
		objectID   = 0x07,  /// BSON Object ID (96-bit)
		bool_      = 0x08,  /// Boolean value
		date       = 0x09,  /// Date value (UTC)
		null_      = 0x0A,  /// Null value
		regex      = 0x0B,  /// Regular expression
		dbRef      = 0x0C,  /// Deprecated
		code       = 0x0D,  /// JaveScript code
		symbol     = 0x0E,  /// Symbol/variable name
		codeWScope = 0x0F,  /// JavaScript code with scope
		int_       = 0x10,  /// 32-bit integer
		timestamp  = 0x11,  /// Timestamp value
		long_      = 0x12,  /// 64-bit integer
		minKey     = 0xff,  /// Internal value
		maxKey     = 0x7f,  /// Internal value
}

package BsonTypeWODeprecated typeInternal(in Bson v)
{
    return cast(BsonTypeWODeprecated) v.type;
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
        Value t = bsonToValue(Bson(true));
        Value f = bsonToValue(Bson(false));

        assert(t.as!bool == true);
        assert(f.as!bool == false);
    }
}

Value bsonArrayToValue(ref Bson bsonArr, OidType defaultType)
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
                throw new ValueConvException(ConvExceptionType.NOT_ARRAY, "Jagged arrays are unsupported", __FILE__, __LINE__);
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
                    Value v = bsonValueToValue(bElem, OidType.Undefined);

                    if(ap.OID == OidType.Undefined)
                    {
                        ap.OID = v.oidType;
                    }
                    else
                    {
                        if(ap.OID != v.oidType)
                            throw new ValueConvException(
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

    if(ap.OID == OidType.Undefined) ap.OID = defaultType.oidConvTo!"element";

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

    return Value(cast(immutable) ret, ap.OID.oidConvTo!"array", false, ValueFormat.BINARY);
}

unittest
{
    import dpq2.conv.to_bson;

    {
        Bson bsonArray = Bson(
            [Bson(123), Bson(155), Bson(null), Bson(0), Bson(null)]
        );

        Value v = bsonToValue(bsonArray);

        assert(v.isSupportedArray);
        assert(v.as!Bson == bsonArray);
    }

    {
        Bson bsonArray = Bson([
            Bson([Bson(123), Bson(155), Bson(null)]),
            Bson([Bson(0), Bson(null), Bson(155)])
        ]);

        Value v = bsonToValue(bsonArray);

        assert(v.isSupportedArray);
        assert(v.as!Bson == bsonArray);
    }

    {
        Bson bsonArray = Bson([
            Bson([Bson(123), Bson(155)]),
            Bson([Bson(0)])
        ]);

        bool exceptionFlag = false;

        try
            bsonToValue(bsonArray);
        catch(ValueConvException e)
        {
            if(e.type == ConvExceptionType.NOT_ARRAY)
                exceptionFlag = true;
        }

        assert(exceptionFlag);
    }
}
