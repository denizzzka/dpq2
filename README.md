dpq2
====

This is yet another attempt to create a good interface to PostgreSQL from the
D 2.0 programming language.

Features
--------

* LISTEN support
* Sending binary data for type bytea

Building
--------

####Debug version (with debugging symbols)
    make debug

####Unittest version (see below)
    make unittest

####Release version
    make release

or

    make

Usage
-----

```D
auto conn = new Connection;
conn.connect( connArgs( "dbname=postgres", connVariant.SYNC ));

auto res = conn.exec( "SELECT now() as current_time, 'abc'::text as field_name, 123 as field_3, 456.78 as field_4" );
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

```bash
$ ./libdpq2 
```
Connection to usually available database "postgres":
```bash
    $ ./libdpq2 --conninfo "dbname=postgres"
```
Network connection:
```bash
    $ ./libdpq2 --conninfo "host=123.45.67.89 dbname=testdb user=testuser password=123123"
```

TODO
----

* Async queries support
* Binary reading to native D types
* Thread safe behaviour
* Make the code more transparent, CamelCasing and Autodoc
