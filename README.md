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

####Unittest version (executable with --conninfo option for connecting to DB)
    make unittest

####Release version
    make release

or just
    make

TODO
----

* Async queries support
* Binary reading to native D types
* Make the code more transparent, CamelCasing and Autodoc
