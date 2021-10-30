///
module dpq2.conv.to_variant;

import dpq2.value;
import dpq2.oids: OidType;
import dpq2.result: ArrayProperties;
import dpq2.conv.to_d_types;
import dpq2.conv.numeric: rawValueToNumeric;
import dpq2.conv.time: TimeStampUTC;
import std.uuid;
import std.datetime: SysTime, dur, TimeZone, UTC;
import std.bitmanip: bigEndianToNative, BitArray;
import std.conv: to;
import std.variant: Variant;

///
Variant toVariant(in Value v) /* FIXME: pure? */
{
    if(v.format == ValueFormat.TEXT)
    {
        immutable text = v.valueAsString;

        return Variant(text);
    }

    Variant res;

    with(OidType)
    switch(v.oidType)
    {
        case OidType.Bool:
            res = v.as!PGboolean;
            break;

        //~ case Int2:
            //~ auto n = v.tunnelForBinaryValueAsCalls!PGsmallint.to!int;
            //~ res = Bson(n);
            //~ break;

        //~ case Int4:
            //~ int n = v.tunnelForBinaryValueAsCalls!PGinteger;
            //~ res = Bson(n);
            //~ break;

        //~ case Int8:
            //~ long n = v.tunnelForBinaryValueAsCalls!PGbigint;
            //~ res = Bson(n);
            //~ break;

        //~ case Float8:
            //~ double n = v.tunnelForBinaryValueAsCalls!PGdouble_precision;
            //~ res = Bson(n);
            //~ break;

        //~ case Numeric:
            //~ res = Bson(rawValueToNumeric(v.data));
            //~ break;

        //~ case Text:
        //~ case FixedString:
        //~ case VariableString:
            //~ res = Bson(v.valueAsString);
            //~ break;

        //~ case ByteArray:
            //~ auto b = BsonBinData(BsonBinData.Type.userDefined, v.data.idup);
            //~ res = Bson(b);
            //~ break;

        //~ case UUID:
            //~ // See: https://github.com/vibe-d/vibe.d/issues/2161
            //~ // res = Bson(v.tunnelForBinaryValueAsCalls!PGuuid);
            //~ res = serializeToBson(v.tunnelForBinaryValueAsCalls!PGuuid);
            //~ break;

        //~ case TimeStampWithZone:
            //~ auto ts = v.tunnelForBinaryValueAsCalls!TimeStampUTC;
            //~ auto time = BsonDate(SysTime(ts.dateTime, UTC()));
            //~ long usecs = ts.fracSec.total!"usecs";
            //~ res = Bson(["time": Bson(time), "usecs": Bson(usecs)]);
            //~ break;

        //~ case Json:
        //~ case Jsonb:
            //~ vibe.data.json.Json json = v.tunnelForBinaryValueAsCalls!PGjson;
            //~ res = Bson(json);
            //~ break;

        default:
            throw new ValueConvException(
                    ConvExceptionType.NOT_IMPLEMENTED,
                    "Format of the column ("~to!(immutable(char)[])(v.oidType)~") doesn't supported by Value to Variant converter",
                    __FILE__, __LINE__
                );
    }

    return res;
}
