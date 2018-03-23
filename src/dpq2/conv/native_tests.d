module dpq2.conv.native_tests;

import dpq2;
import std.typecons: Nullable;
import std.datetime;
import vibe.data.json: Json, parseJsonString;
import vibe.data.bson: Bson;
import std.uuid: UUID;
import dpq2.conv.geometric: Line;

version (integration_tests)
public void _integration_test( string connParam ) @system
{
    import std.format: format;

    auto conn = new Connection(connParam);

    // to return times in other than UTC time zone but fixed time zone so make the test reproducible in databases with other TZ
    conn.exec("SET TIMEZONE TO +02");

    QueryParams params;
    params.resultFormat = ValueFormat.BINARY;

    {
        void testIt(T)(T nativeValue, string pgType, string pgValue)
        {
            import std.algorithm : strip;
            import std.string : representation;

            // test string to native conversion
            params.sqlCommand = format("SELECT %s::%s as d_type_test_value", pgValue is null ? "NULL" : pgValue, pgType);
            params.args = null;
            auto answer = conn.execParams(params);
            immutable Value v = answer[0][0];
            auto result = v.as!T;

            assert(result == nativeValue,
                format("PG to native conv: received unexpected value\nreceived pgType=%s\nexpected nativeType=%s\nsent pgValue=%s\nexpected nativeValue=%s\nresult=%s",
                v.oidType, typeid(T), pgValue, nativeValue, result)
            );

            {
                // test binary to text conversion
                params.sqlCommand = "SELECT $1::text";
                params.args = [nativeValue.toValue];

                auto answer2 = conn.execParams(params);
                auto v2 = answer2[0][0];
                auto textResult = v2.isNull ? null : v2.as!string.strip(' ');
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
                    v.oidType, typeid(T), nativeValue, pgValue, textResult, pgValue.representation, textResult.representation)
                );
            }
        }

        alias C = testIt; // "C" means "case"

        C!PGboolean(true, "boolean", "true");
        C!PGboolean(false, "boolean", "false");
        C!(Nullable!PGboolean)(Nullable!PGboolean.init, "boolean", null);
        C!(Nullable!PGboolean)(Nullable!PGboolean(true), "boolean", "true");
        C!PGsmallint(-32_761, "smallint", "-32761");
        C!PGinteger(-2_147_483_646, "integer", "-2147483646");
        C!PGbigint(-9_223_372_036_854_775_806, "bigint", "-9223372036854775806");
        C!PGreal(-12.3456f, "real", "-12.3456");
        C!PGdouble_precision(-1234.56789012345, "double precision", "-1234.56789012345");
        C!PGtext("first line\nsecond line", "text", "'first line\nsecond line'");
        C!PGtext("12345 ", "char(6)", "'12345'");
        C!PGtext("12345", "varchar(6)", "'12345'");
        C!PGtext(null, "text", "''");
        C!(Nullable!PGtext)(Nullable!string.init, "text", null);
        C!PGbytea([0x44, 0x20, 0x72, 0x75, 0x6c, 0x65, 0x73, 0x00, 0x21],
            "bytea", r"E'\\x44 20 72 75 6c 65 73 00 21'"); // "D rules\x00!" (ASCII)
        C!PGuuid(UUID("8b9ab33a-96e9-499b-9c36-aad1fe86d640"), "uuid", "'8b9ab33a-96e9-499b-9c36-aad1fe86d640'");

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

        // enums tests
        enum Foo { bar, baz }
        enum LongFoo : long { bar, baz }
        enum StringFoo : string { bar = "bar", baz = "baz" }
        C!Foo(Foo.baz, "Int4", "1");
        C!LongFoo(LongFoo.baz, "Int8", "1");
        C!StringFoo(StringFoo.baz, "text", "'baz'");
        C!(Nullable!Foo)(Nullable!Foo(Foo.baz), "Int4", "1");
        C!(Nullable!Foo)(Nullable!Foo.init, "Int4", null);

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
        C!SysTime(SysTime(DateTime(1997, 12, 17, 7, 37, 16), dur!"usecs"(12), testTZ), "timestamptz", "'1997-12-17 07:37:16.000012+02'");

        // json
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string")]), "json", `'{"float_value": 123.456,"text_str": "text string"}'`);
        C!(Nullable!PGjson)(Nullable!Json(Json(["foo": Json("bar")])), "json", `'{"foo":"bar"}'`);

        // json as string
        C!string(`{"float_value": 123.456}`, "json", `'{"float_value": 123.456}'`);

        // jsonb
        C!PGjson(Json(["float_value": Json(123.456), "text_str": Json("text string"), "abc": Json(["key": Json("value")])]), "jsonb",
            `'{"float_value": 123.456, "text_str": "text string", "abc": {"key": "value"}}'`);

        // Geometric
        import dpq2.conv.geometric: GeometricInstancesForIntegrationTest, toValue;
        mixin GeometricInstancesForIntegrationTest;

        C!Point(Point(1,2), "point", "'(1,2)'");
        C!PGline(Line(1,2,3), "line", "'{1,2,3}'");
        C!LineSegment(LineSegment(Point(1,2), Point(3,4)), "lseg", "'[(1,2),(3,4)]'");
        C!Box(Box(Point(1,2),Point(3,4)), "box", "'(3,4),(1,2)'"); // PG handles box ordered as upper right first and lower left next
        C!TestPath(TestPath(true, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'((1,1),(2,2),(3,3))'");
        C!TestPath(TestPath(false, [Point(1,1), Point(2,2), Point(3,3)]), "path", "'[(1,1),(2,2),(3,3)]'");
        C!Polygon(([Point(1,1), Point(2,2), Point(3,3)]), "polygon", "'((1,1),(2,2),(3,3))'");
        C!TestCircle(TestCircle(Point(1,2), 10), "circle", "'<(1,2),10>'");
    }
}
