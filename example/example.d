#!/usr/bin/env rdmd

import dpq2;
import std.stdio: writeln;
import std.getopt;
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

    writeln( "Text query result by name: ", answer[0]["current_time"].as!PGtext );
    writeln( "Text query result by index: ", answer[0][3].as!PGtext );

    // It is possible to read values of unknown type using BSON:
    auto firstRow = answer[0];
    foreach(cell; rangify(firstRow))
    {
        writeln("bson: ", cell.as!Bson);
    }

    // Separated arguments query with binary result:
    QueryParams p;
    p.sqlCommand = "SELECT "~
        "$1::double precision as double_field, "~
        "$2::text, "~
        "$3::text as null_field, "~
        "array['first', 'second', NULL]::text[] as array_field, "~
        "$4::integer[] as multi_array, "~
        "'{\"float_value\": 123.456,\"text_str\": \"text string\"}'::json as json_value";

    p.argsFromArray = [
        "-1234.56789012345",
        "first line\nsecond line",
        null,
        "{{1, 2, 3}, {4, 5, 6}}"
    ];

    auto r = conn.execParams(p);

    writeln( "0: ", r[0]["double_field"].as!PGdouble_precision );
    writeln( "1: ", r[0][1].as!PGtext );
    writeln( "2.1 isNull: ", r[0][2].isNull );
    writeln( "2.2 isNULL: ", r[0].isNULL(2) );
    writeln( "3.1: ", r[0][3].asArray[0].as!PGtext );
    writeln( "3.2: ", r[0][3].asArray[1].as!PGtext );
    writeln( "3.3: ", r[0]["array_field"].asArray[2].isNull );
    writeln( "3.4: ", r[0]["array_field"].asArray.isNULL(2) );
    writeln( "4: ", r[0]["multi_array"].asArray.getValue(1, 2).as!PGinteger );
    writeln( "5.1 Json: ", r[0]["json_value"].as!Json);
    writeln( "5.2 Bson: ", r[0]["json_value"].as!Bson);

    // It is possible to read values of unknown type using BSON:
    for(auto column = 0; column < r.columnCount; column++)
    {
        writeln("column name: '"~r.columnName(column)~"', bson: ", r[0][column].as!Bson);
    }

    version(LDC) destroy(r); // before Derelict unloads its bindings (prevents SIGSEGV)
}
