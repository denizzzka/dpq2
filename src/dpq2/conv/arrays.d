/++
    Module to handle PostgreSQL array types
+/
module dpq2.conv.arrays;

import dpq2.oids : OidType;
import dpq2.value;

import std.traits : isArray, isAssociativeArray;
import std.range : ElementType;
import std.typecons : Nullable;

@safe:

// From array to Value:

template isArrayType(T)
{
    import dpq2.conv.geometric : isValidPolygon;
    import std.traits : Unqual;

    enum isArrayType = isArray!T && !isAssociativeArray!T && !isValidPolygon!T && !is(Unqual!(ElementType!T) == ubyte) && !is(T : string);
}

static assert(isArrayType!(int[]));
static assert(!isArrayType!(int[string]));
static assert(!isArrayType!(ubyte[]));
static assert(!isArrayType!(string));

/// Converts dynamic or static array of supported types to the coresponding PG array type value
Value toValue(T)(auto ref T v)
if (isArrayType!T)
{
    import dpq2.oids : detectOidTypeFromNative, oidConvTo;
    import std.array : Appender;
    import std.bitmanip : nativeToBigEndian;
    import std.exception : enforce;
    import std.format : format;
    import std.traits : isStaticArray;

    static void writeItem(R, T)(ref R output, T item)
    {
        static if (is(T == ArrayElementType!T))
        {
            import dpq2.conv.from_d_types : toValue;

            static immutable ubyte[] nullVal = [255,255,255,255]; //special length value to indicate null value in array
            auto v = item.toValue; // TODO: Direct serialization to buffer would be more effective
            if (v.isNull) output ~= nullVal;
            else
            {
                auto l = v._data.length;
                enforce(l < uint.max, format!"Array item can't be larger than %s"(uint.max-1)); // -1 because uint.max is a null special value
                output ~= (cast(uint)l).nativeToBigEndian[]; // write item length
                output ~= v._data;
            }
        }
        else
        {
            foreach (i; item)
                writeItem(output, i);
        }
    }

    alias ET = ArrayElementType!T;
    enum dimensions = arrayDimensions!T;
    enum elemOid = detectOidTypeFromNative!ET;
    auto arrOid = oidConvTo!("array")(elemOid); //TODO: check in CT for supported array types

    // check for null element
    static if (__traits(compiles, v[0] is null) || is(ET == Nullable!R,R))
    {
        bool hasNull = false;
        foreach (vv; v)
        {
            static if (is(ET == Nullable!R,R)) hasNull = vv.isNull;
            else hasNull = vv is null;

            if (hasNull) break;
        }
    }
    else bool hasNull = false;

    auto buffer = Appender!(immutable(ubyte)[])();

    // write header
    buffer ~= dimensions.nativeToBigEndian[]; // write number of dimensions
    buffer ~= (hasNull ? 1 : 0).nativeToBigEndian[]; // write null element flag
    buffer ~= (cast(int)elemOid).nativeToBigEndian[]; // write elements Oid
    size_t[dimensions] dlen = getDimensionsLengths(v);

    static foreach (d; 0..dimensions)
    {
        buffer ~= (cast(uint)dlen[d]).nativeToBigEndian[]; // write number of dimensions
        buffer ~= 1.nativeToBigEndian[]; // write left bound index (PG indexes from 1 implicitly)
    }

    //write data
    foreach (i; v) writeItem(buffer, i);

    return Value(buffer.data, arrOid);
}

@system unittest
{
    import dpq2.conv.to_d_types : as;
    import dpq2.result : asArray;

    {
        int[3][2][1] arr = [[[1,2,3], [4,5,6]]];

        assert(arr[0][0][2] == 3);
        assert(arr[0][1][2] == 6);

        auto v = arr.toValue();
        assert(v.oidType == OidType.Int4Array);

        auto varr = v.asArray;
        assert(varr.length == 6);
        assert(varr.getValue(0,0,2).as!int == 3);
        assert(varr.getValue(0,1,2).as!int == 6);
    }

    {
        int[][][] arr = [[[1,2,3], [4,5,6]]];

        assert(arr[0][0][2] == 3);
        assert(arr[0][1][2] == 6);

        auto v = arr.toValue();
        assert(v.oidType == OidType.Int4Array);

        auto varr = v.asArray;
        assert(varr.length == 6);
        assert(varr.getValue(0,0,2).as!int == 3);
        assert(varr.getValue(0,1,2).as!int == 6);
    }

    {
        string[] arr = ["foo", "bar", "baz"];

        auto v = arr.toValue();
        assert(v.oidType == OidType.TextArray);

        auto varr = v.asArray;
        assert(varr.length == 3);
        assert(varr[0].as!string == "foo");
        assert(varr[1].as!string == "bar");
        assert(varr[2].as!string == "baz");
    }

    {
        string[] arr = ["foo", null, "baz"];

        auto v = arr.toValue();
        assert(v.oidType == OidType.TextArray);

        auto varr = v.asArray;
        assert(varr.length == 3);
        assert(varr[0].as!string == "foo");
        assert(varr[1].as!string == "");
        assert(varr[2].as!string == "baz");
    }

    {
        string[] arr;

        auto v = arr.toValue();
        assert(v.oidType == OidType.TextArray);
        assert(!v.isNull);

        auto varr = v.asArray;
        assert(varr.length == 0);
    }

    {
        Nullable!string[] arr = [Nullable!string("foo"), Nullable!string.init, Nullable!string("baz")];

        auto v = arr.toValue();
        assert(v.oidType == OidType.TextArray);

        auto varr = v.asArray;
        assert(varr.length == 3);
        assert(varr[0].as!string == "foo");
        assert(varr[1].isNull);
        assert(varr[2].as!string == "baz");
    }
}

package:

template ArrayElementType(T)
{
    import std.traits : isSomeString;

    static if (!isArrayType!T)
        alias ArrayElementType = T;
    else
        alias ArrayElementType = ArrayElementType!(ElementType!T);
}

unittest
{
    static assert(is(ArrayElementType!(int[][][]) == int));
    static assert(is(ArrayElementType!(int[]) == int));
    static assert(is(ArrayElementType!(int) == int));
    static assert(is(ArrayElementType!(string[][][]) == string));
    static assert(is(ArrayElementType!(bool[]) == bool));
}

template arrayDimensions(T)
if (isArray!T)
{
    static if (is(ElementType!T == ArrayElementType!T))
        enum int arrayDimensions = 1;
    else
        enum int arrayDimensions = 1 + arrayDimensions!(ElementType!T);
}

unittest
{
    static assert(arrayDimensions!(bool[]) == 1);
    static assert(arrayDimensions!(int[][]) == 2);
    static assert(arrayDimensions!(int[][][]) == 3);
    static assert(arrayDimensions!(int[][][][]) == 4);
}

template arrayDimensionType(T, size_t dimNum, size_t currDimNum = 0)
if (isArray!T)
{
    alias CurrT = ElementType!T;

    static if (currDimNum < dimNum)
        alias arrayDimensionType = arrayDimensionType!(CurrT, dimNum, currDimNum + 1);
    else
        alias arrayDimensionType = CurrT;
}

unittest
{
    static assert(is(arrayDimensionType!(bool[2][3], 0) == bool[2]));
    static assert(is(arrayDimensionType!(bool[][3], 0) == bool[]));
    static assert(is(arrayDimensionType!(bool[3][], 0) == bool[3]));
    static assert(is(arrayDimensionType!(bool[2][][4], 0) == bool[2][]));
    static assert(is(arrayDimensionType!(bool[3][], 1) == bool));
}

auto getDimensionsLengths(T)(T v)
if (isArrayType!T)
{
    enum dimNum = arrayDimensions!T;
    size_t[dimNum] ret = -1;

    calcDimensionsLengths(v, ret, 0);

    return ret;
}

private void calcDimensionsLengths(T, Ret)(T arr, ref Ret ret, int currDimNum)
if (isArray!T)
{
    import std.exception : enforce;
    import std.format : format;

    enforce(arr.length < uint.max, format!"Array dimension length can't be larger or equal than %s"(uint.max));

    ret[currDimNum] = arr.length;

    static if(isArrayType!(ElementType!T))
    {
        currDimNum++;

        if(currDimNum < ret.length)
            if(arr.length > 0)
                calcDimensionsLengths(arr[0], ret, currDimNum);
    }
}

unittest
{
    alias T = int[][2][];

    T arr = [[[1,2,3], [4,5,6]]];

    auto ret = getDimensionsLengths(arr);

    assert(ret[0] == 1);
    assert(ret[1] == 2);
    assert(ret[2] == 3);
}

// From Value to array:

import dpq2.result: ArrayProperties;

/// Convert Value to native array type
T binaryValueAs(T)(in Value v) @system
if(isArrayType!T)
{
    int idx;
    return v.valueToArrayRow!(T, 0)(ArrayProperties(v), idx);
}

private T valueToArrayRow(T, int currDimension)(in Value v, in ArrayProperties arrayProperties, ref int elemIdx) @system
{
    import std.traits: isStaticArray;
    import std.conv: to;

    T res;

    static if(isStaticArray!T)
    {
        if(T.length != arrayProperties.dimsSize[currDimension])
            throw new ValueConvException(ConvExceptionType.DIMENSION_MISMATCH,
                "Result array dimension "~currDimension.to!string~" mismatch"
            );
    }
    else
        res.length = arrayProperties.dimsSize[currDimension];

    foreach(int i, ref elem; res)
    {
        import dpq2.result;

        alias ElemType = typeof(elem);

        static if(isArrayType!ElemType)
            elem = v.valueToArrayRow!(ElemType, currDimension + 1)(arrayProperties, elemIdx);
        else
        {
            elem = v.asArray.getValueByFlatIndex(elemIdx).as!ElemType;
            elemIdx++;
        }
    }

    return res;
}

// Static array test
@system unittest
{
    alias TA = int[3][2][1];

    TA arr = [[[1,2,3], [4,5,6]]];
    Value v = arr.toValue;

    TA r = v.binaryValueAs!TA;

    assert(r == arr);
}

// Dynamic array test
@system unittest
{
    alias TA = int[][][];

    TA arr = [[[1,2,3], [4,5,6]]];
    Value v = arr.toValue;

    TA r = v.binaryValueAs!TA;

    assert(r == arr);
}

// Mixed up array test
@system unittest
{
    alias TA = int[][2][];

    TA arr = [[[1,2,3], [4,5,6]]];
    Value v = arr.toValue;

    TA r = v.binaryValueAs!TA;

    assert(r == arr);
}
