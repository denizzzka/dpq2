#!/usr/bin/env dub
/+ dub.sdl:
   name "dpq2_example"
   dependency "dpq2" version="*" path="../"
+/

import dpq2;
import std.system;
import std.bitmanip;
import std.getopt;
import std.range;
import std.stdio: writeln;
import std.typecons: Nullable;
import vibe.data.bson;

alias BE = Endian.bigEndian;

int main(string[] args)
{
    string connInfo;
    getopt(args, "conninfo", &connInfo);

    Connection conn;
    try{
        conn = new Connection(connInfo);
    }
    catch(ConnectionException ex){
        writeln(ex.msg);
        writeln("Try adding the arguments:

   '--conninfo postgresql://postgres@/template1' or
   '--conninfo postgresql://postgres@localhost/template1'

to set the DB connection info.  The first version has no host part
and so it tries a local unix-domain socket.");
        return 3;
    }

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

    writeln( "0: ", r[0]["double_field"].as!PGdouble_precision );
    writeln( "1: ", r.oneRow[1].as!PGtext ); // .oneRow additionally checks that here is only one row was returned
    writeln( "2.1 isNull: ", r[0][2].isNull );
    writeln( "2.2 isNULL: ", r[0].isNULL(2) );
    writeln( "3.1: ", r[0][3].asArray[0].as!PGtext );
    writeln( "3.2: ", r[0][3].asArray[1].as!PGtext );
    writeln( "3.3: ", r[0]["array_field"].asArray[2].isNull );
    writeln( "3.4: ", r[0]["array_field"].asArray.isNULL(2) );
    writeln( "4.1: ", r[0]["multi_array"].asArray.getValue(1, 2).as!PGinteger );
    writeln( "4.2: ", r[0]["multi_array"].as!(int[][]) );
    writeln( "5.1 Json: ", r[0]["json_value"].as!Json);
    writeln( "5.2 Bson: ", r[0]["json_value"].as!Bson);

    // It is possible to read values of unknown type using BSON:
    for(auto column = 0; column < r.columnCount; column++)
    {
        writeln("column name: '"~r.columnName(column)~"', bson: ", r[0][column].as!Bson);
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
    writeln("CSV copy-in worked.");


    // It is also possible to send raw binary data.  It's even faster, and can
    // handle any PostgreSQL type, including BYTEA, but it's more complex than
    // sending parsable text streams
    conn.exec("CREATE TEMP TABLE test_dpq2_blob (item BIGINT, data BYTEA)");

    // Init the COPY command, this time for direct binary input
    conn.exec("COPY test_dpq2_blob (item, data) FROM STDIN WITH (FORMAT binary)");

    // For FORMAT binary, send over the 19 byte PostgreSQL header manually
    //                   P    G    C    O    P    Y   \n  255   \r   \n
    conn.putCopyData(cast(ubyte[])[
        0x50,0x47,0x43,0x4F,0x50,0x59,0x0A,0xFF,0x0D,0x0A,0,0,0,0,0,0,0,0,0
    ]);

    // Write 10 rows of variable length binary data. PostgreSQL internal 
    // storage is big endian and the number of values and the length of each
    // must be provided.  Since binary copy-in is likely to be used in 
    // "tight-loop" code, we'll use a stack memory. Stack buffer size is:
    // 
    //   2 bytes for the number of values
    //   plus 4 length bytes for each value
    //   plus total size of all values in the largest row
    //
    enum LOOPS = 10;
    ubyte[2 + 2*4 + 8 + (2*LOOPS + 7)] buf;
    foreach(i;0..LOOPS){
        size_t offset = 0;
        buf[].write!(short, BE)(2, &offset);            // Sending two fields

        buf[].write!(int,   BE)(long.sizeof, &offset);  // BIGINT == long
        buf[].write!(long,  BE)(i, &offset);            // add the item value

        // Generate some data.  Here's we're making the blob larger for each
        // iteration just to emphasize that BYTEA is not fixed length value type.
        ubyte[] blob = iota(cast(ubyte)1, cast(ubyte)(2*i + 7), 1).array;

        buf[].write!(int, BE)(cast(int)blob.length, &offset);
        
        buf[offset..offset+blob.length] = blob;
        offset += blob.length;

        // Send the variable length buffer
        conn.putCopyData(buf[0..offset]);
    }
    
    // Signal that the copy is finished. PostgreSQL will check constraints at
    // this point.
    conn.putCopyEnd();
    writeln("Direct binary copy-in worked.");

    // Read binary blobs back as hex-string data. 
    // For more precise type handling use QueryParams objects with execParams and
    // convert the output using the as!(PGbytea) template from to_d_types.d
    foreach(row; conn.exec("SELECT item, data from test_dpq2_blob").rangify())
        writeln(row[0], ", ", row[1]);

    return 0;
}
