/**
*   PostgreSQL major types oids.
*
*   Copyright: © 2014 DSoftOut
*   Authors: NCrashed <ncrashed@gmail.com>
*/

module dpq2.oids;

@safe:

OidType oid2oidType(Oid oid) pure
{
    static assert(Oid.sizeof == OidType.sizeof);

    return cast(OidType)(oid);
}

OidType oidConvTo(string s)(OidType type)
{
    foreach(ref a; appropriateArrOid)
    {
        static if(s == "array")
        {
            if(a.value == type)
                return a.array;
        }
        else
        static if(s == "element")
        {
            if(a.array == type)
                return a.value;
        }
        else
        static assert(false, "Wrong oidConvTo type "~s);
    }

    import dpq2.exception: AnswerConvException, ConvExceptionType;
    import std.conv: to;

    throw new AnswerConvException( // TODO: rename it to ValueConvException and move to value.d
            ConvExceptionType.NOT_IMPLEMENTED,
            "Conv to "~s~" for type "~type.to!string~" isn't defined",
            __FILE__, __LINE__
        );
}

bool isNativeInteger(OidType t) pure
{
    with(OidType)
    switch(t)
    {
        case Int8:
        case Int2:
        case Int4:
            return true;
        default:
            break;
    }

    return false;
}

bool isNativeFloat(OidType t) pure
{
    with(OidType)
    switch(t)
    {
        case Float4:
        case Float8:
            return true;
        default:
            break;
    }

    return false;
}

package:

private struct AppropriateArrOid
{
    OidType value;
    OidType array;
}

private immutable AppropriateArrOid[] appropriateArrOid;

shared static this()
{
    alias A = AppropriateArrOid;

    with(OidType)
    {
        immutable AppropriateArrOid[] a =
        [
            A(Text, TextArray),
            A(Bool, BoolArray),
            A(Int2, Int2Array),
            A(Int4, Int4Array),
            A(Int8, Int8Array),
            A(Float4, Float4Array),
            A(Float8, Float8Array),
            A(Date, DateArray),
            A(Time, TimeArray),
            A(TimeStampWithZone, TimeStampWithZoneArray),
            A(TimeStamp, TimeStampArray)
        ];

        appropriateArrOid = a;
    }
}

import derelict.pq.pq: Oid;

bool isSupportedArray(OidType t) pure
{
    with(OidType)
    switch(t)
    {
        case BoolArray:
        case ByteArrayArray:
        case CharArray:
        case Int2Array:
        case Int4Array:
        case TextArray:
        case Int8Array:
        case Float4Array:
        case Float8Array:
        case TimeStampArray:
        case TimeStampWithZoneArray:
        case DateArray:
        case TimeArray:
        case TimeWithZoneArray:
        case NumericArray:
        case UUIDArray:
        case JsonArray:
        case JsonbArray:
            return true;
        default:
            break;
    }

    return false;
}

OidType detectOidTypeFromNative(T)()
{
    import std.datetime.date : StdDate = Date, TimeOfDay;
    import std.datetime.systime : SysTime;
    import std.traits : Unqual;
    import dpq2.conv.time: TimeStampWithoutTZ;

    alias UT = Unqual!T;

    with(OidType)
    {
        static if(is(UT == string)){ return Text; } else
        static if(is(UT == ubyte[])){ return ByteArray; } else
        static if(is(UT == bool)){ return Bool; } else
        static if(is(UT == short)){ return Int2; } else
        static if(is(UT == int)){ return Int4; } else
        static if(is(UT == long)){ return Int8; } else
        static if(is(UT == float)){ return Float4; } else
        static if(is(UT == double)){ return Float8; } else
        static if(is(UT == StdDate)){ return Date; } else
        static if(is(UT == TimeOfDay)){ return Time; } else
        static if(is(UT == SysTime)){ return TimeStampWithZone; } else
        static if(is(UT == TimeStampWithoutTZ)){ return TimeStamp; } else

        static assert(false, "Unsupported D type: "~T.stringof);
    }
}

enum OidType : Oid
{
    Undefined = 0,

    Bool = 16,
    ByteArray = 17,
    Char = 18,
    Name = 19,
    Int8 = 20,
    Int2 = 21,
    Int2Vector = 22,
    Int4 = 23,
    RegProc = 24,
    Text = 25,
    Oid = 26,
    Tid = 27,
    Xid = 28,
    Cid = 29,
    OidVector = 30,

    AccessControlList = 1033,
    TypeCatalog = 71,
    AttributeCatalog = 75,
    ProcCatalog = 81,
    ClassCatalog = 83,

    Json = 114,
    Jsonb = 3802,
    Xml = 142,
    NodeTree = 194,
    StorageManager = 210,

    Point = 600,
    LineSegment = 601,
    Path = 602,
    Box = 603,
    Polygon = 604,
    Line = 628,

    Float4 = 700,
    Float8 = 701,
    AbsTime = 702,
    RelTime = 703,
    Interval = 704,
    Unknown = 705,

    Circle = 718,
    Money = 790,
    MacAddress = 829,
    HostAddress = 869,
    NetworkAddress = 650,

    FixedString = 1042,
    VariableString = 1043,

    Date = 1082,
    Time = 1083,
    TimeStamp = 1114,
    TimeStampWithZone = 1184,
    TimeInterval = 1186,
    TimeWithZone = 1266,

    FixedBitString = 1560,
    VariableBitString = 1562,

    Numeric = 1700,
    RefCursor = 1790,
    RegProcWithArgs = 2202,
    RegOperator = 2203,
    RegOperatorWithArgs = 2204,
    RegClass = 2205,
    RegType = 2206,

    UUID = 2950,
    TSVector = 3614,
    GTSVector = 3642,
    TSQuery = 3615,
    RegConfig = 3734,
    RegDictionary = 3769,
    TXidSnapshot = 2970,

    Int4Range = 3904,
    NumRange = 3906,
    TimeStampRange = 3908,
    TimeStampWithZoneRange = 3910,
    DateRange = 3912,
    Int8Range = 3926,

    // Arrays
    XmlArray = 143,
    JsonArray = 3807,
    JsonbArray = 199,
    BoolArray = 1000,
    ByteArrayArray = 1001,
    CharArray = 1002,
    NameArray = 1003,
    Int2Array = 1005,
    Int2VectorArray = 1006,
    Int4Array = 1007,
    RegProcArray = 1008,
    TextArray = 1009,
    OidArray  = 1028,
    TidArray = 1010,
    XidArray = 1011,
    CidArray = 1012,
    OidVectorArray = 1013,
    FixedStringArray = 1014,
    VariableStringArray = 1015,
    Int8Array = 1016,
    PointArray = 1017,
    LineSegmentArray = 1018,
    PathArray = 1019,
    BoxArray = 1020,
    Float4Array = 1021,
    Float8Array = 1022,
    AbsTimeArray = 1023,
    RelTimeArray = 1024,
    IntervalArray = 1025,
    PolygonArray = 1027,
    AccessControlListArray = 1034,
    MacAddressArray = 1040,
    HostAdressArray = 1041,
    NetworkAdressArray = 651,
    CStringArray = 1263,
    TimeStampArray = 1115,
    DateArray = 1182,
    TimeArray = 1183,
    TimeStampWithZoneArray = 1185,
    TimeIntervalArray = 1187,
    NumericArray = 1231,
    TimeWithZoneArray = 1270,
    FixedBitStringArray = 1561,
    VariableBitStringArray = 1563,
    RefCursorArray = 2201,
    RegProcWithArgsArray = 2207,
    RegOperatorArray = 2208,
    RegOperatorWithArgsArray = 2209,
    RegClassArray = 2210,
    RegTypeArray = 2211,
    UUIDArray = 2951,
    TSVectorArray = 3643,
    GTSVectorArray = 3644,
    TSQueryArray = 3645,
    RegConfigArray = 3735,
    RegDictionaryArray = 3770,
    TXidSnapshotArray = 2949,
    Int4RangeArray = 3905,
    NumRangeArray = 3907,
    TimeStampRangeArray = 3909,
    TimeStampWithZoneRangeArray = 3911,
    DateRangeArray = 3913,
    Int8RangeArray = 3927,

    // Pseudo types
    Record = 2249,
    RecordArray = 2287,
    CString = 2275,
    AnyVoid = 2276,
    AnyArray = 2277,
    Void = 2278,
    Trigger = 2279,
    EventTrigger = 3838,
    LanguageHandler = 2280,
    Internal = 2281,
    Opaque = 2282,
    AnyElement = 2283,
    AnyNoArray = 2776,
    AnyEnum = 3500,
    FDWHandler = 3115,
    AnyRange = 3831
}
