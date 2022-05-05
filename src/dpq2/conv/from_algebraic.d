///
module dpq2.conv.from_algebraic;

import dpq2.value: Value;
import dpq2.oids: OidType;
//~ import dpq2.result: ArrayProperties;
//~ import dpq2.conv.to_d_types;
//~ import dpq2.conv.numeric: rawValueToNumeric;
//~ import dpq2.conv.time: TimeStampUTC;
//~ static import geom = dpq2.conv.geometric;
//~ import std.bitmanip: bigEndianToNative, BitArray;
//~ import std.datetime: SysTime, dur, TimeZone, UTC;
//~ import std.conv: to;
//~ import std.typecons: Nullable;
//~ import std.uuid;
//~ import std.sumtype: SumType;
//~ import vibe.data.json: VibeJson = Json;

Value algebraicToValue(alias autoVisitTpl, TAlgebraic)(TAlgebraic alg)
{
    import dpq2.conv.from_d_types: toValue;

    return autoVisitTpl!(
        //TODO: reduce copy-and-paste
        (bool v) => v.toValue,
        (int v) => v.toValue,
        (long v) => v.toValue,
        (float v) => v.toValue,
        (string v) => v.toValue,
    )(alg);
}

//TODO: move to integration tests
unittest
{
    import mir.algebraic;
    import dpq2.conv.to_d_types: as;

    Variant!(int, float) variant;

    variant = 123;
    auto r = variant.algebraicToValue!autoVisit;
    assert(r.as!int == 123);

    //~ variant = "abc";
    //~ r = variant.algebraicToValue!optionalVisit;
    //~ assert(r.as!string == "abc");
}
