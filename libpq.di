// D import file generated from 'libpq.di'
module dpq2.libpq;

pragma(lib, "pq");
pragma(lib, "com_err");

@safe:

import std.c.stdio : FILE;

extern (C) nothrow 
{
    alias uint Oid;
    enum valueFormat 
{
TEXT,
BINARY,
}
    enum ConnStatusType 
{
CONNECTION_OK,
CONNECTION_BAD,
CONNECTION_STARTED,
CONNECTION_MADE,
CONNECTION_AWAITING_RESPONSE,
CONNECTION_AUTH_OK,
CONNECTION_SETENV,
CONNECTION_SSL_STARTUP,
CONNECTION_NEEDED,
}
    enum PostgresPollingStatusType 
{
PGRES_POLLING_FAILED = 0,
PGRES_POLLING_READING,
PGRES_POLLING_WRITING,
PGRES_POLLING_OK,
PGRES_POLLING_ACTIVE,
}
    enum ExecStatusType // used!
{
PGRES_EMPTY_QUERY = 0,
PGRES_COMMAND_OK,
PGRES_TUPLES_OK,
PGRES_COPY_OUT,
PGRES_COPY_IN,
PGRES_BAD_RESPONSE,
PGRES_NONFATAL_ERROR,
PGRES_FATAL_ERROR,
}
    enum PGTransactionStatusType 
{
PQTRANS_IDLE,
PQTRANS_ACTIVE,
PQTRANS_INTRANS,
PQTRANS_INERROR,
PQTRANS_UNKNOWN,
}
    enum PGVerbosity 
{
PQERRORS_TERSE,
PQERRORS_DEFAULT,
PQERRORS_VERBOSE,
}
    struct PGconn
{
}
    struct PGresult
{
}
    struct PGcancel
{
}
    struct PGnotify
{
    char* relname;
    size_t be_pid;
    char* extra;
    private PGnotify* next;

}
    alias void function(void* arg, PGresult* res) PGnoticeReceiver;
    alias void function(void* arg, char* message) PGnoticeProcessor;
    alias char pqbool;
    struct PQprintOpt
{
    pqbool header;
    pqbool alignment;
    pqbool standard;
    pqbool html3;
    pqbool expanded;
    pqbool pager;
    char* fieldSep;
    char* tableOpt;
    char* caption;
    char** fieldName;
}
    struct PQconninfoOption
{
    char* keyword;
    char* envvar;
    char* compiled;
    char* val;
    char* label;
    char* dispchar;
    int dispsize;
}
    struct PQArgBlock
{
    int len;
    int isint;
    union u
{
    int* ptr;
    int integer;
}
}
    PGconn* PQconnectStart(char* connInfo);
    PostgresPollingStatusType PQconnectPoll(PGconn* conn);
    PGconn* PQconnectdb(immutable char* connInfo); // used!
    PGconn* PQsetdbLogin(char* pghost, char* pgport, char* pgoptions, char* pgtty, char* dbName, char* login, char* pwd);
    void PQfinish(PGconn* conn);
    PQconninfoOption* PQconndefaults();
    void PQconninfoFree(PQconninfoOption* connOptions);
    int PQresetStart(PGconn* conn);
    PostgresPollingStatusType PQresetPoll(PGconn* conn);
    void PQreset(PGconn* conn);
    PGcancel* PQgetCancel(PGconn* conn);
    void PQfreeCancel(PGcancel* cancel);
    int PQcancel(PGcancel* cnacel, char* errbuff, int errbufsize);
    int PQrequestCancel(PGconn* conn);
    char* PQdb(PGconn* conn);
    char* PQuser(PGconn* conn);
    char* PQpass(PGconn* conn);
    char* PQhost(PGconn* conn);
    char* PQport(PGconn* conn);
    char* PQtty(PGconn* conn);
    char* PQoptions(PGconn* conn);
    ConnStatusType PQstatus(PGconn* conn); // used!
    PGTransactionStatusType PQtransactionStatus(PGconn* conn);
    char* PQparameterStatus(PGconn* conn, char* paramName);
    int PQprotocolVersion(PGconn* conn);
    int PQserverVersion(PGconn* conn);
    char* PQerrorMessage(PGconn* conn);
    int PQsocket(PGconn* conn);
    int PQbackendPID(PGconn* conn);
    int PQclientEncoding(PGconn* conn);
    int PQsetClientEncoding(PGconn* conn, char* encoding);
    void* PQgetssl(PGconn* conn);
    void PQinitSSL(int do_init);
    PGVerbosity PQsetErrorVerbosity(PGconn* conn, PGVerbosity verbosity);
    void PQtrace(PGconn* conn, FILE* debug_port);
    void PQuntrace(PGconn* conn);
    alias void function(void* arg, PGresult* res) PQnoticeReceiver;
    alias void function(void* arg, char* message) PQnoticeProcessor;
    PQnoticeReceiver PQsetNoticeReceiver(PGconn* conn, PQnoticeReceiver proc, void* arg);
    PQnoticeProcessor PQsetNoticeProcessor(PGconn* conn, PQnoticeProcessor proc, void* arg);
    alias void function(int acquire) pgthreadlock_t;
    pgthreadlock_t PQregisterThreadLock(pgthreadlock_t newhandler);
    immutable (PGresult)* PQexec(PGconn* conn, const char* query); // used!
    immutable (PGresult)* PQexecParams(PGconn* conn, const char* command, size_t nParams, Oid* paramTypes, const ubyte** paramValues, size_t* paramLengths, size_t* paramFormats, size_t resultFormat); // used!
    PGresult* PQprepare(PGconn* conn, char* stmtName, char* query, int nParams, Oid* paramTypes);
    PGresult* PQexecPrepared(PGconn* conn, char* stmtName, int nParams, char** paramValues, int* paramLengths, int* paramFormats, int resultFormat);
    int PQsendQuery(PGconn* conn, char* query);
    int PQsendQueryParams(PGconn* conn, char* command, int nParams, Oid* paramTypes, char** paramValues, int* paramLengths, int* paramFormats, int resultFormat);
    int PQsendPrepare(PGconn* conn, char* stmtName, char* query, int nParams, Oid* paramTypes);
    int PQsendQueryPrepared(PGconn* conn, char* stmtName, int nParams, char** paramValues, int* paramLengths, int* paramFormats, int resultFormat);
    PGresult* PQgetResult(PGconn* conn);
    int PQisBusy(PGconn* conn);
    int PQconsumeInput(PGconn* conn);
    immutable (PGnotify)* PQnotifies(PGconn* conn); // used!
    int PQputCopyData(PGconn* conn, char* buffer, int nbytes);
    int PQputCopyEnd(PGconn* conn, char* errormsg);
    int PQgetCopyData(PGconn* conn, char** buffer, int async);
    int PQgetline(PGconn* conn, char* string, int length);
    int PQputline(PGconn* conn, char* string);
    int PQgetlineAsync(PGconn* conn, char* buffer, int bufsize);
    int PQputnbytes(PGconn* conn, char* buffer, int nbytes);
    int PQendcopy(PGconn* conn);
    int PQsetnonblocking(PGconn* conn, int arg);
    int PQisnonblocking(PGconn* conn);
    int PQisthreadsafe();
    int PQflush(PGconn* conn);
    PGresult* PQfn(PGconn* conn, int fnid, int* result_buf, int* result_len, int result_is_int, PQArgBlock* args, int nargs);
    ExecStatusType PQresultStatus( immutable PGresult* res ); // used!
    char* PQresStatus(ExecStatusType status);
    char* PQresultErrorMessage(immutable PGresult* res); // used!
    char* PQresultErrorField(PGresult* res, int fieldcode);
    size_t PQntuples(immutable PGresult* res); // used!
    size_t PQnfields(immutable PGresult* res); // used!
    int PQbinaryTuples(PGresult* res);
    char* PQfname(PGresult* res, int field_num);
    size_t PQfnumber(immutable PGresult* res, immutable char* field_name); // used!
    Oid PQftable(PGresult* res, int field_num);
    int PQftablecol(PGresult* res, int field_num);
    valueFormat PQfformat(immutable PGresult* res, size_t field_num); // used!
    Oid PQftype(immutable PGresult* res, size_t field_num); // used!
    int PQfsize(PGresult* res, int field_num);
    int PQfmod(PGresult* res, int field_num);
    char* PQcmdStatus( immutable PGresult* res); // used!
    char* PQoidStatus(PGresult* res);
    Oid PQoidValue(PGresult* res);
    char* PQcmdTuples(PGresult* res);
    immutable(ubyte)* PQgetvalue(immutable PGresult* res, size_t tup_num, size_t field_num); // used!
    size_t PQgetlength(immutable PGresult* res, size_t tup_num, size_t field_num); // used!
    int PQgetisnull(immutable PGresult* res, size_t tup_num, size_t field_num); // used!
    int PQnparams(PGresult* res);
    Oid PQparamtype(PGresult* res, int param_num);
    PGresult* PQdescribePrepared(PGconn* conn, char* stmt);
    PGresult* PQdescribePortal(PGconn* conn, char* portal);
    int PQsendDescribePrepared(PGconn* conn, char* stmt);
    int PQsendDescribePortal(PGconn* conn, char* portal);
    void PQclear(immutable PGresult* res); //used!
    void PQfreemem(void* ptr);
    PGresult* PQmakeEmptyPGresult(PGconn* conn, ExecStatusType status);
    size_t PQescapeStringConn(PGconn* conn, char* to, char* from, size_t length, int* error);
    ubyte* PQescapeByteaConn(PGconn* conn, ubyte* from, size_t from_length, size_t* to_length);
    ubyte* PQunescapeBytea(ubyte* strtext, size_t* retbuflen);
    size_t PQescapeString(char* to, char* from, size_t length);
    ubyte* PQescapeBytea(ubyte* from, size_t from_length, size_t* to_length);
    void PQprint(FILE* fout, PGresult* res, PQprintOpt* ps);
    void PQdisplayTuples(PGresult* res, FILE* fp, int fillAlign, char* fieldSep, int printHeader, int quiet);
    void PQprintTuples(PGresult* res, FILE* fout, int printAttName, int terseOutput, int width);
    int lo_open(PGconn* conn, Oid lobjId, int mode);
    int lo_close(PGconn* conn, int fd);
    int lo_read(PGconn* conn, int fd, char* buf, size_t len);
    int lo_write(PGconn* conn, int fd, char* buf, size_t len);
    int lo_lseek(PGconn* conn, int fd, int offset, int whence);
    Oid lo_creat(PGconn* conn, int mode);
    Oid lo_create(PGconn* conn, Oid lobjId);
    int lo_tell(PGconn* conn, int fd);
    int lo_unlink(PGconn* conn, Oid lobjId);
    Oid lo_import(PGconn* conn, char* filename);
    int lo_export(PGconn* conn, Oid lobjId, char* filename);
    size_t PQlibVersion();
    int PQmblen(char* s, int encoding);
    int PQdsplen(char* s, int encoding);
    int PQenv2encoding();
    char* PQencryptPassword(char* passwd, char* user);
}

