module dpq2.query;
@trusted:

import dpq2.libpq;
import dpq2.connection;
import dpq2.answer;

class Connection: conn_piece
{    
    answer exec(PGconn* conn, string sql_command) {
        return new answer(
            PQexec(conn, toStringz(sql_command))
        );
    }
}

/*	

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
