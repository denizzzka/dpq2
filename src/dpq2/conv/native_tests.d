module dpq2.conv.native_tests;

import dpq2;
import dpq2.conv.arrays : isArrayType;
import dpq2.conv.geometric: Line;
import std.bitmanip : BitArray;
import std.datetime;
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

    auto conn = new Connection(connParam);

    // to return times in other than UTC time zone but fixed time zone so make the test reproducible in databases with other TZ
    conn.exec("SET TIMEZONE TO +02");

    conn.exec("SET lc_monetary = 'en_US.UTF-8'");

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(T)(T nativeValue, in string pgType, string pgValue)
        {
            import std.algorithm : strip;
            import std.string : representation;
            import std.meta: AliasSeq, anySatisfy;
            import std.traits: isType;

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

            import std.stdio;
            writeln(`==========`);
            writeln("native typeid=", typeid(T));
            writeln("pgType=", pgType);
            result.writeln;

            alias disabledStdVariantTests = AliasSeq!(BitArray, PGTestMoney);

            static if(!anySatisfy!(isType!T, disabledStdVariantTests))
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

                //Varint:
                // Adittional disabled tests what cause types mismatch
                // TODO: remove
                alias resultTestsDisabled = AliasSeq!(SysTime, Json, BitArray);

                static if(
                    !anySatisfy!(isType!T, disabledStdVariantTests) ||
                    !anySatisfy!(isType!T, resultTestsDisabled)
                )
                {
                    assert(stdVariantResult == nativeValue, formatMsg("std.variant.Variant"));
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
        C!PGtimestamp(PGtimestamp(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12)), "timestamp without time zone", "'1997-12-17 07:37:16.000012'");
        C!PGtimestamptz(PGtimestamptz(DateTime(1997, 12, 17, 5, 37, 16), dur!"usecs"(12)), "timestamp with time zone", "'1997-12-17 07:37:16.000012+02'");
        C!PGtimestamp(PGtimestamp.earlier, "timestamp", "'-infinity'");
        C!PGtimestamp(PGtimestamp.later, "timestamp", "'infinity'");
        C!PGtimestamp(PGtimestamp.min, "timestamp", `'4713-01-01 00:00:00 BC'`);
        C!PGtimestamp(PGtimestamp.max, "timestamp", `'294276-12-31 23:59:59.999999'`);

        // SysTime testing
        auto testTZ = new immutable SimpleTimeZone(2.dur!"hours"); // custom TZ
        C!SysTime(SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12), testTZ), "timestamptz", "'1997-12-17 07:37:16.000012+02'"); // FIXME: fails here
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
        import dpq2.conv.geometric: GeometricInstancesForIntegrationTest;
        mixin GeometricInstancesForIntegrationTest;

        C!Point(Point(1,2), "point", "'(1,2)'");
        C!PGline(Line(1,2,3), "line", "'{1,2,3}'");
        C!LineSegment(LineSegment(Point(1,2), Point(3,4)), "lseg", "'[(1,2),(3,4)]'");
        C!Box(Box(Point(1,2),Point(3,4)), "box", "'(3,4),(1,2)'"); // PG handles box ordered as upper right first and lower left next
        C!TestPath(TestPath(true, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'((1,1),(2,2),(3,3))'");
        C!TestPath(TestPath(false, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'[(1,1),(2,2),(3,3)]'");
        C!Polygon(([Point(1,1), Point(2,2), Point(3,3)]), "polygon", "'((1,1),(2,2),(3,3))'");
        C!TestCircle(TestCircle(Point(1,2), 10), "circle", "'<(1,2),10>'");
        C!(Nullable!Point)(Nullable!Point(Point(1,2)), "point", "'(1,2)'");

        //Arrays
        C!(int[][])([[1,2],[3,4]], "int[]", "'{{1,2},{3,4}}'");
        C!(int[])([], "int[]", "'{}'"); // empty array test
        C!((Nullable!string)[])([Nullable!string("foo"), Nullable!string.init], "text[]", "'{foo,NULL}'");
        C!(string[])(["foo","bar", "baz"], "text[]", "'{foo,bar,baz}'");
        C!(PGjson[])([Json(["foo": Json(42)])], "json[]", `'{"{\"foo\":42}"}'`);
        C!(PGuuid[])([UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640")], "uuid[]", "'{8b9ab33a-96e9-499b-9c36-aad1fe86d640}'");
        C!(Nullable!(int[]))(Nullable!(int[]).init, "int[]", "NULL");
        C!(Nullable!(int[]))(Nullable!(int[])([1,2,3]), "int[]", "'{1,2,3}'");
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
