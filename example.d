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
        "123 as field_3, 456.78 as field_4, "
        r"array[ E'\\000', E'\\001', E'\\002' ]::bytea[]"
        );
        
    writeln( "1: ", s[0,3].str );

    // Binary query result
    static queryArg arg;
    queryParams p;
    p.resultFormat = dpq2.answer.valueFormat.BINARY;
    p.sqlCommand = "SELECT "
        "-1234.56789012345::double precision, "
        "'2012-10-04 11:00:21.227803+08'::timestamp with time zone, "
        "'first line\nsecond line'::text";
    auto r = conn.exec( p );    
 
    writeln( "2: ", r[0,0].as!PGdouble_precision );
    writeln( "3: ", r[0,1].as!PGtime_stamp.toSimpleString );
    writeln( "4: ", r[0,2].as!PGtext );
    writeln( "2: ", r[0,0].as!PGbytea );
}
