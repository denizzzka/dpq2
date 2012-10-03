dpq2
====

(Under development - undocumented functions should be used with care.)

This is yet another attempt to create a good interface to PostgreSQL from the 
D programming language.

It is designed to do not add overhead to the original low level library libpq but
make convenient use PostgreSQL from D.

Features
--------

* Arguments list support
* LISTEN support
* Sending binary data for type bytea

Building
--------

###Requirements:
Currently code builds with compiler dmd 2.060 and GNU make

####Debug version (with debugging symbols and asserts)
    make debug

####Unittest version (see below)
    make unittest

####Release version
    make release

or

    make

Example
-------

```D
auto conn = new Connection;
conn.connString = "dbname=postgres";
conn.connect();

auto res = conn.exec(
    "SELECT now() as current_time, 'abc'::text as field_name,"
    "123 as field_3, 456.78 as field_4"
    );
    
writeln( res[0,3].str );
```
return:
```sh
456.78
```

Unittests
---------

Code contains embedded unittests using a regular functions calls, not using
standard D unittests. (Non standard because that unittests need to pass
parameters of connection to the database in runtime.)

To perform unit test it is required access to any PostgreSQL server with
permissions to run SELECT statements.

After building dpq2 with unittests file libdpq2 can be executed. Option "--conninfo"
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

* Async queries support
* Binary reading to native D types
* Thread safe behaviour
* Make code more transparent, CamelCased and Autodoc
