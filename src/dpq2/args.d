/// Dealing with query arguments
module dpq2.args;

@safe:

public import dpq2.conv.from_d_types;
public import dpq2.conv.from_bson;

import dpq2.value;
import dpq2.oids: Oid;
import std.conv: to;
import std.string: toStringz;

/// Query parameters
struct QueryParams
{
    string sqlCommand; /// SQL command
    ValueFormat resultFormat = ValueFormat.BINARY; /// Result value format
    private Value[] _args; // SQL command arguments

    /// SQL command arguments
    @property void args(Value[] vargs)
    {
        _args = vargs;
    }

    /// ditto
    @property ref inout (Value[]) args() inout pure return
    {
        return _args;
    }

    /// Fills out arguments from array
    ///
    /// Useful for simple text-only query params
    /// Postgres infers a data type for the parameter in the same way it would do for an untyped literal string.
    @property void argsFromArray(in string[] arr)
    {
        _args.length = arr.length;

        foreach(i, ref a; _args)
            a = toValue(arr[i], ValueFormat.TEXT);
    }

    /// Fills out arguments from variadic arguments
    void argsVariadic(Targs ...)(Targs t_args)
    {
        _args.length = t_args.length;

        static foreach(i, T; Targs)
        {
            _args[i] = toValue!T(t_args[i]);
        }
    }

    /// Access to prepared statement name
    ///
    /// Use it to prepare queries
    // FIXME: it is need to check in debug mode what sqlCommand is used in "SQL command" or "prepared statement" mode
    @property string preparedStatementName() const { return sqlCommand; }
    /// ditto
    @property void preparedStatementName(string s){ sqlCommand = s; }
}

unittest
{
    QueryParams qp;
    qp.argsVariadic(123, "asd", true);

    assert(qp.args[0] == 123.toValue);
    assert(qp.args[1] == "asd".toValue);
    assert(qp.args[2] == true.toValue);
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

    this(in QueryParams* qp) pure
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

                immutable ubyte[] zeroLengthArg = [123]; // fake value, isn't used as argument

                if(qp.args[i].data.length == 0)
                    values[i] = &zeroLengthArg[0];
                else
                    values[i] = &qp.args[i].data[0];
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
        if(oids.length == 0)
            return null;
        else
            return &oids[0];
    }

    /// ditto
    const(ubyte*)* paramValues() pure
    {
        if(values.length == 0)
            return null;
        else
            return &values[0];
    }

    /// ditto
    const(int)* paramLengths() pure
    {
        if(lengths.length == 0)
            return null;
        else
            return &lengths[0];
    }

    /// ditto
    const(int)* paramFormats() pure
    {
        if(formats.length == 0)
            return null;
        else
            return &formats[0];
    }
}
