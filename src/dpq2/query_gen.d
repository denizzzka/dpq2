/// Generates SQL query with appropriate variable types
module dpq2.query_gen;

import dpq2.args: QueryParams;
import dpq2.connection: Connection;
import std.conv: to;
import std.traits: isInstanceOf;
import std.array: appender;
import dpq2.conv.from_d_types: toValue;

private enum ArgLikeIn
{
    INSERT, // looks like "FieldName" and passes value as appropriate variable
    UPDATE, // looks like "FieldName" = $3 and passes value into appropriate dollar variable
}

private struct Arg(ArgLikeIn _argLikeIn, T)
{
    enum argLikeIn = _argLikeIn;

    string name;
    T value;
}

private struct DollarArg(T)
{
    T value;
}

/// INSERT-like argument
auto i(T)(string statementArgName, T value)
{
    return Arg!(ArgLikeIn.INSERT, T)(statementArgName, value);
}

/// UPDATE-like argument
auto u(T)(string statementArgName, T value)
{
    return Arg!(ArgLikeIn.UPDATE, T)(statementArgName, value);
}

/// Argument representing dollar, usable in SELECT statements
auto d(T)(T value)
{
    return DollarArg!T(value);
}

private struct CTStatement(SQL_CMD...)
{
    QueryParams qp;
    alias qp this;

    this(Connection conn, SQL_CMD sqlCmd)
    {
        qp = parseSqlCmd!SQL_CMD(conn, sqlCmd);
    }
}

private string dollarsString(size_t num)
{
    string ret;

    foreach(i; 1 .. num+1)
    {
          ret ~= `$`;
          ret ~= i.to!string;

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
        val.length &&
        appender.data.length &&
        val[0].symbolNeedsDelimit &&
        appender.data[$-1].symbolNeedsDelimit
    )
        appender ~= ' ';

    appender ~= val;
}

private string escapeName(string s, Connection conn)
{
    if(conn !is null)
        return conn.escapeIdentifier(s);
    else
        return '"'~s~'"';
}

private QueryParams parseSqlCmd(SQL_CMD...)(Connection conn, SQL_CMD sqlCmd)
{
    QueryParams qp;
    auto resultSql = appender!string;

    foreach(i, V; sqlCmd)
    {
        // argument variable is found?
        static if(isStatementArg!(typeof(V)))
        {
            // previous argument already was processed?
            static if(i > 0 && isStatementArg!(typeof(sqlCmd[i-1])))
            {
                resultSql ~= `,`;
            }

            static if(isInstanceOf!(DollarArg, typeof(V)))
            {
                resultSql.concatWithDelimiter(`$`);
                resultSql ~= (qp.args.length + 1).to!string;
            }
            else static if(V.argLikeIn == ArgLikeIn.UPDATE)
            {
                resultSql ~= V.name.escapeName(conn);
                resultSql ~= `=$`;
                resultSql ~= (qp.args.length + 1).to!string;
            }
            else static if(V.argLikeIn == ArgLikeIn.INSERT)
            {
                resultSql ~= V.name.escapeName(conn);
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

///
auto wrapStatement(C : Connection, T...)(C conn, T statement)
{
    return CTStatement!T(conn, statement);
}

///
auto wrapStatement(T...)(T statement)
if(!is(T[0] == Connection))
{
    return CTStatement!T(null, statement);
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
            u(`boolean_field`, true),
            u(`integer_field`, 123),
            u(`text_field`, `abc`),
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
            i(`integer_field`, integer),
            i(`text_field`, text),
        `) WHERE`,
            u(`integer_field`, another_integer),
        `VALUES(`, Dollars(),`)`
    );

    assert(stmnt.qp.sqlCommand.length > 10);
    assert(stmnt.qp.args[0] == 123.toValue);
    assert(stmnt.qp.args[1] == `abc`.toValue);
    assert(stmnt.qp.args[2] == 456.toValue);
}

version(integration_tests)
void _integration_test(string connParam)
{
    auto conn = new Connection(connParam);
    auto stmnt = wrapStatement(conn, i("Some Integer", 123));

    assert(stmnt.qp.sqlCommand == `"Some Integer"`);
    assert(stmnt.qp.args.length == 1);
    assert(stmnt.qp.args[0] == 123.toValue);
}
