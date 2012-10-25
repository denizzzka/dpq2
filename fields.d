module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

struct Field( T, string sqlName, string sqlPrefix = "" )
{
    @property
    static string toString() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\"";
    }
    
    @property
    static string toDecl() pure nothrow
    {
        return sqlPrefix.length ? sqlPrefix~"_"~sqlName : sqlName;
    }
}

struct Fields( TL ... )
{
    private static string joinFieldString( string memberName )( string delimiter )
    {
        string r;
        foreach( i, T; TL )
        {
            mixin( "r ~= T." ~ memberName ~ ";" );
            if( i < TL.length-1 ) r ~= delimiter;
        }
        
        return r;
    }
    
    @property
    static string toString() nothrow
    {
        return joinFieldString!("toString()")(", ");
    }
    
    struct M(F)
    {
        Field!(F) field;
        alias field this;
        size_t columnNum;
    }
    
    private static string GenFieldsEnum() nothrow
    {
        return joinFieldString!("toDecl()")(", ");
    }
    
    mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
    
    //@property
    //size_t columnNum()
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();

    immutable Field!(PGtext, "i", "") ft;
    immutable Field!(PGinteger, "t") fs;
    
    Fields!( Field!(PGinteger, "i"), Field!(PGinteger, "t") ) f;
    
    string q = "select "~to!string(f)~"
        from (select 123::integer as i, 'qwerty'::text as t) s";
    auto r = conn.exec( q );
    
    import std.stdio;
    writeln( f.toString() );
    writeln( r );
    
    writeln( r[0,1].as!PGtext );
}
