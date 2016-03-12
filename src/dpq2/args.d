module dpq2.args;

@trusted:

import dpq2;
import vibe.data.bson;

/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    QueryArg[] args; /// SQL command arguments
    ValueFormat resultFormat = ValueFormat.BINARY; /// Result value format

    @property void argsFromArray(in string[] arr)
    {
        args.length = arr.length;

        foreach(i, ref a; args)
            a.value = arr[i];
    }

    @property string preparedStatementName() const { return sqlCommand; }
    @property void preparedStatementName(string s){ sqlCommand = s; }
}

/// Query argument
struct QueryArg
{
    Oid type = 0;
    package ubyte[] valueBin;
    
    /// s can be null for SQL NULL value
    @property void value(in string s)
    {
        if( s == null )
            valueBin = null;
        else
            valueBin = cast(ubyte[])( s ~ '\0' );
    }

    /// Can return null value for SQL NULL value
    @property string value()
    {
        return to!string((cast(char*) valueBin).fromStringz);
    }

    /// Accepts Bson array as Postgres array argument
    @property void value(in Bson b)
    {
        if(b.isNull)
        {
            valueBin = null;
        }
        else
        {
            assert(b.type == Bson.Type.array, "Bson value should be array type");

            foreach(elem; b)
            {

            }
        }
    }
}

unittest
{
    immutable s = "test string";

    QueryArg q;
    q.value = s;

    assert(q.value == s);
}

private OidType convType(Bson.Type bt)
{
    switch(bt)
    {
        case Bson.Type.string:
            return OidType.Text;

        default:
            assert(false, "Can't convert Bson type "~bt.to!string~" to Oid type");
    }
}
