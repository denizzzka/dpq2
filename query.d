module dpq2.query;
@trusted:

import dpq2.libpq;
import dpq2.connection;
import dpq2.answer;

final class Connection: BaseConnection
{
    answer exec(string sql_command) {
        return new answer(
            PQexec(conn, toStringz(sql_command))
        );
	}

	answer exec(ref const query_params p) {
		
		// code above just preparing args for PQexecParams
		Oid[] types = new Oid[p.args.length];
		int[] formats = new int[p.args.length];
		int[] lengths = new int[p.args.length];
		const(byte)*[] values = new const(byte)*[p.args.length];

		for( int i = 0; i < p.args.length; ++i ) {
			types[i] = p.args[i].type;
			formats[i] = p.args[i].format;	
			values[i] = p.args[i].value_bin.ptr;
			
			final switch( p.args[i].format ) {
				case valueFormat.TEXT:
					lengths[i] = to!int( p.args[i].value_str.length );
					break;
				case valueFormat.BINARY:
					lengths[i] = to!int( p.args[i].value_bin.length );
					break;
			}
		}

		return new answer(
			PQexecParams (
				conn,
				toStringz( p.sql_command ),
				to!int( p.args.length ),
				types.ptr,
				values.ptr,
				lengths.ptr,
				formats.ptr,
				p.result_format
			)
		);
	}
}
/*	
	
	/// returns null if no notifies was received
	notify get_next_notify() {
		consume_input();
		auto n = PQnotifies(conn);
		return n is null ? null : new notify(n);
	}

	private void consume_input() {
		int r = PQconsumeInput( conn );
		if( r != consume_result.PQ_CONSUME_OK ) throw new exception();
	}

	private static string PQerrorMessage(PGconn* conn) {
		return to!(string)( dpq2.libpq.PQerrorMessage(conn) );
	}
*/

void external_unittest( string conn_param ) {
	conn_args cd = {
			conn_string: conn_param,
			type: conn_variant.SYNC
		};

    auto conn = new Connection;
    conn.connect( cd );

    string sql_query =
    "select now() as time, 'abc'::text as string, 123, 456.78\n"
    "union all\n"
    "select now(), 'def'::text, 456, 910.11\n"
    "union all\n"
    "select NULL, 'ijk'::text, 789, 12345.115345";

    auto r = conn.exec( sql_query );
    
    alias dpq2.answer.answer.cell_coords cell_coords;
    
    auto c1 = cell_coords(2,1);
    auto c2 = cell_coords(0,0);
    auto c3 = cell_coords(0,2);

    assert( r.rows_num == 3 );
    assert( r.cols_num == 4);
    assert( r.column_format(2) == dpq2.libpq.valueFormat.TEXT );
    assert( r.get_value(c1).str == "456" );
    assert( !r.isNULL( c2 ) );
    assert( r.isNULL( c3 ) );
    assert( r.column_num( "string" ) == 1 );

    auto c = r.get_value( c1 );	
    assert( c.str == "456" );
    /*
    string sql_query2 = "select * from test where t = $1 order by serial";
    static query_arg arg = { value_str: "abc" };
    query_arg[1] args;
    args[0] = arg;
    query_params p;
    p.sql_command = sql_query2;
    p.args = args;

    r = conn.exec( p );		
    assert( r.get_value( c2 ).str == "abc" );
    */
    string sql_query3 = "listen test_notify; notify test_notify";
    r = conn.exec( sql_query3 );
    assert( conn.get_next_notify.name == "test_notify" );

}
