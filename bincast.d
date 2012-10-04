/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;

T convert(T)(immutable ubyte[] data)
{
    assert( data.length == T.sizeof );
	return *( cast(T*)data[0..T.sizeof].ptr );
}

/*
short PGsmallint( immutable byte[] b )
{
    assert( b.length == 2 );
    ushort r = b[1];
    r <<= 8;
    r = b[0];
    return cast(short) r;
}
*/

void _unittest( string connParam )
{
    auto conn = new Connection;
    conn.connString = connParam;
    conn.connect();

    static queryArg arg;
    queryParams p;
    p.resultFormat = valueFormat.BINARY;
    p.sqlCommand = "SELECT "
        "250::smallint, "
        "32761::smallint, "
        "2::smallint";

    auto r = conn.exec( p );
    
    writeln( convert!( short )( r[0,0].bin ) );
//    writeln( PGsmallint( r[0,0].bin ) );
//    assert( from_smallint( r[0,0].bin ) == -32761 );
}
