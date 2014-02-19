@trusted:

import std.getopt;

import dpq2.all;
import conn = dpq2.connection: _unittest;
import query = dpq2.query: _unittest;
import answer = dpq2.answer: _unittest;

int main(string[] args)
{
    string conninfo;
    getopt( args, "conninfo", &conninfo );

    conn._unittest( conninfo );
    query._unittest( conninfo );
    answer._unittest( conninfo );
    
    return 0;
}
