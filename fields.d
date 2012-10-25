module dpq2.fields;

import dpq2.answer;
import dpq2.libpq;
import std.string;

struct Field
{
    string sqlPrefix;
    string sqlName;
    
    @property
    string toString() nothrow
    {
        return "\""~( sqlPrefix.length ? sqlPrefix~"."~sqlName : sqlName )~"\"";
    }
}

struct Fields( FieldArray )
{
    FieldArray fields;
    
    @property
    string toString()
    {        
        string r = fields[0].toString;
        size_t i = 1;
        
        while ( i < fields.length )
        {
            r ~= ", " ~ fields[i].toString;
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
    
    writeln( fields );
}
