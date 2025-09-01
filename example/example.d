#!/usr/bin/env rdmd

import dpq2;
import std.getopt;
import std.stdio: writeln;
import std.typecons: Nullable;
import std.variant: Variant;
import vibe.data.bson;

void main(string[] args)
{
    string connInfo;
    getopt(args, "conninfo", &connInfo);

    Connection conn = new Connection(connInfo);

    // Only text query result can be obtained by this call:
    auto answer = conn.exec(
        "SELECT now()::timestamp as current_time, 'abc'::text as field_name, "~
        "123 as field_3, 456.78 as field_4, '{\"JSON field name\": 123.456}'::json"
        );

    writeln( "Text query result by name: ", answer[0]["current_time"].as!string );
    writeln( "Text query result by index: ", answer[0][3].as!string );

    // It is possible to read values of unknown type using BSON:
    auto firstRow = answer[0];
    foreach(cell; rangify(firstRow))
    {
        writeln("bson: ", cell.as!Bson);
    }

    // Binary arguments query with binary result:
    QueryParams p;
    p.sqlCommand = "SELECT "~
        "$1::double precision as double_field, "~
        "$2::text, "~
        "$3::text as null_field, "~
        "array['first', 'second', NULL]::text[] as array_field, "~
        "$4::integer[] as multi_array, "~
        "'{\"float_value\": 123.456,\"text_str\": \"text string\"}'::json as json_value";

    p.argsVariadic(
        -1234.56789012345,
        "first line\nsecond line",
        Nullable!string.init,
        [[1, 2, 3], [4, 5, 6]]
    );

    auto r = conn.execParams(p);
    scope(exit) destroy(r);

    writeln( "0: ", r[0]["double_field"].as!double );
    writeln( "1: ", r.oneRow[1].as!string ); // .oneRow additionally checks that here is only one row was returned
    writeln( "2.1 isNull: ", r[0][2].isNull );
    writeln( "2.2 isNULL: ", r[0].isNULL(2) );
    writeln( "3.1: ", r[0][3].asArray[0].as!string );
    writeln( "3.2: ", r[0][3].asArray[1].as!string );
    writeln( "3.3: ", r[0]["array_field"].asArray[2].isNull );
    writeln( "3.4: ", r[0]["array_field"].asArray.isNULL(2) );
    writeln( "4.1: ", r[0]["multi_array"].asArray.getValue(1, 2).as!int );
    writeln( "4.2: ", r[0]["multi_array"].as!(int[][]) );
    writeln( "5.1 Json: ", r[0]["json_value"].as!Json);
    writeln( "5.2 Bson: ", r[0]["json_value"].as!Bson);

    // It is possible to read values of unknown type
    // using std.variant.Variant or vibe.data.bson.Bson:
    for(auto column = 0; column < r.columnCount; column++)
    {
        writeln(
            "column: '", r.columnName(column), "', ",
            "Variant: ", r[0][column].as!Variant, ", ",
            "Bson: ", r[0][column].as!Bson
        );
    }

    // It is possible to upload CSV data ultra-fast:
    conn.exec("CREATE TEMP TABLE test_dpq2_copy (v1 TEXT, v2 INT)");

    // Init the COPY command. This sets the connection in a COPY receive
    // mode until putCopyEnd() is called. Copy CSV data, because it's standard,
    // ultra fast, and readable:
    conn.exec("COPY test_dpq2_copy FROM STDIN WITH (FORMAT csv)");

    // Write 2 lines of CSV, including text that contains the delimiter.
    // Postgresql handles it well:
    string data = "\"This, right here, is a test\",8\nWow! it works,13\n";
    conn.putCopyData(data);

    // Write 2 more lines
    data = "Horray!,3456\nSuper fast!,325\n";
    conn.putCopyData(data);

    // Signal that the COPY is finished. Let Postgresql finalize the command
    // and return any errors with the data.
    conn.putCopyEnd();
}
