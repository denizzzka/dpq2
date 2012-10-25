module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

struct Field( T, string sqlPrefix, string sqlName )
{
    @property
    string toString() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\"";
    }
    
    @property
    string toDecl() pure nothrow
    {
        return sqlPrefix.length ? sqlPrefix~"_"~sqlName : sqlName;
    }
}

struct Fields( TL ... )
{
    void static_this()
    {
        foreach( i, T; TL ){}
            //T.columnNum = i;
    }
    
    @property
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
    
    struct M(F)
    {
        Field!(F) field;
        alias field this;
        size_t columnNum;
    }
    
    
    
    //@property
    //size_t columnNum()
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    Field!(PGtext, "", "i") ft;
    Field!(PGinteger, "", "t") fs;
    
    Fields!( ft, fs ) f;
    
    string q = "select "~to!string(f)~"
        from (select 123::integer as i, 'qwerty'::text as t) s";
    auto r = conn.exec( q );
    
    import std.stdio;
    writeln( f.toString() );
    writeln( r );
    
    writeln( r[0,1].as!PGtext );
}
