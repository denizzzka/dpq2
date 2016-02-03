/**
*   PostgreSQL major types oids.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.oids;

import derelict.pq.pq: Oid;

OidType oid2oidType(Oid oid) pure
{
    return cast(OidType)(oid);
}

package enum NativeType
{
    NativeNumeric,
    NativeString, /// strings, bytea
    Boolean,
    unsupported
}

private struct Attributes
{
    Oid oid;
    NativeType nativeType;
}

bool isArray(OidType t) pure
{
    with(OidType)
    switch(t)
    {
        case BoolArray:
        case ByteArrayArray:
        case CharArray:
        case NameArray:
        case Int2Array:
        case Int2VectorArray:
        case Int4Array:
        case RegProcArray:
        case TextArray:
        case OidArray:
        case TidArray:
        case XidArray:
        case CidArray:
        case OidVectorArray:
        case FixedStringArray:
        case VariableStringArray:
        case Int8Array:
        case PointArray:
        case LineSegmentArray:
        case PathArray:
        case BoxArray:
        case Float4Array:
        case Float8Array:
        case AbsTimeArray:
        case RelTimeArray:
        case IntervalArray:
        case PolygonArray:
        case AccessControlListArray:
        case MacAddressArray:
        case HostAdressArray:
        case NetworkAdressArray:
        case CStringArray:
        case TimeStampArray:
        case DateArray:
        case TimeArray:
        case TimeStampWithZoneArray:
        case TimeIntervalArray:
        case NumericArray:
        case TimeWithZoneArray: 
        case FixedBitStringArray:
        case VariableBitStringArray:
        case RefCursorArray:
        case RegProcWithArgsArray:
        case RegOperatorArray:
        case RegOperatorWithArgsArray:
        case RegClassArray:
        case RegTypeArray:
        case UUIDArray:
        case TSVectorArray:
        case GTSVectorArray:
        case TSQueryArray:
        case RegConfigArray:
        case RegDictionaryArray:
        case TXidSnapshotArray:
        case Int4RangeArray:
        case NumRangeArray:
        case TimeStampRangeArray:
        case TimeStampWithZoneRangeArray:
        case DateRangeArray:
        case Int8RangeArray:
            return true;
        default:
            break;
    }

    return false;
}

enum OidType : Oid
{
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
