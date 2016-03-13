module dpq2.args;

@trusted:

public import dpq2.types.from_d_types;
public import dpq2.types.from_bson;

import dpq2;

/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    Value[] args; /// SQL command arguments
    ValueFormat resultFormat = ValueFormat.BINARY; /// Result value format

    @property void argsFromArray(in string[] arr)
    {
        args.length = arr.length;

        foreach(i, ref a; args)
            a = toValue(arr[i]);
    }

    @property string preparedStatementName() const { return sqlCommand; }
    @property void preparedStatementName(string s){ sqlCommand = s; }
}

unittest
{
    string s = "test string";
    Value v = toValue(s);

    assert(v.as!string == s);
}
