/// Generates SQL query with appropriate variable types
module dpq2.query_gen;

import dpq2.args: QueryParams;
import std.conv: to;
import std.traits: isInstanceOf;
import std.array: appender;
import dpq2.conv.from_d_types: toValue;

private enum ArgLikeIn
{
    INSERT, // looks like "FieldName" and passes value as appropriate variable
    UPDATE, // looks like "FieldName" = $3 and passes value into appropriate dollar variable
}

private struct Arg(ArgLikeIn _argLikeIn, string _name, T)
{
    enum argLikeIn = _argLikeIn;
    enum name = _name;

    T value;
}

private struct DollarArg(T)
{
    T value;
}

/// INSERT-like argument
auto i(string statementArgName, T)(T value)
{
    //FIXME: wrong way quotes adding
    return Arg!(ArgLikeIn.INSERT, '"'~statementArgName~'"', T)(value);
}

/// UPDATE-like argument
auto u(string statementArgName, T)(T value)
{
    return Arg!(ArgLikeIn.UPDATE, '"'~statementArgName~'"', T)(value);
}

/// Argument representing dollar, usable in SELECT statements
auto d(T)(T value)
{
    return DollarArg!T(value);
}

private struct CTStatement(SQL_CMD...)
{
    QueryParams qp;

    this(SQL_CMD sqlCmd)
    {
        qp = parseSqlCmd!SQL_CMD(sqlCmd);
    }
}

private string dollarsString(size_t num)
{
    string ret; //TODO: replace by compile-time enum string

    foreach(i; 1 .. num+1)
    {
          ret ~= `$`~i.to!string; //TODO: appender or CT

          if(i < num)
                ret ~= `,`;
    }

    return ret;
}

private template isStatementArg(T)
{
    enum isStatementArg = 
        isInstanceOf!(Arg, T) ||
        isInstanceOf!(DollarArg, T);
}

private bool symbolNeedsDelimit(dchar c)
{
    import std.ascii: isAlphaNum;

    return c == '$' || c.isAlphaNum;
}

private void concatWithDelimiter(A, T)(ref A appender, T val)
{

    if(
        val.length && val[0].symbolNeedsDelimit &&
        appender.data.length && appender.data[$-1].symbolNeedsDelimit
    )
        appender ~= ' ';

    appender ~= val;
}

private QueryParams parseSqlCmd(SQL_CMD...)(SQL_CMD sqlCmd)
{
    QueryParams qp;
    auto resultSql = appender!string;

    foreach(i, V; sqlCmd)
    {
        // argument variable is found?
        static if(isStatementArg!(typeof(V)))
        {
            // previous argument already was processed?
            static if(isStatementArg!(typeof(sqlCmd[i-1])))
            {
                resultSql ~= `,`;
            }

            static if(isInstanceOf!(DollarArg, typeof(V)))
            {
                resultSql ~= `$`~(qp.args.length + 1).to!string; //TODO: appender
            }
            else static if(V.argLikeIn == ArgLikeIn.UPDATE)
            {
                resultSql ~= V.name~`=$`~(qp.args.length + 1).to!string; //FIXME: forgot quotes?
            }
            else static if(V.argLikeIn == ArgLikeIn.INSERT)
            {
                resultSql ~= V.name;
            }
            else
                static assert(false);

            qp.args ~= V.value.toValue;
        }
        else
        {
            // Usable as INSERT VALUES ($1, $2, ...) argument
            static if(is(typeof(V) == Dollars))
            {
                resultSql ~= dollarsString(qp.args.length);
            }
            else
            {
                // ordinary part of SQL statement
                resultSql.concatWithDelimiter(V);
            }
        }
    }

    qp.sqlCommand = resultSql[];

    return qp;
}

struct Dollars {}

auto wrapStatement(T...)(T statement) {
    return CTStatement!T(statement);
}

unittest
{
    auto stmnt = wrapStatement(`abc=`, d(123));

    assert(stmnt.qp.sqlCommand == `abc=$1`);
    assert(stmnt.qp.args.length == 1);
    assert(stmnt.qp.args[0] == 123.toValue);
}

unittest
{
    auto stmnt = wrapStatement(
        `SELECT`, d!string("abc"), d!int(123)
    );

    assert(stmnt.qp.args.length == 2);
    assert(stmnt.qp.args[0] == "abc".toValue);
    assert(stmnt.qp.args[1] == 123.toValue);
}

unittest
{
    auto stmnt = wrapStatement(
        `UPDATE table1`,
        `SET`,
            u!`boolean_field`(true),
            u!`integer_field`(123),
            u!`text_field`(`abc`),
    );

    assert(stmnt.qp.sqlCommand.length > 10);
    assert(stmnt.qp.args.length == 3);
    assert(stmnt.qp.args[0] == true.toValue);
    assert(stmnt.qp.args[1] == 123.toValue);
    assert(stmnt.qp.args[2] == `abc`.toValue);
}

unittest
{
    int integer = 123;
    int another_integer = 456;
    string text = "abc";

    auto stmnt = wrapStatement(
        `INSERT INTO table1 (`,
            i!`integer_field`(integer),
            i!`text_field`(text),
        `) WHERE`,
            u!`integer_field`(another_integer),
        `VALUES(`, Dollars(),`)`
    );

    assert(stmnt.qp.sqlCommand.length > 10);
    assert(stmnt.qp.args[0] == 123.toValue);
    assert(stmnt.qp.args[1] == `abc`.toValue);
    assert(stmnt.qp.args[2] == 456.toValue);
}
