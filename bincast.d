/// Binary data access templates
module dpq2.bincast;
@trusted:

import dpq2.answer;

import std.conv: to;
import std.bitmanip;
import std.datetime;

import std.stdio;
import std.math: modf;
import std.c.time: tm;


T convert(T)(immutable ubyte[] b)
{
    assert( b.length == T.sizeof );
    // добавить проверку передаваемого сюда типа T (std.traits)
     
    ubyte[T.sizeof] s = b[0..T.sizeof];
	return bigEndianToNative!(T)( s );
}

SysTime* getTime( immutable ubyte[] b )
{
    ulong pre_time = convert!(ulong)( b );
    return new SysTime( pre_time * 10 );
}

// Supported PostgreSQL binary types
alias short  PGsmallint; /// smallint
alias int    PGinteger; /// integer
alias long   PGbigint; /// bigint
alias float  PGreal; /// real
alias double PGdouble_precision; /// double precision

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
        "-12.3456::real, "
        "-1234.56789012345::double precision, "
        "'2012-10-04 11:00:21.227803+08'::timestamp with time zone, "
        "'2012-10-04 11:00:21.227803+08'::timestamp without time zone, "
        "'2012-10-04 11:00:21.227803+00'::timestamp with time zone, "
        "'2012-10-04 11:00:21.227803+00'::timestamp without time zone";

    auto r = conn.exec( p );

    assert( convert!( PGsmallint )( r[0,0].bin ) == -32761 );
    assert( convert!( PGinteger )( r[0,1].bin ) == -2147483646 );
    assert( convert!( PGbigint )( r[0,2].bin ) == -9223372036854775806 );
    assert( convert!( PGreal )( r[0,3].bin ) == -12.3456f );
    assert( convert!( PGdouble_precision )( r[0,4].bin ) == -1234.56789012345 );

    writeln( convert!( long )( r[0,5].bin ) );
    writeln( convert!( long )( r[0,6].bin ) );
    writeln( convert!( long )( r[0,7].bin ) );
    writeln( convert!( long )( r[0,8].bin ) );

    writeln( r[0,5].bin );
    writeln( r[0,6].bin );
    writeln( r[0,7].bin );
    
    writeln( getTime( r[0,5].bin ).toSimpleString() );
    writeln( getTime( r[0,6].bin ).toSimpleString() );
    writeln( getTime( r[0,7].bin ).toSimpleString() );
    writeln( getTime( r[0,8].bin ).toSimpleString() );
}
