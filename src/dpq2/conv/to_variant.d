///
module dpq2.conv.to_variant;

import dpq2.value;
import dpq2.oids: OidType;
import dpq2.result: ArrayProperties;
import dpq2.conv.to_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
import dpq2.conv.time: TimeStampUTC;
static import geom = dpq2.conv.geometric;
import std.bitmanip: bigEndianToNative, BitArray;
import std.datetime: SysTime, dur, TimeZone, UTC;
import std.conv: to;
import std.typecons: Nullable;
import std.uuid;
import std.variant: Variant;
import vibe.data.json: VibeJson = Json;

//TODO: isNullablePayload should be runtime argument
///
Variant toVariant(bool isNullablePayload = true)(in Value v) @safe
{
    auto getNative(T)()
    if(!is(T == Variant))
    {
        static if(isNullablePayload)
        {
            Nullable!T ret;

            if (v.isNull)
                return ret;

            ret = v.as!T;

            return ret;
        }
        else
        {
            return v.as!T;
        }
    }

    Variant retVariant(T)() @trusted
    {
        return Variant(getNative!T);
    }

    if(v.format == ValueFormat.TEXT)
        return retVariant!string;

    //~ if(v.isSupportedArray)
        //~ return arrayValueToBson(v);
    //~ else
        //~ return rawValueToBson(v);


//~ import std.typecons;

//~ with(OidType)
//~ Tuple!
//~ (
    //~ PGboolean, bool,
//~ ) variantMapping;

    with(OidType)
    switch(v.oidType)
    {
        mixin(CaseMap!(BoolArray, bool[]));

        case Bool: return retVariant!PGboolean;
        case Int2: return retVariant!short;
        case Int4: return retVariant!int;
        //~ CaseMap!("Int4Array", int[]);
        case Int8: return retVariant!long;
        case Float4: return retVariant!float;
        case Float8: return retVariant!double;

        case Numeric:
        case Text:
        case FixedString:
        case VariableString:
            return retVariant!string;

        case ByteArray: return retVariant!PGbytea;
        case UUID: return retVariant!PGuuid;
        case Date: return retVariant!PGdate;
        case Time: return retVariant!PGtime_without_time_zone;
        case TimeStamp: return retVariant!PGtimestamp;
        case TimeStampWithZone: return retVariant!PGtimestamptz;

        case Json:
        case Jsonb:
            return retVariant!VibeJson;

        case Line: return retVariant!(geom.Line);

        default:
            throw new ValueConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format of the column ("~to!(immutable(char)[])(v.oidType)~") doesn't supported by Value to Variant converter",
                    __FILE__, __LINE__
                );
    }
}

private template CaseMap(OidType oid, NativeT)
{
    import std.conv: to;

    enum sss = typeid(NativeT);

    string CaseMap = `case `~oid.to!string~`: return retVariant!`~sss~`;`;
}
