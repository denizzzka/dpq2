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
        "SELECT now() as current_time, 'abc'::text as field_name, "
        "123 as field_3, 456.78 as field_4"
        );
    
    writeln( "Text query result: ", s[0][3].as!PGtext );
    
    // Separated arguments query with binary result:
    queryParams p;
    p.sqlCommand = "SELECT "
        "$1::double precision as double_field, "
        "$2::timestamp with time zone as time_field, "
        "$3::text, "
        "$4::text, "
        "$5::integer[] as array_field";
    
    p.args.length = 5;
    
    p.args[0].value = "-1234.56789012345";
    p.args[1].value = "2012-10-04 11:00:21.227803+08";
    p.args[2].value = "first line\nsecond line";
    p.args[3].value = null;
    p.args[4].value = "{1, 2, NULL}";
    
    auto r = conn.exec(p);
    
    writeln( "0: ", r[0]["double_field"].as!PGdouble_precision );
    writeln( "1: ", r[0]["time_field"].as!PGtime_stamp.toSimpleString );
    writeln( "2: ", r[0][2].as!PGtext );
    writeln( "3.1 isNULL: ", r[0].isNULL(3) );
    writeln( "3.2 isNull: ", r[0][3].isNull );
    writeln( "4.1: ", r[0][4].asArray.getValue(1).as!PGinteger );
    writeln( "4.2: ", r[0]["array_field"].asArray.isNULL(0) );
    writeln( "4.3: ", r[0]["array_field"].asArray.isNULL(2) );
    
    version(LDC) delete r; // before Derelict unloads its bindings (prevents SIGSEGV)
}
