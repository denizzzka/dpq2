module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;

struct Field( T, string sqlName, string sqlPrefix = "", string decl = "", string PGtypeCast = "" )
{
    alias T type;
    
    static string sql() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\""~
            ( PGtypeCast.length ? "::"~PGtypeCast : "" );
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
    
    @disable
    private static string GenFieldsEnum() nothrow
    {
        return joinFieldString!("toDecl")(", ");
    }
    
    //mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
}

struct RowFields( A, TL ... )
{
    Fields!(TL) fields;
    alias fields this;
    
    const A answer;
    
    this( const A a ) { answer = a; }
    
    //@property void answer( A a ) { _answer = a; }
    
    @property
    private auto getVal( size_t n )()
    {
        return answer.opIndex(n).as!( TL[n].type );
    }
    
    @property
    private bool isNULL( size_t n )()
    {
        return answer.isNULL( n );
    }
    
    private static string GenProperties()
    {
        string r;
        foreach( i, T; TL )
        {
            r ~= "@property auto "~T.toDecl()~"(){ return getVal!("~to!string(i)~"); }";
            r ~= "@property auto "~T.toDecl()~"_isNULL(){ return isNULL!("~to!string(i)~"); }";            
        }
        
        return r;
    }
    
    mixin( GenProperties() );
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();
    
    alias
    RowFields!( Row*,
        Field!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        Field!(PGtext, "t2")
    ) f1;
    
    string q = "select "~f1.sql~"
        from (select '123'::integer as t1, 'qwerty'::text as t2) s";
    auto res = conn.exec( q );
        
    foreach( r; res )
    {
        f1 f = f1(&r);
        assert( f.TEXT_FIELD == res[0,0].as!PGtext );
        assert( !f.TEXT_FIELD_isNULL );
        assert( f.t2 == res[0,1].as!PGtext );
    }
}
