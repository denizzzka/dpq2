module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

struct Field( T )
{
    string sqlPrefix;
    string sqlName;
    T value;
    
    //alias as!T as;
    
    @property
    string toString() nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\"";
    }
}

struct Fields( TL ... )
{
    string toString()
    {
        string r;
        foreach( i, T; TL )
        {
            r ~= T.toString();
            if( i < TL.length-1 ) r ~= ", ";
        }
        
        return r;
    }
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    Field!(PGtext) ft;
    ft.sqlPrefix = "";
    ft.sqlName = "i";
    
    Field!(PGinteger) fs;
    fs.sqlPrefix = "";
    fs.sqlName = "t";
    
    Fields!( ft, fs ) f;
    
    string q = "select "~to!string(f)~"
        from (select 123::integer as i, 'qwerty'::text as t) s";
    auto r = conn.exec( q );
    
    import std.stdio;
    writeln( f.toString() );
    writeln( r );
}
