@trusted:

import std.getopt;

import dpq2;
import conn = dpq2.connection: _integration_test;
import native_conn = dpq2.native_conn.connection: _integration_test;
import query = dpq2.query: _integration_test;
import result = dpq2.result: _integration_test;
import native_types = dpq2.conv.native_tests: _integration_test;
import bson = dpq2.conv.to_bson: _integration_test;

int main(string[] args)
{
    string conninfo;
    string native_host = "localhost";
    ushort native_port = 5432;

    with(std.getopt.config)
    getopt(args,
        required, "conninfo|c", &conninfo,
        required, "native-host|h", &native_host,
        required, "native-port|p", &native_port
    );

    version(libpq_conn_enabled)
    {
        conn._integration_test( conninfo );
        query._integration_test( conninfo );
    }
    native_conn._integration_test(native_host, native_port);
    result._integration_test( conninfo );
    native_types._integration_test( conninfo );
    bson._integration_test( conninfo );

    return 0;
}
