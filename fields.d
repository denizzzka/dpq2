module dpq2.fields;

import dpq2.answer;

struct Field(string sqlName, string sqlPrefix = "", string decl = "", string PGtypeCast = "" )
{
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
    
    alias toDecl toTemplatedName;
}

struct ResultField( T, string sqlName, string sqlPrefix = "", string decl = "", string PGtypeCast = "" )
{
    alias T type;
    Field!(sqlName, sqlPrefix, decl, PGtypeCast) field;
    alias field this;
}

struct Fields( TL ... )
{
    @property static size_t length(){ return TL.length; }
    string opIndex(size_t n)(){ return TL[n].toDecl(); }
    
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
    
    @property
    static string dollars()
    {
        string r;
        foreach( i; 1..TL.length+1 )
        {
            r ~= "$"~to!string(i);
            if( i < TL.length ) r~=", ";
        }
        return r;
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
    alias fields.dollars dollars;
    alias fields.toString toString;
    
    this( A a ) { answer = a; }
    
    invariant()
    {
        assert( answer.columnCount == TL.length );
    }
    
    static if( is( A == Answer) )
    {
        alias ResultFields!( Row, TL ) RF; // Row Fields
        
        RF opIndex( size_t rowNum )
        {
            return RF( answer[rowNum] );
        }
        
        @property RF front(){ return opIndex(answer.currRow); }
    }
    else
    {
        private auto getVal( size_t c )() { return answer.opIndex(c).as!( TL[c].type ); }    
        private static string fieldProperties( T, size_t col )()
        {
            return "@property auto getValue(string s)()"
                        "if( s == \""~T.toTemplatedName()~"\" ){ return getVal!("~to!string(col)~")(); }"
                   "@property bool isNULL(string s)()"
                        "if( s == \""~T.toTemplatedName()~"\" ){ return answer.isNULL("~to!string(col)~"); }"
                   "@property auto "~T.toDecl()~"(){ return getVal!("~to!string(col)~")(); }"
                   "@property auto "~T.toDecl()~"_isNULL(){ return answer.isNULL("~to!string(col)~"); }";
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
}

void _unittest( string connParam )
{
    auto conn = new Connection;
	conn.connString = connParam;
    conn.connect();
    
    alias
    ResultFields!( Row,
        ResultField!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        ResultField!(PGtext, "t2")
    ) f1;
    
    alias
    ResultFields!( Row*,
        ResultField!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        ResultField!(PGtext, "t2")
    ) f2;

    alias
    ResultFields!( Answer,
        ResultField!(PGtext, "t1", "", "TEXT_FIELD", "text"),
        ResultField!(PGtext, "t2")
    ) f3;
    
    assert( f1.dollars == "$1, $2" );
    
    string q = "select "~f1.sql~"
        from (select '123'::integer as t1, 'qwerty'::text as t2
              union
              select '456',                'asdfgh') s";
    auto res = conn.exec( q );
        
    auto fa = f3(res);
    assert( fa[0].TEXT_FIELD == res[0][0].as!PGtext );
    assert( !fa[0].TEXT_FIELD_isNULL );
    assert( fa[0].t2 == res[0][1].as!PGtext );
    
    import std.stdio;
    assert( fa[1].t2 == "asdfgh" );
    
    foreach( f; fa )
    {
        f.getValue!"t2";
        assert( !f.isNULL!"t2" );
        assert( !f.TEXT_FIELD_isNULL );
    }
}
