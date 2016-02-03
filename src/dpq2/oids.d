/**
*   PostgreSQL major types oids.
*
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module dpq2.oids;

import derelict.pq.pq: Oid;

/// Is Oid means native integer or decimal value?
/// TODO: remove it
bool isNativeNumeric(OidType t)
{
    return t.nativeType == ValueType.NativeNumeric;
}

unittest
{
    assert(isNativeNumeric(OidType.Int8));
}

OidType oid2oidType(Oid oid) pure
{
    OidType res = cast(OidType)(oid);

    assert(res.oid == oid);

    return res;
}

private enum ValueType
{
    NativeNumeric,
    NativeString, /// strings, bytea
    Boolean,
    unsupported
}
alias V = ValueType;

private struct Attributes
{
    Oid oid;
    ValueType nativeType;
}
alias A = Attributes;

enum OidType : A
{
    Bool = A(16, V.Boolean),
    ByteArray = A(17, V.NativeString),
    Char = A(18, V.unsupported),
    Name = A(19, V.unsupported),
    Int8 = A(20, V.NativeNumeric),
    Int2 = A(21, V.NativeNumeric),
    Int2Vector = A(22, V.unsupported),
    Int4 = A(23, V.NativeNumeric),
    RegProc = A(24, V.unsupported),
    Text = A(25, V.NativeString),
    Oid = A(26, V.unsupported),
    Tid = A(27, V.unsupported),
    Xid = A(28, V.unsupported),
    Cid = A(29, V.unsupported),
    OidVector = A(30, V.unsupported),

    AccessControlList = A(1033, V.unsupported),
    TypeCatalog = A(71, V.unsupported),
    AttributeCatalog = A(75, V.unsupported),
    ProcCatalog = A(81, V.unsupported),
    ClassCatalog = A(83, V.unsupported),
    
    Json = A(114, V.unsupported),
    Xml = A(142, V.unsupported),
    NodeTree = A(194, V.unsupported),
    StorageManager = A(210, V.unsupported),
    
    Point = A(600, V.unsupported),
    LineSegment = A(601, V.unsupported),
    Path = A(602, V.unsupported),
    Box = A(603, V.unsupported),
    Polygon = A(604, V.unsupported),
    Line = A(628, V.unsupported),
    
    Float4 = A(700, V.NativeNumeric),
    Float8 = A(701, V.NativeNumeric),
    AbsTime = A(702, V.unsupported),
    RelTime = A(703, V.unsupported),
    Interval = A(704, V.unsupported),
    Unknown = A(705, V.unsupported),
    
    Circle = A(718, V.unsupported),
    Money = A(790, V.unsupported),
    MacAddress = A(829, V.unsupported),
    HostAddress = A(869, V.unsupported),
    NetworkAddress = A(650, V.unsupported),
    
    FixedString = A(1042, V.unsupported),
    VariableString = A(1043, V.unsupported),
    
    Date = A(1082, V.unsupported),
    Time = A(1083, V.unsupported),
    TimeStamp = A(1114, V.unsupported),
    TimeStampWithZone = A(1184, V.unsupported),
    TimeInterval = A(1186, V.unsupported),
    TimeWithZone = A(1266, V.unsupported),
    
    FixedBitString = A(1560, V.unsupported),
    VariableBitString = A(1562, V.unsupported),
    
    Numeric = A(1700, V.unsupported),
    RefCursor = A(1790, V.unsupported),
    RegProcWithArgs = A(2202, V.unsupported),
    RegOperator = A(2203, V.unsupported),
    RegOperatorWithArgs = A(2204, V.unsupported),
    RegClass = A(2205, V.unsupported),
    RegType = A(2206, V.unsupported),
    
    UUID = A(2950, V.unsupported),
    TSVector = A(3614, V.unsupported),
    GTSVector = A(3642, V.unsupported),
    TSQuery = A(3615, V.unsupported),
    RegConfig = A(3734, V.unsupported),
    RegDictionary = A(3769, V.unsupported),
    TXidSnapshot = A(2970, V.unsupported),
    
    Int4Range = A(3904, V.unsupported),
    NumRange = A(3906, V.unsupported),
    TimeStampRange = A(3908, V.unsupported),
    TimeStampWithZoneRange = A(3910, V.unsupported),
    DateRange = A(3912, V.unsupported),
    Int8Range = A(3926, V.unsupported),
    
    // Arrays
    BoolArray = A(1000, V.Boolean),
    ByteArrayArray = A(1001, V.NativeString),
    CharArray = A(1002, V.unsupported),
    NameArray = A(1003, V.unsupported),
    Int2Array = A(1005, V.NativeNumeric),
    Int2VectorArray = A(1006, V.unsupported),
    Int4Array = A(1007, V.NativeNumeric),
    RegProcArray = A(1008, V.unsupported),
    TextArray = A(1009, V.NativeString),
    OidArray  = A(1028, V.unsupported),
    TidArray = A(1010, V.unsupported),
    XidArray = A(1011, V.unsupported),
    CidArray = A(1012, V.unsupported),
    OidVectorArray = A(1013, V.unsupported),
    FixedStringArray = A(1014, V.unsupported),
    VariableStringArray = A(1015, V.unsupported),
    Int8Array = A(1016, V.NativeNumeric),
    PointArray = A(1017, V.unsupported),
    LineSegmentArray = A(1018, V.unsupported),
    PathArray = A(1019, V.unsupported),
    BoxArray = A(1020, V.unsupported),
    Float4Array = A(1021, V.NativeNumeric),
    Float8Array = A(1022, V.NativeNumeric),
    AbsTimeArray = A(1023, V.unsupported),
    RelTimeArray = A(1024, V.unsupported),
    IntervalArray = A(1025, V.unsupported),
    PolygonArray = A(1027, V.unsupported),
    AccessControlListArray = A(1034, V.unsupported),
    MacAddressArray = A(1040, V.unsupported),
    HostAdressArray = A(1041, V.unsupported),
    NetworkAdressArray = A(651, V.unsupported),
    CStringArray = A(1263, V.unsupported),
    TimeStampArray = A(1115, V.unsupported),
    DateArray = A(1182, V.unsupported),
    TimeArray = A(1183, V.unsupported),
    TimeStampWithZoneArray = A(1185, V.unsupported),
    TimeIntervalArray = A(1187, V.unsupported),
    NumericArray = A(1231, V.unsupported),
    TimeWithZoneArray = A(1270, V.unsupported),
    FixedBitStringArray = A(1561, V.unsupported),
    VariableBitStringArray = A(1563, V.unsupported),
    RefCursorArray = A(2201, V.unsupported),
    RegProcWithArgsArray = A(2207, V.unsupported),
    RegOperatorArray = A(2208, V.unsupported),
    RegOperatorWithArgsArray = A(2209, V.unsupported),
    RegClassArray = A(2210, V.unsupported),
    RegTypeArray = A(2211, V.unsupported),
    UUIDArray = A(2951, V.unsupported),
    TSVectorArray = A(3643, V.unsupported),
    GTSVectorArray = A(3644, V.unsupported),
    TSQueryArray = A(3645, V.unsupported),
    RegConfigArray = A(3735, V.unsupported),
    RegDictionaryArray = A(3770, V.unsupported),
    TXidSnapshotArray = A(2949, V.unsupported),
    Int4RangeArray = A(3905, V.unsupported),
    NumRangeArray = A(3907, V.unsupported),
    TimeStampRangeArray = A(3909, V.unsupported),
    TimeStampWithZoneRangeArray = A(3911, V.unsupported),
    DateRangeArray = A(3913, V.unsupported),
    Int8RangeArray = A(3927, V.unsupported),
    
    // Pseudo types
    Record = A(2249, V.unsupported),
    RecordArray = A(2287, V.unsupported),
    CString = A(2275, V.unsupported),
    AnyVoid = A(2276, V.unsupported),
    AnyArray = A(2277, V.unsupported),
    Void = A(2278, V.unsupported),
    Trigger = A(2279, V.unsupported),
    EventTrigger = A(3838, V.unsupported),
    LanguageHandler = A(2280, V.unsupported),
    Internal = A(2281, V.unsupported),
    Opaque = A(2282, V.unsupported),
    AnyElement = A(2283, V.unsupported),
    AnyNoArray = A(2776, V.unsupported),
    AnyEnum = A(3500, V.unsupported),
    FDWHandler = A(3115, V.unsupported),
    AnyRange = A(3831, V.unsupported)
}
