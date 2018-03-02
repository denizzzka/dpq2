module dpq2.conv.geometric;

import dpq2.oids: OidType;
import dpq2.value: ConvExceptionType, throwTypeComplaint, Value, ValueConvException, ValueFormat;
import std.bitmanip: bigEndianToNative, nativeToBigEndian;
import std.exception: enforce;
import std.traits: ReturnType, isInstanceOf;

@safe:

private bool isValidPointType(T)()
{
    return is(typeof(T.x) == double) && is(typeof(T.y) == double);
}

private bool isValidBoxType(T)()
{
    import gfm.math;

    // TODO: reduce code duplication, use hasMember
    static if(__traits(compiles, isValidPointType!(typeof(T.min)) && isValidPointType!(typeof(T.max))))
        return isValidPointType!(typeof(T.min)) && isValidPointType!(typeof(T.max));
    else
        return false;
}

private bool isValidLineSegmentType(T)()
{
    import gfm.math;

    static if(__traits(compiles, isValidPointType!(typeof(T.a)) && isValidPointType!(typeof(T.b))))
        return isValidPointType!(typeof(T.a)) && isValidPointType!(typeof(T.b));
    else
        return false;
}

private bool isValidPathType(T)()
{
    return isInstanceOf!(Path, T) /*&& isValidPointType!(typeof(T.points))*/; //FIXME
}

private auto serializePoint(Vec2Ddouble, T)(Vec2Ddouble point, T target)
if(isValidPointType!Vec2Ddouble)
{
    import std.algorithm : copy;

    auto rem = point.x.nativeToBigEndian.copy(target);
    rem = point.y.nativeToBigEndian.copy(rem);

    return rem;
}

Value toValue(Vec2Ddouble)(Vec2Ddouble pt)
if(isValidPointType!Vec2Ddouble)
{
    ubyte[] data = new ubyte[16];
    pt.serializePoint(data);

    return Value(data, OidType.Point);
}

private auto serializeBox(Box, T)(Box box, T target)
{
    auto rem = box.min.serializePoint(target);
    rem = box.max.serializePoint(rem);

    return rem;
}

Value toValue(Box)(Box box)
if(isValidBoxType!Box)
{
    ubyte[] data = new ubyte[32];
    box.serializeBox(data);

    return Value(data, OidType.Box);
}

/// Infinite line - {A,B,C} (Ax + By + C = 0)
struct Line
{
    double a;
    double b;
    double c;
}

///
struct Path(Point)
{
    bool isClosed;
    Point[] points;
}

/// Polygon (similar to closed path) - ((x1,y1),...)
//~ struct Polygon
//~ {
    //~ Point[] points; /// Polygon's points
//~ }

/// Circle - <(x,y),r> (center point and radius)
//~ struct Circle
//~ {
    //~ Point center;
    //~ double radius;
//~ }

Value toValue(Line line)
{
    import std.algorithm : copy;

    ubyte[] data = new ubyte[24];

    auto rem = line.a.nativeToBigEndian.copy(data);
    rem = line.b.nativeToBigEndian.copy(rem);
    rem = line.c.nativeToBigEndian.copy(rem);

    return Value(data, OidType.Line, false);
}

Value toValue(LineSegment)(LineSegment lseg)
if(isValidLineSegmentType!LineSegment)
{
    ubyte[] data = new ubyte[32];

    auto rem = lseg.start.serializePoint(data);
    rem = lseg.end.serializePoint(rem);

    return Value(data, OidType.LineSegment, false);
}

Value toValue(Path)(Path path)
if(isValidPathType!Path)
{
    import std.algorithm : copy;

    enforce(path.points.length >= 1, "At least one point is needed for Path");

    ubyte[] data = new ubyte[path.points.length * 16 + 5];

    auto rem = (cast(ubyte)(path.isClosed ? 1 : 0)).nativeToBigEndian.copy(data);
    rem = (cast(int)path.points.length).nativeToBigEndian.copy(rem);

    foreach (ref p; path.points)
    {
        rem = p.serializePoint(rem);
    }

    return Value(data, OidType.Path, false);
}

//~ Value toValue(Polygon poly)
//~ {
    //~ import std.algorithm : copy;

    //~ enforce(poly.points.length >= 1, "At least one point is needed for Polygon");

    //~ ubyte[] data = new ubyte[poly.points.length * 16 + 4];
    //~ auto rem = (cast(int)poly.points.length).nativeToBigEndian.copy(data);

    //~ foreach (ref p; poly.points)
    //~ {
        //~ rem = p.serialize(rem);
    //~ }

    //~ return Value(data, OidType.Polygon, false);
//~ }

//~ Value toValue(Circle c)
//~ {
    //~ import std.algorithm : copy;

    //~ ubyte[] data = new ubyte[24];
    //~ auto rem = c.center.serialize(data);
    //~ c.radius.nativeToBigEndian.copy(rem);

    //~ return Value(data, OidType.Circle, false);
//~ }

private alias AE = ValueConvException;
private alias ET = ConvExceptionType;

Vec2Ddouble binaryValueAsPoint(Vec2Ddouble)(in Value v)
if(isValidPointType!Vec2Ddouble)
{
    if(!(v.oidType == OidType.Point))
        throwTypeComplaint(v.oidType, "Point", __FILE__, __LINE__);

    auto data = v.data;

    if(!(data.length == 16))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres Point size", __FILE__, __LINE__);

    return pointFromBytes!Vec2Ddouble(data[0..16]);
}

private Vec2Ddouble pointFromBytes(Vec2Ddouble)(in ubyte[16] data) pure
if(isValidPointType!Vec2Ddouble)
{
    return Vec2Ddouble(data[0..8].bigEndianToNative!double, data[8..16].bigEndianToNative!double);
}

T binaryValueAs(T)(in Value v)
if (is(T == Line))
{
    if(!(v.oidType == OidType.Line))
        throwTypeComplaint(v.oidType, "Line", __FILE__, __LINE__);

    if(!(v.data.length == 24))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres Line size", __FILE__, __LINE__);

    return Line((v.data[0..8].bigEndianToNative!double), v.data[8..16].bigEndianToNative!double, v.data[16..24].bigEndianToNative!double);
}

LineSegment binaryValueAsLineSegment(LineSegment)(in Value v)
if(isValidLineSegmentType!LineSegment)
{
    if(!(v.oidType == OidType.LineSegment))
        throwTypeComplaint(v.oidType, "LineSegment", __FILE__, __LINE__);

    if(!(v.data.length == 32))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres LineSegment size", __FILE__, __LINE__);

    alias Point = ReturnType!(LineSegment.start);

    auto start = v.data[0..16].pointFromBytes!Point;
    auto end = v.data[16..32].pointFromBytes!Point;

    return LineSegment(start, end);
}

Box binaryValueAsBox(Box)(in Value v)
if(isValidBoxType!Box)
{
    if(!(v.oidType == OidType.Box))
        throwTypeComplaint(v.oidType, "Box", __FILE__, __LINE__);

    if(!(v.data.length == 32))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres Box size", __FILE__, __LINE__);

    alias Point = typeof(Box.min);

    auto min = v.data[0..16].pointFromBytes!Point;
    auto max = v.data[16..32].pointFromBytes!Point;

    return Box(min, max);
}

Path binaryValueAs(Path)(in Value v)
if(isValidPathType!Path)
{
    import std.array : uninitializedArray;

    if(!(v.oidType == OidType.Path))
        throwTypeComplaint(v.oidType, "Path", __FILE__, __LINE__);

    if(!((v.data.length - 5) % 16 == 0))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to Postgres Path size", __FILE__, __LINE__);

    Path res;
    res.isClosed = v.data[0..1].bigEndianToNative!byte == 1;
    int len = v.data[1..5].bigEndianToNative!int;

    if (len != (v.data.length - 5)/16)
        throw new AE(ET.SIZE_MISMATCH, "Path points number mismatch", __FILE__, __LINE__);

    alias Point = typeof(Path.points[0]);

    res.points = uninitializedArray!(Point[])(len);
    for (int i=0; i<len; i++)
    {
        const ubyte[] b = v.data[ i*16+5 .. i*16+5+16 ];
        res.points[i] = b[0..16].pointFromBytes!Point;
    }

    return res;
}

//~ T binaryValueAs(T)(in Value v)
//~ if (is(T == Polygon))
//~ {
    //~ import std.array : uninitializedArray;

    //~ if(!(v.oidType == OidType.Polygon))
        //~ throwTypeComplaint(v.oidType, "Polygon", __FILE__, __LINE__);

    //~ if(!((v.data.length - 4) % 16 == 0))
        //~ throw new AE(ET.SIZE_MISMATCH,
            //~ "Value length isn't equal to Postgres Polygon size", __FILE__, __LINE__);

    //~ T res;
    //~ int len = v.data[0..4].bigEndianToNative!int;

    //~ if (len != (v.data.length - 4)/16)
        //~ throw new AE(ET.SIZE_MISMATCH, "Path points number mismatch", __FILE__, __LINE__);

    //~ res.points = uninitializedArray!(Point[])(len);
    //~ for (int i=0; i<len; i++)
    //~ {
        //~ res.points[i] = v.data[(i*16+4)..(i*16+16+4)].binaryValueAs!Point;
    //~ }

    //~ return res;
//~ }

//~ T binaryValueAs(T)(in Value v)
//~ if (is(T == Circle))
//~ {
    //~ if(!(v.oidType == OidType.Circle))
        //~ throwTypeComplaint(v.oidType, "Circle", __FILE__, __LINE__);

    //~ if(!(v.data.length == 24))
        //~ throw new AE(ET.SIZE_MISMATCH,
            //~ "Value length isn't equal to Postgres Circle size", __FILE__, __LINE__);

    //~ return Circle(
        //~ v.data[0..16].binaryValueAs!Point,
        //~ v.data[16..24].bigEndianToNative!double
    //~ );
//~ }

unittest
{

    import gfm.math;

    alias Point = vec2d;
    alias Box = box2d;
    static struct LineSegment
    {
        seg2d seg;
        alias seg this;

        ref Point start(){ return a; }
        ref Point end(){ return b; }

        this(Point a, Point b)
        {
            seg.a = a;
            seg.b = b;
        }
    }
    alias TestPath = Path!Point;

    // binary write/read
    {
        auto pt = Point(1,2);
        assert(pt.toValue.binaryValueAsPoint!Point == pt);

        auto ln = Line(1,2,3);
        assert(ln.toValue.binaryValueAs!Line == ln);

        auto lseg = LineSegment(Point(1,2),Point(3,4));
        assert(lseg.toValue.binaryValueAsLineSegment!LineSegment == lseg);

        auto b = Box(Point(2,2), Point(1,1));
        assert(b.toValue.binaryValueAsBox!Box == b);

        auto p = TestPath(false, [Point(1,1), Point(2,2)]);
        assert(p.toValue.binaryValueAs!TestPath == p);

        p = TestPath(true, [Point(1,1), Point(2,2)]);
        assert(p.toValue.binaryValueAs!TestPath == p);

        //~ auto poly = Polygon([Point(1,1), Point(2,2), Point(3,3)]);
        //~ assert(poly.toValue.binaryValueAs!Polygon == poly);

        //~ auto c = Circle(Point(1,2), 3);
        //~ assert(c.toValue.binaryValueAs!Circle == c);
    }

    // Invalid OID tests
    {
        import std.exception : assertThrown;

        auto v = Point(1,1).toValue;
        v.oidType = OidType.Text;
        assertThrown!ValueConvException(v.binaryValueAsPoint!Point);

        v = Line(1,2,3).toValue;
        v.oidType = OidType.Text;
        assertThrown!ValueConvException(v.binaryValueAs!Line);

        v = LineSegment(Point(1,1), Point(2,2)).toValue;
        v.oidType = OidType.Text;
        assertThrown!ValueConvException(v.binaryValueAsLineSegment!LineSegment);

        v = Box(Point(1,1), Point(2,2)).toValue;
        v.oidType = OidType.Text;
        assertThrown!ValueConvException(v.binaryValueAsBox!Box);

        v = TestPath(true, [Point(1,1), Point(2,2)]).toValue;
        v.oidType = OidType.Text;
        assertThrown!ValueConvException(v.binaryValueAs!TestPath);

        //~ v = Polygon([Point(1,1), Point(2,2)]).toValue;
        //~ v.oidType = OidType.Text;
        //~ assertThrown!ValueConvException(v.binaryValueAs!Polygon);

        //~ v = Circle(Point(1,1), 3).toValue;
        //~ v.oidType = OidType.Text;
        //~ assertThrown!ValueConvException(v.binaryValueAs!Circle);
    }

    // Invalid data size
    {
        import std.exception : assertThrown;

        auto v = Point(1,1).toValue;
        v._data = new ubyte[1];
        assertThrown!ValueConvException(v.binaryValueAsPoint!Point);

        v = Line(1,2,3).toValue;
        v._data.length = 1;
        assertThrown!ValueConvException(v.binaryValueAs!Line);

        v = LineSegment(Point(1,1), Point(2,2)).toValue;
        v._data.length = 1;
        assertThrown!ValueConvException(v.binaryValueAsLineSegment!LineSegment);

        v = Box(Point(1,1), Point(2,2)).toValue;
        v._data.length = 1;
        assertThrown!ValueConvException(v.binaryValueAsBox!Box);

        v = TestPath(true, [Point(1,1), Point(2,2)]).toValue;
        v._data.length -= 16;
        assertThrown!ValueConvException(v.binaryValueAs!TestPath);
        v._data.length = 1;
        assertThrown!ValueConvException(v.binaryValueAs!TestPath);

        //~ v = Polygon([Point(1,1), Point(2,2)]).toValue;
        //~ v._data.length -= 16;
        //~ assertThrown!ValueConvException(v.binaryValueAs!Polygon);
        //~ v._data.length = 1;
        //~ assertThrown!ValueConvException(v.binaryValueAs!Polygon);

        //~ v = Circle(Point(1,1), 3).toValue;
        //~ v._data.length = 1;
        //~ assertThrown!ValueConvException(v.binaryValueAs!Circle);
    }
}
