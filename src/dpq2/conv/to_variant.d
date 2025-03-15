///
module dpq2.conv.to_variant;

import dpq2.value;
import dpq2.oids: OidType;
import dpq2.result: ArrayProperties;
import dpq2.conv.to_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
static import dpq2.conv.ranges;
static import dpq2.conv.tsearch;
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
        static if(isNullablePayload)
            alias arrType = Nullable!NativeT[];
        else
            alias arrType = NativeT[];

        alias retArray__ = retVariant!arrType;
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

        case Int4Range:         return retVariant!(dpq2.conv.ranges.Int4Range);
        case Int8Range:         return retVariant!(dpq2.conv.ranges.Int8Range);
        case NumRange:          return retVariant!(dpq2.conv.ranges.NumRange);
        case DateRange:         return retVariant!(dpq2.conv.ranges.DateRange);
        case TimeStampRange:    return retVariant!(dpq2.conv.ranges.TsRange);
        case TimeStampWithZoneRange:  return retVariant!(dpq2.conv.ranges.TsTzRange);

        case Int4RangeArray:            return retArray__!(dpq2.conv.ranges.Int4Range);
        case Int8RangeArray:            return retArray__!(dpq2.conv.ranges.Int8Range);
        case NumRangeArray:             return retArray__!(dpq2.conv.ranges.NumRange);
        case DateRangeArray:            return retArray__!(dpq2.conv.ranges.DateRange);
        case TimeStampRangeArray:       return retArray__!(dpq2.conv.ranges.TsRange);
        case TimeStampWithZoneRangeArray:  return retArray__!(dpq2.conv.ranges.TsTzRange);

        case Int4MultiRange:            return retVariant!(dpq2.conv.ranges.Int4MultiRange);
        case Int8MultiRange:            return retVariant!(dpq2.conv.ranges.Int8MultiRange);
        case NumMultiRange:             return retVariant!(dpq2.conv.ranges.NumMultiRange);
        case DateMultiRange:            return retVariant!(dpq2.conv.ranges.DateMultiRange);
        case TimeStampMultiRange:       return retVariant!(dpq2.conv.ranges.TsMultiRange);
        case TimeStampWithZoneMultiRange:  return retVariant!(dpq2.conv.ranges.TsTzMultiRange);

        case Int4MultiRangeArray:               return retArray__!(dpq2.conv.ranges.Int4MultiRange);
        case Int8MultiRangeArray:               return retArray__!(dpq2.conv.ranges.Int8MultiRange);
        case NumMultiRangeArray:                return retArray__!(dpq2.conv.ranges.NumMultiRange);
        case DateMultiRangeArray:               return retArray__!(dpq2.conv.ranges.DateMultiRange);
        case TimeStampMultiRangeArray:          return retArray__!(dpq2.conv.ranges.TsMultiRange);
        case TimeStampWithZoneMultiRangeArray:  return retArray__!(dpq2.conv.ranges.TsTzMultiRange);

        case ByteArray: return retVariant!PGbytea;

        case UUID:      return retVariant!PGuuid;
        case UUIDArray: return retArray__!PGuuid;

        case Date:      return retVariant!PGdate;
        case DateArray: return retArray__!PGdate;

        case Time:      return retVariant!PGtime_without_time_zone;
        case TimeArray: return retArray__!PGtime_without_time_zone;

        case TimeWithZone:      return retVariant!PGtime_with_time_zone;
        case TimeWithZoneArray: return retArray__!PGtime_with_time_zone;

        case TimeStamp:         return retVariant!PGtimestamp;
        case TimeStampArray:    return retArray__!PGtimestamp;

        case TimeStampWithZone:         return retVariant!PGtimestamptz;
        case TimeStampWithZoneArray:    return retArray__!PGtimestamptz;

        case TimeInterval:         return retVariant!PGinterval;

        case TSQuery:         return retVariant!(dpq2.conv.tsearch.TsQuery);
        case TSQueryArray:    return retArray__!(dpq2.conv.tsearch.TsQuery);

        case TSVector:         return retVariant!(dpq2.conv.tsearch.TsVector);
        case TSVectorArray:    return retArray__!(dpq2.conv.tsearch.TsVector);

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
