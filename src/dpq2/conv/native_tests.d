module dpq2.conv.native_tests;

import dpq2;
import dpq2.conv.arrays : isArrayType;
import dpq2.conv.geometric: Line;
import dpq2.conv.ranges;
import std.bitmanip : BitArray;
import std.datetime;
import std.string: replace;
import std.typecons: Nullable;
import std.uuid: UUID;
import std.variant: Variant;
import vibe.data.json: Json, parseJsonString;

version (integration_tests)
private bool compareArraysWithCareAboutNullables(A, B)(A _a, B _b)
{
    static assert(is(A == B));

    import std.algorithm.comparison : equal;
    import std.traits: isInstanceOf;

    return equal!(
        (a, b)
        {
            static if(isInstanceOf!(Nullable, A))
            {
                if(a.isNull != b.isNull)
                    return false;

                if(a.isNull)
                    return true;
            }

            return a == b;
        }
    )(_a, _b);
}

version (integration_tests)
public void _integration_test( string connParam ) @system
{
    import std.format: format;
    import dpq2.connection: createTestConn;

    auto conn = createTestConn(connParam);

    // to return times in other than UTC time zone but fixed time zone so make the test reproducible in databases with other TZ
    conn.exec("SET TIMEZONE TO +02");

    // It is found what Linux and Windows have different approach for monetary
    // types formatting at same locales. This line sets equal approach.
    conn.exec("SET lc_monetary = 'C'");

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        import dpq2.conv.geometric: GeometricInstancesForIntegrationTest;
        mixin GeometricInstancesForIntegrationTest;

        void testIt(T)(T nativeValue, in string pgType, string pgValue)
        {
            import std.algorithm : strip;
            import std.string : representation;
            import std.meta: AliasSeq, anySatisfy;

            static string formatValue(T val)
            {
                import std.algorithm : joiner, map;
                import std.conv : text, to;
                import std.range : chain, ElementType;

                // Nullable format deprecation workaround
                static if (is(T == Nullable!R, R))
                    return val.isNull ? "null" : val.get.to!string;
                else static if (isArrayType!T && is(ElementType!T == Nullable!E, E))
                    return chain("[", val.map!(a => a.isNull ? "null" : a.to!string).joiner(", "), "]").text;
                else return val.to!string;
            }

            // test string to native conversion
            params.sqlCommand = format("SELECT %s::%s as d_type_test_value", pgValue is null ? "NULL" : pgValue, pgType);
            params.args = null;
            auto answer = conn.execParams(params);
            immutable Value v = answer[0][0];

            auto result = v.as!T;

            enum disabledForStdVariant = (
                is(T == Nullable!string[]) || // Variant haven't heuristics to understand what array elements can contain NULLs
                is(T == Nullable!(int[])) || // Same reason, but here is all values are Nullable and thus incompatible for comparison with original values
                is(T == SysTime) || is(T == Nullable!SysTime) || // Can't be supported by toVariant because TimeStampWithZone converted to PGtimestamptz
                is(T == LineSegment) || // Impossible to support: LineSegment struct must be provided by user
                is(T == PGTestMoney) || // ditto
                is(T == BitArray) || //TODO: Format of the column (VariableBitString) doesn't supported by Value to Variant converter
                is(T == Nullable!BitArray) || // ditto
                is(T == Point) || // Impossible to support: LineSegment struct must be provided by user
                is(T == Nullable!Point) || // ditto
                is(T == Box) || // ditto
                is(T == TestPath) || // ditto
                is(T == TestPolygon) || // ditto
                is(T == TestCircle) // ditto
            );

            static if(!disabledForStdVariant)
            {
                static if (is(T == Nullable!R, R))
                    auto stdVariantResult = v.as!(Variant, true);
                else
                    auto stdVariantResult = v.as!(Variant, false);
            }

            string formatMsg(string varType)
            {
                return format(
                    "PG to %s conv: received unexpected value\nreceived pgType=%s\nexpected nativeType=%s\nsent pgValue=%s\nexpected nativeValue=%s\nresult=%s",
                    varType, v.oidType, typeid(T), pgValue, formatValue(nativeValue), formatValue(result)
                );
            }

            static if(isArrayType!T)
                const bool assertResult = compareArraysWithCareAboutNullables(result, nativeValue);
            else
            {
                const bool assertResult = result == nativeValue;

                //Variant:
                static if(!disabledForStdVariant)
                {
                    // Ignores "json as string" test case with Json sent natively as string
                    if(!(is(T == string) && v.oidType == OidType.Json))
                    {
                        assert(stdVariantResult == nativeValue, formatMsg("std.variant.Variant (type: %s)".format(stdVariantResult.type)));
                    }
                }
            }

            assert(assertResult, formatMsg("native"));

            {
                // test binary to text conversion
                params.sqlCommand = "SELECT $1::text";
                params.args = [toValue(nativeValue)];

                auto answer2 = conn.execParams(params);
                auto v2 = answer2[0][0];

                string textResult = v2.isNull
                    ? "NULL"
                    : v2.as!string.strip(' ');

                pgValue = pgValue.strip('\'');

                // Special cases:
                static if(is(T == PGbytea))
                    pgValue = `\x442072756c65730021`; // Server formats its reply slightly different from the passed argument

                static if(is(T == Json))
                {
                    // Reformatting by same way in the hope that the data will be sorted same in both cases
                    pgValue = pgValue.parseJsonString.toString;
                    textResult = textResult.parseJsonString.toString;
                }

                static if(is(T == TsRange) || is(T == TsTzRange) || is(T == TsMultiRange) || is(T == TsTzMultiRange))
                    textResult = textResult.replace('"', "");

                static if(is(T == TsRange[]) || is(T == TsTzRange[]) || is(T == TsMultiRange[]) || is(T == TsTzMultiRange[]))
                    textResult = textResult.replace(`\"`, "");

                assert(textResult == pgValue,
                    format("Native to PG conv: received unexpected value\nreceived pgType=%s\nsent nativeType=%s\nsent nativeValue=%s\nexpected pgValue=%s\nresult=%s\nexpectedRepresentation=%s\nreceivedRepresentation=%s",
                    v.oidType, typeid(T), formatValue(nativeValue), pgValue, textResult, pgValue.representation, textResult.representation)
                );
            }
        }

        alias C = testIt; // "C" means "case"

        import dpq2.conv.to_d_types: PGTestMoney;

        C!PGboolean(true, "boolean", "true");
        C!PGboolean(false, "boolean", "false");
        C!(Nullable!PGboolean)(Nullable!PGboolean.init, "boolean", "NULL");
        C!(Nullable!PGboolean)(Nullable!PGboolean(true), "boolean", "true");
        C!PGsmallint(-32_761, "smallint", "-32761");
        C!PGinteger(-2_147_483_646, "integer", "-2147483646");
        C!PGbigint(-9_223_372_036_854_775_806, "bigint", "-9223372036854775806");
        C!PGTestMoney(PGTestMoney(-123.45), "money", "'-$123.45'");
        C!PGreal(-12.3456f, "real", "-12.3456");
        C!PGdouble_precision(-1234.56789012345, "double precision", "-1234.56789012345");
        C!PGtext("first line\nsecond line", "text", "'first line\nsecond line'");
        C!PGtext("12345 ", "char(6)", "'12345'");
        C!PGtext("12345", "varchar(6)", "'12345'");
        C!(Nullable!PGtext)(Nullable!PGtext.init, "text", "NULL");
        C!PGbytea([0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21],
            "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)
        C!PGuuid(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640"), "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");
        C!(Nullable!PGuuid)(Nullable!UUID(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")), "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");
        C!PGvarbit(BitArray([1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]), "varbit", "'101011010110101'");
        C!PGvarbit(BitArray([0, 0, 1, 0, 1]), "varbit", "'00101'");
        C!PGvarbit(BitArray([1, 0, 1, 0, 0]), "varbit", "'10100'");
        C!(Nullable!PGvarbit)(Nullable!PGvarbit.init, "varbit", "NULL");

        // numeric testing
        C!PGnumeric("NaN", "numeric", "'NaN'");

        const string[] numericTests = [
            "42",
            "-42",
            "0",
            "0.0146328",
            "0.0007",
            "0.007",
            "0.07",
            "0.7",
            "7",
            "70",
            "700",
            "7000",
            "70000",

            "7.0",
            "70.0",
            "700.0",
            "7000.0",
            "70000.000",

            "2354877787627192443",
            "2354877787627192443.0",
            "2354877787627192443.00000",
            "-2354877787627192443.00000"
        ];

        foreach(i, s; numericTests)
            C!PGnumeric(s, "numeric", s);

        // date and time testing
        C!PGdate(Date(2016, 01, 8), "date", "'2016-01-08'");
        {
            import std.exception : assertThrown;

            assertThrown!ValueConvException(
                    C!PGdate(Date(0001, 01, 8), "date", "'5874897-12-31'")
                );
        }
        C!PGtime_without_time_zone(TimeOfDay(12, 34, 56), "time without time zone", "'12:34:56'");
        C!PGtime_with_time_zone(PGtime_with_time_zone(TimeOfDay(12, 34, 56), 3600 * 5), "time with time zone", "'12:34:56-05'");
        C!PGinterval(PGinterval(-123), "interval", "'-00:00:00.000123'");
        C!PGinterval(PGinterval(7200_000_000 + 123), "interval", "'02:00:00.000123'");
        C!PGinterval(PGinterval(0, 2, 13), "interval", "'1 year 1 mon 2 days'");
        C!PGinterval(PGinterval(0, 0, -1), "interval", "'-1 mons'");
        C!PGinterval(PGinterval(0, -2, 1), "interval", "'1 mon -2 days'");
        C!PGinterval(PGinterval(-123, -2, -1), "interval", "'-1 mons -2 days -00:00:00.000123'");
        C!PGinterval(PGinterval(-(7200_000_000 + 123), 2, 177999999 * 12 + 3), "interval", "'177999999 years 3 mons 2 days -02:00:00.000123'");
        C!PGtimestamp(PGtimestamp(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12)), "timestamp without time zone", "'1997-12-17 07:37:16.000012'");
        C!PGtimestamptz(PGtimestamptz(DateTime(1997, 12, 17, 5, 37, 16), dur!"usecs"(12)), "timestamp with time zone", "'1997-12-17 07:37:16.000012+02'");
        C!PGtimestamp(PGtimestamp.earlier, "timestamp", "'-infinity'");
        C!PGtimestamp(PGtimestamp.later, "timestamp", "'infinity'");
        C!PGtimestamp(PGtimestamp.min, "timestamp", `'4713-01-01 00:00:00 BC'`);
        C!PGtimestamp(PGtimestamp.max, "timestamp", `'294276-12-31 23:59:59.999999'`);

        // SysTime testing
        auto testTZ = new immutable SimpleTimeZone(2.dur!"hours"); // custom TZ
        C!SysTime(SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12), testTZ), "timestamptz", "'1997-12-17 07:37:16.000012+02'");
        C!(Nullable!SysTime)(Nullable!SysTime(SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12), testTZ)), "timestamptz", "'1997-12-17 07:37:16.000012+02'");

        // json
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string")]), "json", `'{"float_value": 123.456,"text_str": "text string"}'`);
        C!(Nullable!PGjson)(Nullable!Json(Json(["foo": Json("bar")])), "json", `'{"foo":"bar"}'`);

        // json as string
        C!string(`{"float_value": 123.456}`, "json", `'{"float_value": 123.456}'`);

        // jsonb
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string"), "abc": Json(["key": Json("value")])]), "jsonb",
            `'{"float_value": 123.456, "text_str": "text string", "abc": {"key": "value"}}'`);

        // Geometric
        C!Point(Point(1,2), "point", "'(1,2)'");
        C!PGline(Line(1,2,3), "line", "'{1,2,3}'");
        C!LineSegment(LineSegment(Point(1,2), Point(3,4)), "lseg", "'[(1,2),(3,4)]'");
        C!Box(Box(Point(1,2), Point(3,4)), "box", "'(3,4),(1,2)'"); // PG handles box ordered as upper right first and lower left next
        C!TestPath(TestPath(true, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'((1,1),(2,2),(3,3))'");
        C!TestPath(TestPath(false, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'[(1,1),(2,2),(3,3)]'");
        C!TestPolygon(TestPolygon([Point(1,1), Point(2,2), Point(3,3)]), "polygon", "'((1,1),(2,2),(3,3))'");
        C!TestCircle(TestCircle(Point(1,2), 10), "circle", "'<(1,2),10>'");
        C!(Nullable!Point)(Nullable!Point(Point(1,2)), "point", "'(1,2)'");

        // Arrays
        C!(int[][])([[1,2],[3,4]], "int[]", "'{{1,2},{3,4}}'");
        C!(int[])([], "int[]", "'{}'"); // empty array test
        C!((Nullable!string)[])([Nullable!string("foo"), Nullable!string.init], "text[]", "'{foo,NULL}'");
        C!(string[])(["foo","bar", "baz"], "text[]", "'{foo,bar,baz}'");
        C!(PGjson[])([Json(["foo": Json(42)])], "json[]", `'{"{\"foo\":42}"}'`);
        C!(PGuuid[])([UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")], "uuid[]", "'{8b9ab33a-96e9-499b-9c36-aad1fe86d640}'");
        C!(PGline[])([Line(1,2,3), Line(4,5,6)], "line[]", `'{"{1,2,3}","{4,5,6}"}'`);
        C!(Nullable!(int[]))(Nullable!(int[]).init, "int[]", "NULL");
        C!(Nullable!(int[]))(Nullable!(int[])([1,2,3]), "int[]", "'{1,2,3}'");

        // Ranges
        C!Int4Range(Int4Range([2, 0,0,0,4, 0,0,0,35, 0,0,0,4, 0,0,0,71]), "int4range", "'[35,71)'");
        C!Int8Range(Int8Range([2, 0,0,0,8, 0,0,0,0,0,0,1,92, 0,0,0,8, 0,0,0,0,2,42,0,11]), "int8range", "'[348,36306955)'");
        C!NumRange(NumRange([2, 0,0,0,16, 0,4,0,1,0,0,0,6,0,12,13,128,38,148,21,24, 0,0,0,16, 0,4,0,1,0,0,0,6,0,32,6,118,38,169,37,128]), "numrange", "'[123456.987654,321654.989796)'");
        C!TsRange(TsRange([2, 0,0,0,8, 0,2,206,85,58,90,234,0, 0,0,0,8, 0,2,207,173,95,251,7,0]), "tsrange", "'[2025-01-10 09:10:00,2025-01-27 11:45:00)'");
        C!TsTzRange(TsTzRange([2, 0,0,0,8, 0,2,206,83,141,51,162,0, 0,0,0,8, 0,2,207,171,178,211,191,0]), "tstzrange", "'[2025-01-10 09:10:00+02,2025-01-27 11:45:00+02)'");
        C!DateRange(DateRange([2, 0,0,0,4, 255,255,227,119, 0,0,0,4, 255,255,231,190]), "daterange", "'[1980-01-01,1982-12-31)'");

        // Range arrays
        C!(Int4Range[])([Int4Range([2, 0,0,0,4, 0,0,0,35, 0,0,0,4, 0,0,0,71])], "int4range[]", `'{"[35,71)"}'`);
        C!(Int8Range[])([Int8Range([2, 0,0,0,8, 0,0,0,0,0,0,1,92, 0,0,0,8, 0,0,0,0,2,42,0,11])], "int8range[]", `'{"[348,36306955)"}'`);
        C!(NumRange[])([NumRange([2, 0,0,0,16, 0,4,0,1,0,0,0,6,0,12,13,128,38,148,21,24, 0,0,0,16, 0,4,0,1,0,0,0,6,0,32,6,118,38,169,37,128])], "numrange[]", `'{"[123456.987654,321654.989796)"}'`);
        C!(TsRange[])([TsRange([2, 0,0,0,8, 0,2,206,85,58,90,234,0, 0,0,0,8, 0,2,207,173,95,251,7,0])], "tsrange[]", `'{"[2025-01-10 09:10:00,2025-01-27 11:45:00)"}'`);
        C!(TsTzRange[])([TsTzRange([2, 0,0,0,8, 0,2,206,83,141,51,162,0, 0,0,0,8, 0,2,207,171,178,211,191,0])], "tstzrange[]", `'{"[2025-01-10 09:10:00+02,2025-01-27 11:45:00+02)"}'`);
        C!(DateRange[])([DateRange([2, 0,0,0,4, 255,255,227,119, 0,0,0,4, 255,255,231,190])], "daterange[]", `'{"[1980-01-01,1982-12-31)"}'`);

        // Multiranges
        C!Int4MultiRange(Int4MultiRange([0,0,0,2, 0,0,0,17, 2, 0,0,0,4, 0,0,0,23, 0,0,0,4, 0,0,0,32, 0,0,0,17, 2, 0,0,0,4, 0,0,0,35, 0,0,0,4, 0,0,0,71]), "int4multirange", "'{[23,32),[35,71)}'");
        C!Int8MultiRange(Int8MultiRange([0,0,0,2, 0,0,0,25, 2, 0,0,0,8, 0,0,0,0,0,0,0,3, 0,0,0,8, 0,0,0,0,0,0,0,14, 0,0,0,25, 2, 0,0,0,8, 0,0,0,0,0,0,1,92, 0,0,0,8, 0,0,0,0,2,42,0,11]), "int8multirange", "'{[3,14),[348,36306955)}'");
        C!NumMultiRange(NumMultiRange([0,0,0,2, 0,0,0,33, 2, 0,0,0,12, 0,2,0,0,0,0,0,2,0,17,34,196, 0,0,0,12, 0,2,0,0,0,0,0,3,0,24,30,210, 0,0,0,41, 2, 0,0,0,16, 0,4,0,1,0,0,0,6,0,12,13,128,38,148,21,24, 0,0,0,16, 0,4,0,1,0,0,0,6,0,32,6,118,38,169,37,128]), "nummultirange", "'{[17.89,24.789),[123456.987654,321654.989796)}'");
        C!TsMultiRange(TsMultiRange([0,0,0,1, 0,0,0,25, 2, 0,0,0,8, 0,2,206,85,58,90,234,0, 0,0,0,8, 0,2,207,173,95,251,7,0]), "tsmultirange", "'{[2025-01-10 09:10:00,2025-01-27 11:45:00)}'");
        C!TsTzMultiRange(TsTzMultiRange([0,0,0,1, 0,0,0,25, 2, 0,0,0,8, 0,2,206,83,141,51,162,0, 0,0,0,8, 0,2,207,171,178,211,191,0]), "tstzmultirange", "'{[2025-01-10 09:10:00+02,2025-01-27 11:45:00+02)}'");
        C!DateMultiRange(DateMultiRange([0,0,0,1, 0,0,0,17, 2, 0,0,0,4, 255,255,227,119, 0,0,0,4, 255,255,231,190]), "datemultirange", "'{[1980-01-01,1982-12-31)}'");

        // Multirange arrays
        C!(Int4MultiRange[])([Int4MultiRange([0,0,0,2, 0,0,0,17, 2, 0,0,0,4, 0,0,0,23, 0,0,0,4, 0,0,0,32, 0,0,0,17, 2, 0,0,0,4, 0,0,0,35, 0,0,0,4, 0,0,0,71])], "int4multirange[]", `'{"{[23,32),[35,71)}"}'`);
        C!(Int8MultiRange[])([Int8MultiRange([0,0,0,2, 0,0,0,25, 2, 0,0,0,8, 0,0,0,0,0,0,0,3, 0,0,0,8, 0,0,0,0,0,0,0,14, 0,0,0,25, 2, 0,0,0,8, 0,0,0,0,0,0,1,92, 0,0,0,8, 0,0,0,0,2,42,0,11])], "int8multirange[]", `'{"{[3,14),[348,36306955)}"}'`);
        C!(NumMultiRange[])([NumMultiRange([0,0,0,2, 0,0,0,33, 2, 0,0,0,12, 0,2,0,0,0,0,0,2,0,17,34,196, 0,0,0,12, 0,2,0,0,0,0,0,3,0,24,30,210, 0,0,0,41, 2, 0,0,0,16, 0,4,0,1,0,0,0,6,0,12,13,128,38,148,21,24, 0,0,0,16, 0,4,0,1,0,0,0,6,0,32,6,118,38,169,37,128])], "nummultirange[]", `'{"{[17.89,24.789),[123456.987654,321654.989796)}"}'`);
        C!(TsMultiRange[])([TsMultiRange([0,0,0,1, 0,0,0,25, 2, 0,0,0,8, 0,2,206,85,58,90,234,0, 0,0,0,8, 0,2,207,173,95,251,7,0])], "tsmultirange[]", `'{"{[2025-01-10 09:10:00,2025-01-27 11:45:00)}"}'`);
        C!(TsTzMultiRange[])([TsTzMultiRange([0,0,0,1, 0,0,0,25, 2, 0,0,0,8, 0,2,206,83,141,51,162,0, 0,0,0,8, 0,2,207,171,178,211,191,0])], "tstzmultirange[]", `'{"{[2025-01-10 09:10:00+02,2025-01-27 11:45:00+02)}"}'`);
        C!(DateMultiRange[])([DateMultiRange([0,0,0,1, 0,0,0,17, 2, 0,0,0,4, 255,255,227,119, 0,0,0,4, 255,255,231,190])], "datemultirange[]", `'{"{[1980-01-01,1982-12-31)}"}'`);
    }

    // test round-trip compound types
    {
        conn.exec("CREATE TYPE test_type AS (x int, y int)");
        scope(exit) conn.exec("DROP TYPE test_type");

        params.sqlCommand = "SELECT 'test_type'::regtype::oid";
        OidType oid = cast(OidType)conn.execParams(params)[0][0].as!Oid;

        Value input = Value(toRecordValue([17.toValue, Nullable!int.init.toValue]).data, oid);

        params.sqlCommand = "SELECT $1::text";
        params.args = [input];
        Value v = conn.execParams(params)[0][0];
        assert(v.as!string == `(17,)`, v.as!string);
        params.sqlCommand = "SELECT $1";
        v = conn.execParams(params)[0][0];
        assert(v.oidType == oid && v.data == input.data);
    }
}
