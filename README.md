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
* Binary reading to native D types
    * Integer and decimal types (except "numeric")
    * Timestamp type (with and without timezone)
* LISTEN support
* Sending binary data for type bytea

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

After build header file libdpq2.di will be created automatically.

Example
-------

```D
import libdpq2.di;

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

Unit tests
----------

Code contains embedded unit tests using a regular functions calls, not using
standard D unit tests. (Non standard because that unit tests need to pass
parameters of connection to the database in runtime.)

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

* Async queries support
* PostGIS binary data support
* Thread safe behaviour
* Make code more transparent, CamelCased and Autodoc
