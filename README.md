dpq2
====

(Under development - undocumented functions should be used with care.)

This is yet another attempt to create a good interface to PostgreSQL from the 
D programming language.

It is doesn't add overhead to the original low level library libpq but
make convenient use PostgreSQL from D.

Features
--------

* Arguments list support
* Binary and text data queries
* Async queries support
* Reading of the text query results to native D text types
* Representation of the binary query results to native D types
 * Text types
 * Integer and decimal types (except "numeric")
 * Timestamp type (with and without timezone)
* Access to PostgreSQL's multidimensional arrays (only in binary mode)
* LISTEN/NOTIFY support

Building
--------

####Requirements:
Currently code builds with libpq 9.1.0 and higher, compiler dmd 2.060 and GNU make.
```sh
git clone https://github.com/denizzzka/dpq2.git
cd dpq2
```

####Debug version (with debugging symbols and asserts)
    $ make debug

####Unittest version (see below)
    $ make unittest

####Release version
    $ make release

or

    $ make

Example
-------

```D
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
        
    writeln( "1: ", s[0,3].as!PGtext );

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
 
    writeln( "2: ", r[0,0].as!PGdouble_precision );
    writeln( "3: ", r[0,1].as!PGtime_stamp.toSimpleString );
    writeln( "4: ", r[0,2].as!PGtext );
    writeln( "5: ", r.isNULL(0,3) );
    writeln( "6: ", r[0,4].asArray.getValue(1).as!PGinteger );
    writeln( "7: ", r[0,4].asArray.isNULL(0) );
    writeln( "8: ", r[0,4].asArray.isNULL(2) );
}
```
Compile and run:
```sh
$ dmd example.d -Ldpq2/libdpq2.a -L-lpq -L-lcom_err
$ ./example 
1: 456.78
2: -1234.57
3: 0013-Oct-05 03:00:21.227803Z
4: first line
second line
```

Unit tests
----------

Code contains embedded unit tests using a regular functions calls, not using
standard D unit tests. It is because unit tests need to receive parameters of
connection to the database in runtime.

To perform unit test it is required access to any PostgreSQL server with
permissions to run SELECT statements.

After building dpq2 with the unit tests file libdpq2 can be executed. Option "--conninfo"
may contains connection string as described in [PostgreSQL documentation]
(http://www.postgresql.org/docs/current/static/libpq-connect.html#LIBPQ-CONNSTRING).

For default connection to DB type:

```sh
$ ./libdpq2 
```
Connection to usually available database "postgres":
```sh
$ ./libdpq2 --conninfo "dbname=postgres"
```
Network connection:
```sh
$ ./libdpq2 --conninfo "host=123.45.67.89 dbname=testdb user=testuser password=123123"
```

TODO
----

* Row by row result reading
* Binary arguments types
* PostGIS binary data support
* Checking types by Oid
* Make code more transparent, CamelCased and Autodoc
