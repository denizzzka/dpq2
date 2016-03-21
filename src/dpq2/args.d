module dpq2.args;

@safe:

public import dpq2.conv.from_d_types;
public import dpq2.conv.from_bson;

import dpq2;

/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    Value[] args; /// SQL command arguments
    ValueFormat resultFormat = ValueFormat.BINARY; /// Result value format

    /// Useful for simple text-only query params
    /// Postgres infers a data type for the parameter in the same way it would do for an untyped literal string.
    @property void argsFromArray(in string[] arr)
    {
        args.length = arr.length;

        foreach(i, ref a; args)
            a = toValue(arr[i], ValueFormat.TEXT);
    }

    @property string preparedStatementName() const { return sqlCommand; }
    @property void preparedStatementName(string s){ sqlCommand = s; }
}

/// Used as parameters by PQexecParams-like functions
package struct InternalQueryParams
{
    private
    {
        const(string)* sqlCommand;
        Oid[] oids;
        int[] formats;
        int[] lengths;
        const(ubyte)*[] values;
    }

    ValueFormat resultFormat;

    this(in ref QueryParams qp) pure
    {
        sqlCommand = &qp.sqlCommand;
        resultFormat = qp.resultFormat;

        oids = new Oid[qp.args.length];
        formats = new int[qp.args.length];
        lengths = new int[qp.args.length];
        values = new const(ubyte)* [qp.args.length];

        for(int i = 0; i < qp.args.length; ++i)
        {
            oids[i] = qp.args[i].oidType;
            formats[i] = qp.args[i].format;

            if(!qp.args[i].isNull)
            {
                lengths[i] = qp.args[i].data.length.to!int;
                values[i] = qp.args[i].data.ptr;
            }
        }
    }

    /// Values used by PQexecParams-like functions
    const(char)* command() pure const
    {
        return cast(const(char)*) (*sqlCommand).toStringz;
    }

    /// ditto
    const(char)* stmtName() pure const
    {
        return command();
    }

    /// ditto
    int nParams() pure const
    {
        return values.length.to!int;
    }

    /// ditto
    const(Oid)* paramTypes() pure
    {
        return oids.ptr;
    }

    /// ditto
    const(ubyte*)* paramValues() pure
    {
        return values.ptr;
    }

    /// ditto
    const(int)* paramLengths() pure
    {
        return lengths.ptr;
    }

    /// ditto
    const(int)* paramFormats() pure
    {
        return formats.ptr;
    }
}
