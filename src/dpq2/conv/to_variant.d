///

module dpq2.conv.to_variant;

version(NO_VARIANT) {
/* Without std.variant dpq2 compiles significantly faster, and often the
* ability explore unknown database schemas is not needed, removing the need
* for a Variant type.
*/
} else {

import dpq2.value;
import dpq2.oids: OidType;
import dpq2.result: ArrayProperties;
import dpq2.conv.inet: InetAddress, CidrAddress;
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

    template retArray__(NativeT)
    {
        /*
            Variant storage haven't heuristics to understand
            what array elements can contain NULLs. So, to
            simplify things, if declared that cell itself is
            not nullable then we decease that array elements
            also can't contain NULL values
        */
        static if(isNullablePayload)
            alias ArrType = Nullable!NativeT;
        else
            alias ArrType = NativeT;

        auto retArray__() @trusted
        {
            if(isNullablePayload && v.isNull)
            {
                /*
                    One-dimensional array return is used here only to
                    highlight that the value contains an array. For
                    NULL cell we can determine only its type, but not
                    the number of dimensions
                */
                return Variant(
                    Nullable!(ArrType[]).init
                );
            }

            import dpq2.conv.arrays: ab = binaryValueAs;

            const ap = ArrayProperties(v);

            switch(ap.dimsSize.length)
            {
                case 0: return Variant(v.ab!(ArrType[])); // PG can return zero-dimensional arrays
                case 1: return Variant(v.ab!(ArrType[]));
                case 2: return Variant(v.ab!(ArrType[][]));
                case 3: return Variant(v.ab!(ArrType[][][]));
                case 4: return Variant(v.ab!(ArrType[][][][]));
                default: throw new ValueConvException(
                    ConvExceptionType.DIMENSION_MISMATCH,
                    "Attempt to convert an array of dimension "~ap.dimsSize.length.to!string~" to type Variant: dimensions greater than 4 are not supported"
                );
            }
        }
    }

    with(OidType)
    switch(v.oidType)
    {
        case Bool:      return retVariant!PGboolean;
        case BoolArray: return retArray__!PGboolean;

        case Int2:      return retVariant!short;
        case Int2Array: return retArray__!short;

        case Int4:      return retVariant!int;
        case Int4Array: return retArray__!int;

        case Int8:      return retVariant!long;
        case Int8Array: return retArray__!long;

        case Float4:        return retVariant!float;
        case Float4Array:   return retArray__!float;

        case Float8:        return retVariant!double;
        case Float8Array:   return retArray__!double;

        case Numeric:
        case Text:
        case FixedString:
        case VariableString:
            return retVariant!string;

        case NumericArray:
        case TextArray:
        case FixedStringArray:
        case VariableStringArray:
            return retArray__!string;

        case ByteArray: return retVariant!PGbytea;

        case UUID:      return retVariant!PGuuid;
        case UUIDArray: return retArray__!PGuuid;

        case Date:      return retVariant!PGdate;
        case DateArray: return retArray__!PGdate;

        case HostAddress:       return retVariant!InetAddress;
        case HostAddressArray:  return retArray__!InetAddress;

        case NetworkAddress:        return retVariant!CidrAddress;
        case NetworkAddressArray:   return retArray__!CidrAddress;

        case Time:      return retVariant!PGtime_without_time_zone;
        case TimeArray: return retArray__!PGtime_without_time_zone;

        case TimeWithZone:      return retVariant!PGtime_with_time_zone;
        case TimeWithZoneArray: return retArray__!PGtime_with_time_zone;

        case TimeStamp:         return retVariant!PGtimestamp;
        case TimeStampArray:    return retArray__!PGtimestamp;

        case TimeStampWithZone:         return retVariant!PGtimestamptz;
        case TimeStampWithZoneArray:    return retArray__!PGtimestamptz;

        case TimeInterval:         return retVariant!PGinterval;

        case Json:
        case Jsonb:
            return retVariant!VibeJson;

        case JsonArray:
        case JsonbArray:
            return retArray__!VibeJson;

        case Line:      return retVariant!(geom.Line);
        case LineArray: return retArray__!(geom.Line);

        default:
            throw new ValueConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format of the column ("~to!(immutable(char)[])(v.oidType)~") doesn't supported by Value to Variant converter",
                    __FILE__, __LINE__
                );
    }
}
}
