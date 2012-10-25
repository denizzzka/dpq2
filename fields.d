module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

struct Field
{
    string sqlPrefix;
    string sqlName;
}

struct Fields( FieldArray )
{
    FieldArray fields;
    
    string str()
    {
        string addQuotes( string s ) pure nothrow { return "\""~s~"\""; }
        string fieldName( Field f ) pure nothrow
        {
            return addQuotes(
                f.sqlPrefix.length ? f.sqlPrefix~"."~f.sqlName : f.sqlName
            );
        }
        
        string r = fieldName( fields[0] );
        size_t i = 1;
        
        while ( i < fields.length )
        {
            r ~= ", " ~ fieldName( fields[i] );
            i++;
        }
        
        return r;
    }
}

unittest
{
    Field f;
    f.sqlPrefix = "pr";
    f.sqlName = "asd";
    
    Fields!( Field[2] ) fields;
    
    fields.fields[0] = f;
    fields.fields[1] = f;
    
    import std.stdio;
    
    writeln( fields.str() );
}
