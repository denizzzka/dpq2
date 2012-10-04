/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

void _unittest( string connParam )
{
    auto conn = new Connection;
    conn.connString = connParam;
    conn.connect();

    static queryArg arg;
    queryParams p;
    p.sqlCommand =
        "SELECT now() as current_time, 'abc'::text as field_name,"
        "123 as field_3, 456.78 as field_4";
    p.resultFormat = valueFormat.BINARY;

    auto r = conn.exec( p );     
//    assert( r[0,2].str == "456" );
}
