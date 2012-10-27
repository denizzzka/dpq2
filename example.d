#!/usr/bin/env rdmd

import dpq2.answer;
import std.stdio: writeln;

void main()
{
    Connection conn = new Connection;
    conn.connString = "dbname=postgres";
    conn.connect();

    // Text query result
    auto s = conn.exec(
        "SELECT now() as current_time, 'abc'::text as field_name, "
        "123 as field_3, 456.78 as field_4"
        );
        
    writeln( "1: ", s[0][3].as!PGtext );

    // Binary query result
    static queryArg arg;
    queryParams p;
    p.resultFormat = dpq2.answer.valueFormat.BINARY;
    p.sqlCommand = "SELECT "
        "-1234.56789012345::double precision, "
        "'2012-10-04 11:00:21.227803+08'::timestamp with time zone, "
        "'first line\nsecond line'::text, "
        "NULL, "
        "array[1, 2, NULL]::integer[]";
    
    
    auto r = conn.exec( p );    
 
    writeln( "2: ", r[0][0].as!PGdouble_precision );
    writeln( "3: ", r[0][1].as!PGtime_stamp.toSimpleString );
    writeln( "4: ", r[0][2].as!PGtext );
    writeln( "5: ", r[0].isNULL(3) );
    writeln( "6: ", r[0][4].asArray.getValue(1).as!PGinteger );
    writeln( "7: ", r[0][4].asArray.isNULL(0) );
    writeln( "8: ", r[0][4].asArray.isNULL(2) );
}
