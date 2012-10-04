/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;

short from_smallint( immutable byte[] b )
{
    assert( b.length == 2 );
    short r = b[0];
    r = r >> 8;
    r = b[1];
    return r;
}

void _unittest( string connParam )
{
    auto conn = new Connection;
    conn.connString = connParam;
    conn.connect();

    static queryArg arg;
    queryParams p;
    p.resultFormat = valueFormat.BINARY;
    p.sqlCommand = "SELECT "
        "-32761::smallint, "
        "2::smallint";

    auto r = conn.exec( p );
    
    writeln( from_smallint( r[0,0].bin ) );
//    assert( from_smallint( r[0,0].bin ) == -32761 );
}
