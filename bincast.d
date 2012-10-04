/// Binary data convertation
module dpq2.bincast;
@trusted:

import dpq2.answer;

void _unittest( string connParam )
{
    auto conn = new Connection;
    conn.connString = "dbname=postgres";
    conn.connect();

    auto res = conn.exec(
        "SELECT now() as current_time, 'abc'::text as field_name,"
        "123 as field_3, 456.78 as field_4"
        );
        
    writeln( res[0,3].str );
}
