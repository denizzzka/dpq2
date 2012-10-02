module dpq2.answer;
@trusted:

import dpq2.libpq;

import std.conv: to;
import std.string: toStringz;
import std.exception;
import core.exception;

debug import std.stdio: writeln;

class answer {	

	struct cell_coords {
		int col;
		int row;
	}

	struct cell {
		package {
			immutable (byte)* val;
			int size; // currently used only for bin
			debug valueFormat format;
		}

		@property string str(){
			debug enforce( format == valueFormat.TEXT, "Format of the column is not text" );
			return to!string( cast(immutable(char)*)val );
		}

		@property immutable (byte[]) bin(){
			debug enforce( format == valueFormat.BINARY, "Format of the column is not binary" );
			return val[0..size];
		}
	}
	
	private PGresult* res;
    
    private this(){}
    
	package this(PGresult* r){
		res = r;
		enforceEx!OutOfMemoryError(r, "Can't write query result");
		if(!(status == ExecStatusType.PGRES_COMMAND_OK ||
			 status == ExecStatusType.PGRES_TUPLES_OK))
			throw new exception();
	}
	
	~this() {
		PQclear(res);
	}

	ExecStatusType status() {
		return PQresultStatus(res);
	}

	string cmd_status() {
		return to!string( PQcmdStatus(res) );
	}

	int rows_num(){ return PQntuples(res); }

	int cols_num(){ return PQnfields(res); }

	valueFormat column_format( int col_num ) {
		return PQfformat(res, col_num);
    }
    
    int column_num( string column_name ) {    
		int n = PQfnumber(res, toStringz(column_name));
		if( n == -1 )
			throw new exception(exception.exception_types.COLUMN_NOT_FOUND,
								"Column '"~column_name~"' is not found");
		return n;
	}

    cell* get_value( const cell_coords c ) {
		assert_coords(c);
		
		cell* r = new cell;
		r.val = PQgetvalue(res, c.row, c.col);
		r.size = get_value_size( c );
		debug r.format = column_format( c.col );
		return r;
    }

	int get_value_size( const cell_coords c ) {
		assert_coords(c);
		return PQgetlength(res, c.row, c.col);
	}
    
    bool isNULL( const cell_coords c ) {
		assert_coords(c);
		return PQgetisnull(res, c.row, c.col) != 0;
    }

	private void assert_coords( const cell_coords c ) {
		assert( c.row < rows_num, to!string(c.row)~" row is out of range 0.."~to!string(rows_num-1)~" of result rows" );
		assert( c.col < cols_num, to!string(c.col)~" col is out of range 0.."~to!string(rows_num-1)~" of result cols" );
	}

	class exception : Exception {		
		enum exception_types {
			COLUMN_NOT_FOUND
		}
		
		exception_types type;

		string error_msg() {
			return to!string( PQresultErrorMessage(res) );
		}
		
		this( exception_types t, string msg ) {
			type = t;
			super( msg, null, null );
		}
		
		this() {
			super( error_msg~" ("~to!string(status)~")", null, null );
		}			
	}
}

class notify {
	private PGnotify* n;

	this(){}
	this( PGnotify* n ) { this.n = n; }
	~this() { PQfreemem(n); }

	string name() { return to!string( n.relname ); }
	string extra() { return to!string( n.extra ); }
	int pid() { return n.be_pid; }

	invariant(){
		assert( n != null );
	}
}
