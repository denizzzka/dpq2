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
bool isNativeNumeric(OidTypes t)
{
    OidTypes[] valid = [
//            Int8,
//            Int2
        ];

    return false;
}

unittest
{
    assert(isNativeNumeric(OidTypes.Int8));
}

private enum ValueType
{
    NativeNumeric,
    NativeString, /// strings, bytea
    Boolean,
    Other
}
alias V = ValueType;

private struct Attributes
{
    Oid oid;
    ValueType type;
}
alias A = Attributes;

enum OidTypes : A
{
    Bool = A(16, V.Boolean),
    ByteArray = A(17, V.NativeString),
    Char = A(18, V.Other),
    Name = A(19, V.Other),
    Int8 = A(20, V.NativeNumeric),
    Int2 = A(21, V.NativeNumeric),
    Int2Vector = A(22, V.Other),
    Int4 = A(23, V.NativeNumeric),
    RegProc = A(24, V.Other),
    Text = A(25, V.NativeString),
    Oid = A(26, V.Other),
    Tid = A(27, V.Other),
    Xid = A(28, V.Other),
    Cid = A(29, V.Other),
    OidVector = A(30, V.Other),

    AccessControlList = A(1033, V.Other),
    TypeCatalog = A(71, V.Other),
    AttributeCatalog = A(75, V.Other),
    ProcCatalog = A(81, V.Other),
    ClassCatalog = A(83, V.Other),
    
    Json = A(114, V.Other),
    Xml = A(142, V.Other),
    NodeTree = A(194, V.Other),
    StorageManager = A(210, V.Other),
    
    Point = A(600, V.Other),
    LineSegment = A(601, V.Other),
    Path = A(602, V.Other),
    Box = A(603, V.Other),
    Polygon = A(604, V.Other),
    Line = A(628, V.Other),
    
    Float4 = A(700, V.NativeNumeric),
    Float8 = A(701, V.NativeNumeric),
    AbsTime = A(702, V.Other),
    RelTime = A(703, V.Other),
    Interval = A(704, V.Other),
    Unknown = A(705, V.Other),
    
    Circle = A(718, V.Other),
    Money = A(790, V.Other),
    MacAddress = A(829, V.Other),
    HostAddress = A(869, V.Other),
    NetworkAddress = A(650, V.Other),
    
    FixedString = A(1042, V.Other),
    VariableString = A(1043, V.Other),
    
    Date = A(1082, V.Other),
    Time = A(1083, V.Other),
    TimeStamp = A(1114, V.Other),
    TimeStampWithZone = A(1184, V.Other),
    TimeInterval = A(1186, V.Other),
    TimeWithZone = A(1266, V.Other),
    
    FixedBitString = A(1560, V.Other),
    VariableBitString = A(1562, V.Other),
    
    Numeric = A(1700, V.Other),
    RefCursor = A(1790, V.Other),
    RegProcWithArgs = A(2202, V.Other),
    RegOperator = A(2203, V.Other),
    RegOperatorWithArgs = A(2204, V.Other),
    RegClass = A(2205, V.Other),
    RegType = A(2206, V.Other),
    
    UUID = A(2950, V.Other),
    TSVector = A(3614, V.Other),
    GTSVector = A(3642, V.Other),
    TSQuery = A(3615, V.Other),
    RegConfig = A(3734, V.Other),
    RegDictionary = A(3769, V.Other),
    TXidSnapshot = A(2970, V.Other),
    
    Int4Range = A(3904, V.Other),
    NumRange = A(3906, V.Other),
    TimeStampRange = A(3908, V.Other),
    TimeStampWithZoneRange = A(3910, V.Other),
    DateRange = A(3912, V.Other),
    Int8Range = A(3926, V.Other),
    
    // Arrays
    BoolArray = A(1000, V.Boolean),
    ByteArrayArray = A(1001, V.NativeString),
    CharArray = A(1002, V.Other),
    NameArray = A(1003, V.Other),
    Int2Array = A(1005, V.NativeNumeric),
    Int2VectorArray = A(1006, V.Other),
    Int4Array = A(1007, V.NativeNumeric),
    RegProcArray = A(1008, V.Other),
    TextArray = A(1009, V.NativeString),
    OidArray  = A(1028, V.Other),
    TidArray = A(1010, V.Other),
    XidArray = A(1011, V.Other),
    CidArray = A(1012, V.Other),
    OidVectorArray = A(1013, V.Other),
    FixedStringArray = A(1014, V.Other),
    VariableStringArray = A(1015, V.Other),
    Int8Array = A(1016, V.NativeNumeric),
    PointArray = A(1017, V.Other),
    LineSegmentArray = A(1018, V.Other),
    PathArray = A(1019, V.Other),
    BoxArray = A(1020, V.Other),
    Float4Array = A(1021, V.NativeNumeric),
    Float8Array = A(1022, V.NativeNumeric),
    AbsTimeArray = A(1023, V.Other),
    RelTimeArray = A(1024, V.Other),
    IntervalArray = A(1025, V.Other),
    PolygonArray = A(1027, V.Other),
    AccessControlListArray = A(1034, V.Other),
    MacAddressArray = A(1040, V.Other),
    HostAdressArray = A(1041, V.Other),
    NetworkAdressArray = A(651, V.Other),
    CStringArray = A(1263, V.Other),
    TimeStampArray = A(1115, V.Other),
    DateArray = A(1182, V.Other),
    TimeArray = A(1183, V.Other),
    TimeStampWithZoneArray = A(1185, V.Other),
    TimeIntervalArray = A(1187, V.Other),
    NumericArray = A(1231, V.Other),
    TimeWithZoneArray = A(1270, V.Other),
    FixedBitStringArray = A(1561, V.Other),
    VariableBitStringArray = A(1563, V.Other),
    RefCursorArray = A(2201, V.Other),
    RegProcWithArgsArray = A(2207, V.Other),
    RegOperatorArray = A(2208, V.Other),
    RegOperatorWithArgsArray = A(2209, V.Other),
    RegClassArray = A(2210, V.Other),
    RegTypeArray = A(2211, V.Other),
    UUIDArray = A(2951, V.Other),
    TSVectorArray = A(3643, V.Other),
    GTSVectorArray = A(3644, V.Other),
    TSQueryArray = A(3645, V.Other),
    RegConfigArray = A(3735, V.Other),
    RegDictionaryArray = A(3770, V.Other),
    TXidSnapshotArray = A(2949, V.Other),
    Int4RangeArray = A(3905, V.Other),
    NumRangeArray = A(3907, V.Other),
    TimeStampRangeArray = A(3909, V.Other),
    TimeStampWithZoneRangeArray = A(3911, V.Other),
    DateRangeArray = A(3913, V.Other),
    Int8RangeArray = A(3927, V.Other),
    
    // Pseudo types
    Record = A(2249, V.Other),
    RecordArray = A(2287, V.Other),
    CString = A(2275, V.Other),
    AnyVoid = A(2276, V.Other),
    AnyArray = A(2277, V.Other),
    Void = A(2278, V.Other),
    Trigger = A(2279, V.Other),
    EventTrigger = A(3838, V.Other),
    LanguageHandler = A(2280, V.Other),
    Internal = A(2281, V.Other),
    Opaque = A(2282, V.Other),
    AnyElement = A(2283, V.Other),
    AnyNoArray = A(2776, V.Other),
    AnyEnum = A(3500, V.Other),
    FDWHandler = A(3115, V.Other),
    AnyRange = A(3831, V.Other)
}
