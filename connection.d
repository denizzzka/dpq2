module dpq2.connection;
@trusted:

import dpq2.libpq;
public import dpq2.libpq: valueFormat;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

enum connVariant { SYNC, ASYNC };

struct connArgs {	
	string connString;
	connVariant type;
}

struct queryParams {
	string sqlCommand;
	queryArg[] args;
	valueFormat result_format = valueFormat.TEXT;
}

struct queryArg {
	Oid type = 0;
	valueFormat format = valueFormat.TEXT;
	union {
		byte[] valueBin;
		string valueStr;
	};
}


/*
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
class BaseConnection
{
	package PGconn* conn;
	private bool conn_created_flag;
	private enum ConsumeResult
	{
		PQ_CONSUME_ERROR,
		PQ_CONSUME_OK
	}

	void connect( connArgs args )
	{
		conn = PQconnectdb(toStringz(args.connString));
		
		enforceEx!OutOfMemoryError(conn, "Unable to allocate libpq connection data");
		
		conn_created_flag = true;
		
		if(args.type == connVariant.SYNC &&
		   PQstatus(conn) != ConnStatusType.CONNECTION_OK)
			throw new exception();
	}

	void disconnect()
	{
		if( conn_created_flag )
		{
			conn_created_flag = false;
			PQfinish( conn );
		}
	}

	~this() {
		disconnect();
	}

	package void consumeInput()
	{
		int r = PQconsumeInput( conn );
		if( r != ConsumeResult.PQ_CONSUME_OK ) throw new exception();
	}

	private static string PQerrorMessage(PGconn* conn)
	{
		return to!(string)( dpq2.libpq.PQerrorMessage(conn) );
	}
	
	class exception : Exception
	{
		alias ConnStatusType pq_type; /// libpq conn statuses

		pq_type type;
		
		this() {
			type = PQstatus(conn);
			super( PQerrorMessage(conn), null, null );
		}
	}
}

void external_unittest( string connParam )
{
	connArgs cd = {
		connString: connParam,
		type: connVariant.SYNC
	};
	
	auto c = new BaseConnection;
	c.connect( cd );
	c.disconnect();
}
