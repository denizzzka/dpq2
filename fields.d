module dpq2.fields;

import dpq2.answer;

struct Field( string sqlName, string sqlPrefix = "", string decl = "" )
{
    static string sql() pure nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"\".\""~sqlName : sqlName )~"\"";
    }
    
    static string toDecl() pure nothrow
    {
        return decl.length ? decl : sqlName;
    }
    
    alias toDecl toTemplatedName;
    
    static string toArrayElement() pure nothrow
    {
        return addQuotes( toDecl() );
    }
    
    static string addQuotes(string s) pure nothrow { return "\""~s~"\""; }    
}

alias Field QueryField;

struct ResultField( T, string sqlName, string sqlPrefix = "", string decl = "", string PGtypeCast = "" )
{
    alias T type;
    Field!(sqlName, sqlPrefix, decl) field;
    alias field this;
    
    static string sql() nothrow
    {
        return field.sql() ~ ( PGtypeCast.length ? "::"~PGtypeCast : "" );
    }
}

struct Fields( TL ... )
{
    @property static size_t length(){ return TL.length; }
    
    package static
    string joinFieldString( string memberName )( string delimiter )
    {
        string r;
        foreach( i, T; TL )
        {
            mixin( "r ~= " ~ memberName ~ ";" );
            if( i < TL.length-1 ) r ~= delimiter;
        }
        
        return r;
    }
    
    @property
    static string sql() nothrow
    {
        return joinFieldString!("T.sql()")(", ");
    }
    
    @disable
    package static string GenFieldsEnum() nothrow
    {
        return joinFieldString!("T.toDecl()")(", ");
    }
    
    //mixin("enum FieldsEnum {"~GenFieldsEnum()~"}");
}

struct QueryFields( string _name, TL ... )
{
    alias _name name; // TODO: how to write alias name this.name; in templates?
    Fields!(TL) fieldsTuples;
    alias fieldsTuples this;
    
    package static string genArrayElems() nothrow
    {
        return fieldsTuples.joinFieldString!("T.toArrayElement()")(", ");
    }
    
    mixin("auto fields = ["~genArrayElems()~"];");
    
    string opIndex( size_t n )
    {
        return fields[n];
    }
}

struct QueryFieldsUnity( TL ... )
{
    @property static size_t length()
    {
        size_t l = 0;
        foreach( T; TL )
            l += T.length;
            
        return l;
    }
    
    private static string genDeclArray()
    {
        string s;
        foreach( T; TL )
            s ~= T.genArrayElems()~" ";
        
        return s;
    }
    
    mixin("auto decl = ["~genDeclArray()~"];");
    
    @property
    static string sql( string name )()
    {
        foreach( T; TL )
            if( T.name == name ) return T.sql();
        
        assert( false, "Name not found" );
    }
    
    @property
    static string dollars( string name )()
    {
        size_t i = 1;
        foreach( T; TL )
        {
            if( T.name != name )
                i += T.length;
            else
                return createDollars( i, T.length );
        }
        assert( false, "Name not found" );
    }
    
    private static string createDollars( size_t startNum, size_t count )
    {
        string r;
        foreach( i; startNum .. startNum + count )
        {
            r ~= "$"~to!string(i);
            if( i < TL.length ) r~=", ";
        }
        return r;
    }
}

struct ResultFields( A, TL ... )
if( is( A == Answer) || is( A == Row ) || is( A == Row* ) )
{
    Fields!(TL) fields;
    
    A answer;
    alias answer this;
    alias fields.sql sql;
    
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
    
    alias QueryField F;    
    alias QueryFields!( "QFS1",
        F!("t1")
    ) QF;
    
    QueryFieldsUnity!( QF ) qf;
    
    assert( qf.sql!("QFS1") == `"t1"` );
    assert( qf.dollars!("QFS1") == "$1" );
    assert( qf.length == 1 );
    assert( qf.decl[0] == "t1" );
    
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
    
    queryParams p;
    p.sqlCommand = 
        "select "~f1.sql~"
         from (select '123'::integer as t1, 'qwerty'::text as t2
               union
               select '456',                'asdfgh') s
         where "~qf.sql!("QFS1")~" = "~qf.dollars!("QFS1");
         
    queryArg arg;
    arg.valueStr = "456";
    p.args = [ arg ];
    
    auto res = conn.exec( p );
        
    auto fa = f3(res);
    assert( fa[0].TEXT_FIELD == res[0][0].as!PGtext );
    assert( !fa[0].TEXT_FIELD_isNULL );
    assert( fa[0].t2 == res[0][1].as!PGtext );
    
    assert( fa[0].t2 == "asdfgh" );
    
    foreach( f; fa )
    {
        assert( f.getValue!"t2" == "asdfgh" );
        assert( f.TEXT_FIELD == "456" );
        assert( !f.isNULL!"t2" );
        assert( !f.TEXT_FIELD_isNULL );
    }
}
