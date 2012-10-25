module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

static struct Field( T, string sqlName, string sqlPrefix = "" )
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
    string joinString( string memberName )( string delimiter )
    {
        string r;
        foreach( i, T; TL )
        {
            mixin( "r ~= T." ~ memberName );
            if( i < TL.length-1 ) r ~= delimiter;
        }
        
        return r;
    }
    
    @property
    string toString() nothrow
    {
        return "sd";
        //return joinString!("toString()")(", ");
    }
    
    struct M(F)
    {
        Field!(F) field;
        alias field this;
        size_t columnNum;
    }
    
    /*
    private string GenFieldsEnum() nothrow
    {
        string r;
        foreach( i, T; TL )
        {
            r ~= T.toDecl();
            if( i < TL.length-1 ) r ~= ", ";
        }
        return r;
    }    
    */
    //mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
    
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
    
    Fields!( ft, fs ) f;
    
    string q = "select "~to!string(f)~"
        from (select 123::integer as i, 'qwerty'::text as t) s";
    auto r = conn.exec( q );
    
    import std.stdio;
    writeln( f.toString() );
    writeln( r );
    
    writeln( r[0,1].as!PGtext );
}
