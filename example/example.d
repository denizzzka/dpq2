#!/usr/bin/env rdmd

import dpq2.all;
import std.stdio: writeln;

void main()
{
    Connection conn = new Connection;
    conn.connString = "dbname=postgres";
    conn.connect();

    // Only text query result can be obtained by this call:
    auto s = conn.exec(
        "SELECT now() as current_time, 'abc'::text as field_name, "~
        "123 as field_3, 456.78 as field_4"
        );
    
    writeln( "Text query result: ", s[0][3].as!PGtext );
    
    // Separated arguments query with binary result:
    QueryParams p;
    p.sqlCommand = "SELECT "~
        "$1::double precision as double_field, "~
        "$2::text, "~
        "$3::text as null_field, "~
        "array['first', 'second', NULL]::text[] as array_field, "~
        "$4::integer[] as multi_array";
    
    p.args.length = 4;
    
    p.args[0].value = "-1234.56789012345";
    p.args[1].value = "first line\nsecond line";
    p.args[2].value = null;
    p.args[3].value = "{{1, 2, 3}, {4, 5, 6}}";
    
    auto r = conn.exec(p);
    
    writeln( "0: ", r[0]["double_field"].as!PGdouble_precision );
    writeln( "1: ", r[0][1].as!PGtext );
    writeln( "2.1 isNull: ", r[0][2].isNull );
    writeln( "2.2 isNULL: ", r[0].isNULL(2) );
    writeln( "3.1: ", r[0][3].asArray[0].as!PGtext );
    writeln( "3.2: ", r[0][3].asArray[1].as!PGtext );
    writeln( "3.3: ", r[0]["array_field"].asArray[2].isNull );
    writeln( "3.4: ", r[0]["array_field"].asArray.isNULL(2) );
    writeln( "4: ", r[0]["multi_array"].asArray.getValue(1, 2).as!PGinteger );

    // It is possible to read values of unknown type using BSON:
    for(auto column = 0; column < r.columnCount; column++)
    {
        auto cell = r[0][column];
        if(!cell.isNull && !cell.isArray)
            writeln("bson=", cell.toBson);
    }

    version(LDC) destroy(r); // before Derelict unloads its bindings (prevents SIGSEGV)
}
