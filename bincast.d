/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;
import std.bitmanip;

T convert(T)(immutable ubyte[] b)
{
    assert( b.length == T.sizeof );
    // добавить проверку передаваемого сюда типа T (std.traits)
     
    ubyte[T.sizeof] s = b[0..T.sizeof];
	return bigEndianToNative!(T)( s );
}

/// Supported PostgreSQL binary types
alias short PGsmallint; /// smallint
alias int   PGinteger; /// integer
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
        "-2147483646::integer, "
        "-9223372036854775806::bigint, "
        "2::smallint";

    auto r = conn.exec( p );
    
//    writeln( convert!( PGsmallint )( r[0,0].bin ) );

    assert( convert!( PGsmallint )( r[0,0].bin ) == -32761 );
    assert( convert!( PGinteger )( r[0,1].bin ) == -2147483646 );
    assert( convert!( PGbigint )( r[0,2].bin ) == -9223372036854775806 );
}
