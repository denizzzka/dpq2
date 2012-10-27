module dpq2.fields;

import dpq2.answer;

struct Field( T, string sqlName, string sqlPrefix = "", string decl = "", string PGtypeCast = "" )
{
    alias T type;
    
    static string sql() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"\".\""~sqlName : sqlName )~"\""~
            ( PGtypeCast.length ? "::"~PGtypeCast : "" );
    }
    
    alias sql toString;
    
    static string toDecl() pure nothrow
    {
        return decl.length ? decl : sqlName;
    }
    
    static string toTemplatedName() pure nothrow
    {
        return toDecl();
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
            mixin( "r ~= T." ~ memberName ~ ";" );
            if( i < TL.length-1 ) r ~= delimiter;
        }
        
        return r;
    }
    
    @property
    static string sql() nothrow
    {
        return joinFieldString!("sql()")(", ");
    }
    
    alias sql toString;
    
    @disable
    private static string GenFieldsEnum() nothrow
    {
        return joinFieldString!("toDecl()")(", ");
    }
    
    //mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
}

struct ResultFields( A, TL ... )
if( is( A == Answer) || is( A == Row ) || is( A == Row* ) )
{
    Fields!(TL) fields;
    
    A answer;
    alias answer this;
    alias fields.sql sql;
    alias fields.toString toString;
    
    this( A a ) { answer = a; }
    
    invariant()
    {
        assert( answer.columnCount == TL.length );
    }
    
    static if( !is( A == Answer) )
    {
        private auto getVal( size_t c )() { return answer.opIndex(c).as!( TL[c].type ); }    
        private bool isNULL( size_t c )() { return answer.isNULL( c ); }
        private static string fieldProperties( T, size_t col )()
        {
            return "@property auto getVal(string s)()"
                        "if( s == \""~T.toTemplatedName()~"\" ){ return getVal!("~to!string(col)~")(); }"~
                   "@property auto "~T.toDecl()~"(){ return getVal!("~to!string(col)~")(); }"~
                   "@property auto "~T.toDecl()~"_isNULL(){ return isNULL!("~to!string(col)~")(); }";
        }
    }
    else
    {
        private auto getVal( size_t c )( size_t r ) { return answer.opIndex(r,c).as!( TL[c].type ); }
        private bool isNULL( size_t c )( size_t r ) { return answer.isNULL( r, c ); }
        private static string fieldProperties( T, size_t col )()
        {
            return "@property auto "~T.toDecl()~"(size_t row){ return getVal!("~to!string(col)~")(row); }"~
                   "@property auto "~T.toDecl()~"_isNULL(size_t row){ return isNULL!("~to!string(col)~")(row); }";
        }
        
        alias ResultFields!( Row, TL ) RF; // Row Fields
        
        RF opIndex( size_t rowNum )
        {
            return RF( answer[rowNum] );
        }
        
        @property RF front(){ return opIndex(answer.currRow); }
    }
    
    private static string GenProperties()
    {
        string r;
        foreach( i, T; TL )
            r ~= fieldProperties!( T, i )();
        
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
    ResultFields!( Row,
        Field!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        Field!(PGtext, "t2")
    ) f1;
    
    alias
    ResultFields!( Row*,
        Field!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        Field!(PGtext, "t2")
    ) f2;

    alias
    ResultFields!( Answer,
        Field!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        Field!(PGtext, "t2")
    ) f3;
    
    string q = "select "~f1.sql~"
        from (select '123'::integer as t1, 'qwerty'::text as t2
              union
              select '456',                'asdfgh') s";
    auto res = conn.exec( q );
        
    auto fa = f3(res);
    assert( fa.TEXT_FIELD(0) == res[0,0].as!PGtext );
    assert( !fa.TEXT_FIELD_isNULL(0) );
    assert( fa.t2(0) == res[0,1].as!PGtext );
    
    import std.stdio;
    assert( fa[1].t2 == "asdfgh" );
    
    foreach( f; fa )
    {
        f.getVal!"t2";
        assert( !f.TEXT_FIELD_isNULL );
    }
}
