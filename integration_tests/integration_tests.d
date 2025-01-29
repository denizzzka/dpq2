@trusted:

import std.getopt;

import dpq2;
import dynld = dpq2.dynloader;
import conn = dpq2.connection: _integration_test;
import query = dpq2.query: _integration_test;
import query_gen = dpq2.query_gen: _integration_test;
import result = dpq2.result: _integration_test;
import native = dpq2.conv.native_tests: _integration_test;
import bson = dpq2.conv.to_bson: _integration_test;

int main(string[] args)
{
    version(Dpq2_Dynamic)
    {
        dynld._integration_test();
        dynld._initTestsConnectionFactory();
    }
    else version(Test_Dynamic_Unmanaged)
    {
        import derelict.pq.pq;

        DerelictPQ.load();
    }

    string conninfo;
    getopt( args, "conninfo", &conninfo );

    conn._integration_test( conninfo );
    query._integration_test( conninfo );
    query_gen._integration_test( conninfo );
    result._integration_test( conninfo );
    native._integration_test( conninfo );
    bson._integration_test( conninfo );

    return 0;
}
