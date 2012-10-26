module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;

struct Field( T, string sqlName, string sqlPrefix = "", string decl = "" )
{
    alias T type;
    
    static string sql() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\"";
    }
    
    alias sql toString;
    
    static string toDecl() pure nothrow
    {
        return decl.length ? decl : (sqlPrefix.length ? sqlPrefix~"_"~sqlName : sqlName);
    }
}

struct Fields( TL ... )
{
    private static
    string joinFieldString( string memberName )( string delimiter )
    {
        string r;
        foreach( i, T; TL )
        {
            mixin( "r ~= T." ~ memberName ~ "();" );
            if( i < TL.length-1 ) r ~= delimiter;
        }
        
        return r;
    }
    
    @property
    static string sql() nothrow
    {
        return joinFieldString!("sql")(", ");
    }
    
    alias sql toString;
    
    private static string GenFieldsEnum() nothrow
    {
        return joinFieldString!("toDecl")(", ");
    }
    
    mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
}

struct RowFields( TL ... )
{
    Fields!(TL) fields;
    alias fields this;
    
    Row* _row;
    
    @property
    void row( ref Row r )
    {
        _row = &r;
    }
    
    @property
    auto getVal( size_t n )()
    {
        return _row.opIndex(n).as!( TL[n].type );
    }
    
    private static string GenRowProperties()
    {
        string r;
        foreach( i, T; TL )
            r ~= "@property auto "~T.toDecl()~"()"
                "{return getVal!("~to!string(i)~");}";
        return r;
    }
    
    mixin( GenRowProperties() );
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();
    
    RowFields!(
        Field!(PGtext, "t1", "", "TEXT_FIELD" ),
        Field!(PGtext, "t2")
    ) f;
    
    string q = "select "~f.sql~"
        from (select '123'::text as t1, 'qwerty'::text as t2) s";
    auto res = conn.exec( q );
        
    foreach( r; res )
    {
        f.row = r;
        assert( f.TEXT_FIELD == res[0,0].as!PGtext );
        assert( f.t2 == res[0,1].as!PGtext );
    }
}
