@trusted:

import std.getopt;

import dpq2;
import conn = dpq2.connection: _integration_test;
import native_conn = dpq2.native_conn.connection: _integration_test;
import query = dpq2.query: _integration_test;
import result = dpq2.result: _integration_test;
import native_types = dpq2.conv.to_d_types: _integration_test;
import bson = dpq2.conv.to_bson: _integration_test;

int main(string[] args)
{
    string conninfo;
    getopt( args, "conninfo", &conninfo );

    version(libpq_conn_enabled)
    {
        conn._integration_test( conninfo );
        query._integration_test( conninfo );
    }
    native_conn._integration_test( conninfo );
    result._integration_test( conninfo );
    native_types._integration_test( conninfo );
    bson._integration_test( conninfo );

    return 0;
}
