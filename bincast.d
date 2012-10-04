/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;
import std.socket: ntohl, ntohs;

T convert(T)(immutable ubyte[] data)
{
    assert( data.length == T.sizeof );

    auto r = *( cast(T*) data[0..T.sizeof].ptr );

    static if( T.sizeof == 2 )
        r = ntohs( r );
    else if( T.sizeof == 8 )
        r = ntohl( r );
        
	return r;
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
        "-32761::smallint, "
        "2::smallint";

    auto r = conn.exec( p );
    
    writeln( convert!( PGtypes.PGsmallint )( r[0,0].bin ) );

    assert( convert!( PGtypes.PGsmallint )( r[0,0].bin ) == -32761 );
}
