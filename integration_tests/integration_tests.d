@trusted:

import std.getopt;

import dpq2.all;
import conn = dpq2.connection: _integration_test;
import query = dpq2.query: _integration_test;
import answer = dpq2.answer: _integration_test;

int main(string[] args)
{
    string conninfo;
    getopt( args, "conninfo", &conninfo );
    
    conn._integration_test( conninfo );
    query._integration_test( conninfo );
    answer._integration_test( conninfo );
    
    return 0;
}
