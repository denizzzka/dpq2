module dpq2.connection;
@trusted:

import dpq2.libpq;
public import dpq2.libpq: valueFormat;
import dpq2.answer;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

enum conn_variant { SYNC, ASYNC };

struct conn_args {	
	string conn_string;
	conn_variant type;
}

struct query_params {
	string sql_command;
	query_arg[] args;
	valueFormat result_format = valueFormat.TEXT;
}

struct query_arg {
	Oid type = 0;
	valueFormat format = valueFormat.TEXT;
	union {
		byte[] value_bin;
		string value_str;
	};
}


/**
 * Bugs: On Unix connection is not thread safe.
 * 
 * On Unix, forking a process with open libpq connections can lead
 * to unpredictable results because the parent and child processes share
 * the same sockets and operating system resources. For this reason,
 * such usage is not recommended, though doing an exec from the child
 * process to load a new executable is safe.

TODO: запрет копирования класса conn_piece:

Returns the thread safety status of the libpq library.

int PQisthreadsafe();
Returns 1 if the libpq is thread-safe and 0 if it is not.

 */
class BaseConnection {
	package PGconn* conn;
	private bool conn_created_flag;

	private enum consume_result {
		PQ_CONSUME_ERROR,
		PQ_CONSUME_OK
	}

	void connect( conn_args args ) {
		conn = PQconnectdb(toStringz(args.conn_string));
		
		enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
		
		conn_created_flag = true;
		
		if(args.type == conn_variant.SYNC &&
		   PQstatus(conn) != ConnStatusType.CONNECTION_OK)
			throw new exception();
	}

	~this() {
		if (conn_created_flag) PQfinish( conn );
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
	
	class exception : Exception {
		alias ConnStatusType pq_type; /// libpq conn statuses

		pq_type type;
		
		this() {
			type = PQstatus(conn);
			super( PQerrorMessage(conn), null, null );
		}
	}
}

void external_unittest( string conn_param ) {
	conn_args cd = {
			conn_string: conn_param,
			type: conn_variant.SYNC
		};
		
		auto conn = new BaseConnection;
		conn.connect( cd );
}
