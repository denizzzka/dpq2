/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;
import std.socket: ntohl, ntohs;

T convert(T)(immutable ubyte[] data)
{
    assert( data.length == T.sizeof );

//	return to!(T)( data[0..T.sizeof].ptr );

    auto res = *( cast(T*) data[0..T.sizeof].ptr );

	return ntohs( res );
}

struct PGtypes /// Supported PostgreSQL binary types
{
    alias short PGsmallint; /// smallint
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
        "32761::smallint, "
        "2::smallint";

    auto r = conn.exec( p );
    
    writeln( convert!( PGtypes.PGsmallint )( r[0,0].bin ) );
//    writeln( PGsmallint( r[0,0].bin ) );
//    assert( from_smallint( r[0,0].bin ) == -32761 );
}
