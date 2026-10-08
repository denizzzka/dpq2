///
module dpq2.async.queries;

/// Extends AsyncConnection by adding asynchronous query methods
package mixin template Queries()
{
    import dpq2.args : QueryParams;
    import dpq2.result : Answer, Row, ResponseException;
    import dpq2.value : ValueFormat;
    import derelict.pq.pq : Oid, PGRES_COMMAND_OK;

    /// Perform SQL query to DB
    /// All values are returned in textual
    /// form. This means that the dpq2.conv.to_d_types.as template will likely
    /// not work for anything but strings.
    /// Try to use exec(string, ValueFormat.BINARY) or execParams(QueryParams) instead, even if now parameters are present.
    override immutable(Answer) exec(string sqlCommand)
    {
        return exec(sqlCommand, ValueFormat.TEXT);
    }

    ///
    immutable(Answer) exec(
        string sqlCommand,
        ValueFormat resultFormat
    )
    {
        QueryParams p;
        p.resultFormat = resultFormat;
        p.sqlCommand = sqlCommand;

        return execParams(p);
    }

    /// Perform SQL query to DB
    override immutable(Answer) execParams(scope const ref QueryParams params)
    {
        auto res = runStatementBlockingManner({ sendQueryParams(params); });

        return res.getAnswer;
    }

    /// Submits a command to the server without waiting for the result
    override void sendQuery(string SQLcmd)
    {
        auto p = QueryParams(sqlCommand: SQLcmd);
        sendQueryParams(p);
    }

    /// Row-by-row version of exec
    ///
    /// Delegate called for each received row.
    ///
    /// More info: https://www.postgresql.org/docs/current/libpq-single-row-mode.html
    ///
    void execStatementRbR(
        string sqlCommand,
        void delegate(immutable(Row)) answerRowProcessDg,
        ValueFormat resultFormat = ValueFormat.BINARY
    )
    {
        QueryParams p;
        p.resultFormat = resultFormat;
        p.sqlCommand = sqlCommand;

        execStatementRbR(p, answerRowProcessDg);
    }

    /// Row-by-row version of execParams
    ///
    /// Delegate called for each received row.
    ///
    /// More info: https://www.postgresql.org/docs/current/libpq-single-row-mode.html
    ///
    void execStatementRbR(scope const ref QueryParams params, void delegate(immutable(Row)) answerRowProcessDg)
    {
        runStatementWithRowByRowResult(
            { sendQueryParams(params); },
            answerRowProcessDg
        );
    }

    /// Submits a request to create a prepared statement with the given parameters, and waits for completion.
    ///
    /// Throws an exception if preparing failed.
    void prepareEx(
        string statementName,
        string sqlStatement,
        Oid[] oids = null
    )
    {
        auto r = runStatementBlockingManner(
                {sendPrepare(statementName, sqlStatement, oids);}
            );

        if(r.status != PGRES_COMMAND_OK)
            throw new ResponseException(r, __FILE__, __LINE__);
    }

    /// Submits a request to execute a prepared statement with given parameters, and waits for completion.
    override immutable(Answer) execPrepared(scope const ref QueryParams params)
    {
        auto res = runStatementBlockingManner({ sendQueryPrepared(params); });

        return res.getAnswer;
    }

    /// Row-by-row version of execPrepared
    ///
    /// Delegate called for each received row.
    ///
    /// More info: https://www.postgresql.org/docs/current/libpq-single-row-mode.html
    ///
    void execPreparedRbR(scope const ref QueryParams params, void delegate(immutable(Row)) answerRowProcessDg)
    {
        runStatementWithRowByRowResult(
            { sendQueryPrepared(params); },
            answerRowProcessDg
        );
    }

    /// Submits a request to obtain information about the specified prepared statement, and waits for completion.
    override immutable(Answer) describePrepared(string preparedStatementName)
    {
        auto res = runStatementBlockingManner({ sendDescribePrepared(preparedStatementName); });

        return res.getAnswer;
    }

    override void cancel()
    {
        cancelRequest(requestTimeout);
    }

    deprecated("please use exec(sqlCommand, ValueFormat.BINARY) instead. execStatement() will be removed by 2027")
    immutable(Answer) execStatement(
        string sqlCommand,
        ValueFormat resultFormat = ValueFormat.BINARY
    )
    {
        return exec(sqlCommand, resultFormat);
    }

    deprecated("please use execParams() instead. execStatement() will be removed by 2027")
    immutable(Answer) execStatement(scope const ref QueryParams params)
    {
        return execParams(params);
    }

    deprecated("please use prepareEx() instead. prepareStatement() will be removed by 2027")
    void prepareStatement(
        string statementName,
        string sqlStatement,
        Oid[] oids = null
    )
    {
        prepareEx(statementName, sqlStatement, oids);
    }

    deprecated("please use execPrepared() instead. execPreparedStatement() will be removed by 2027")
    immutable(Answer) execPreparedStatement(scope const ref QueryParams params)
    {
        return execPrepared(params);
    }

    deprecated("please use describePrepared() instead. describePreparedStatement() will be removed by 2027")
    immutable(Answer) describePreparedStatement(string preparedStatementName)
    {
        return describePrepared(preparedStatementName);
    }
}