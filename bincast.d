/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;
import std.bitmanip;

T convert(T)(immutable ubyte[] b)
{
    assert( b.length == T.sizeof );
     
    ubyte[2] s = b[0..b.length];
	return bigEndianToNative!(T)( s );
}

/// Supported PostgreSQL binary types
alias short PGsmallint; /// smallint
alias long  PGbigint; /// bigint

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
        "123::bigint, "
        "2::smallint";

    auto r = conn.exec( p );
    
    writeln( convert!( PGsmallint )( r[0,0].bin ) );

//    assert( convert!( PGtypes.PGsmallint )( r[0,0].bin ) == -32761 );
}
