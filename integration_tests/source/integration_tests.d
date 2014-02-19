@trusted:

import std.getopt;

import dpq2.all;
import conn = dpq2.connection: integration_test;
import query = dpq2.query: integration_test;
import answer = dpq2.answer: integration_test;

int main(string[] args)
{
    string conninfo;
    getopt( args, "conninfo", &conninfo );

    conn.integration_test( conninfo );
    query.integration_test( conninfo );
    answer.integration_test( conninfo );
    
    return 0;
}
