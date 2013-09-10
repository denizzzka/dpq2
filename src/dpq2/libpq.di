module dpq2.libpq;

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

    enum PGEventId // used
    {
        PGEVT_REGISTER,
        PGEVT_CONNRESET,
        PGEVT_CONNDESTROY,
        PGEVT_RESULTCREATE,
        PGEVT_RESULTCOPY,
        PGEVT_RESULTDESTROY
    }
    
    struct PGEventResultCreate
    {
        PGconn* conn;
        PGresult* result;
    }

    PGconn* PQconnectdb(immutable char* connInfo); // used!
    ConnStatusType PQstatus(PGconn* conn); // used!
    int PQsocket(PGconn* conn); // used!
    void PQfinish(PGconn* conn);
    PGresult* PQexec(PGconn* conn, const char* query); // used!
    int PQsendQuery(PGconn* conn, const char* query); // used!
    int PQsendQueryParams(PGconn* conn, const char* command, int nParams, Oid* paramTypes, const ubyte** paramValues, int* paramLengths, int* paramFormats, int resultFormat); // used!
    PGresult* PQexecParams(PGconn* conn, const char* command, int nParams, Oid* paramTypes, const ubyte** paramValues, int* paramLengths, int* paramFormats, int resultFormat); // used!
    PGresult* PQgetResult(PGconn* conn); // used!
    int PQisBusy(PGconn* conn); // used!
    immutable (PGnotify)* PQnotifies(PGconn* conn); // used!
    int PQsetnonblocking(PGconn* conn, int arg); // used!
    int PQisthreadsafe(); //   
    int PQflush(PGconn* conn); // used!
    ExecStatusType PQresultStatus(const PGresult* res);
    int PQconsumeInput(PGconn* conn);
    char* PQresultErrorMessage(const PGresult* res); // used!
    int PQntuples(const PGresult* res); // used!
    int PQnfields(const PGresult* res); // used!
    int PQfnumber(const PGresult* res, immutable char* field_name); // used!
    valueFormat PQfformat(const PGresult* res, int field_num); // used!
    Oid PQftype(const PGresult* res, int field_num); // used!
    immutable(ubyte)* PQgetvalue(const PGresult* res, int tup_num, int field_num); // used!
    int PQgetlength(const PGresult* res, int tup_num, int field_num); // used!
    int PQgetisnull(const PGresult* res, int tup_num, int field_num); // used!
    char* PQcmdStatus( const PGresult* res); // used!
    void PQclear(const PGresult* res); //used!
    alias int function (PGEventId evtId, void* evtInfo, void* passThrough) PGEventProc; // used!
    int PQregisterEventProc(PGconn *conn, PGEventProc proc, immutable char* name, void *passThrough); // used!
    int PQlibVersion();
    void PQfreemem(void* ptr);
    int PQisnonblocking(PGconn* conn);
    char* PQerrorMessage(PGconn* conn);

    version(FULL_PQ_BINGINGS)
    {
        PGconn* PQconnectStart(char* connInfo);
        PostgresPollingStatusType PQconnectPoll(PGconn* conn);
        PGconn* PQsetdbLogin(char* pghost, char* pgport, char* pgoptions, char* pgtty, char* dbName, char* login, char* pwd);
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
        PGTransactionStatusType PQtransactionStatus(PGconn* conn);
        char* PQparameterStatus(PGconn* conn, char* paramName);
        int PQprotocolVersion(PGconn* conn);
        int PQserverVersion(PGconn* conn);
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
        PGresult* PQprepare(PGconn* conn, char* stmtName, char* query, int nParams, Oid* paramTypes);
        PGresult* PQexecPrepared(PGconn* conn, char* stmtName, int nParams, char** paramValues, int* paramLengths, int* paramFormats, int resultFormat);
        int PQsendPrepare(PGconn* conn, char* stmtName, char* query, int nParams, Oid* paramTypes);
        int PQsendQueryPrepared(PGconn* conn, char* stmtName, int nParams, char** paramValues, int* paramLengths, int* paramFormats, int resultFormat);
        int PQputCopyData(PGconn* conn, char* buffer, int nbytes);
        int PQputCopyEnd(PGconn* conn, char* errormsg);
        int PQgetCopyData(PGconn* conn, char** buffer, int async);
        int PQgetline(PGconn* conn, char* string, int length);
        int PQputline(PGconn* conn, char* string);
        int PQgetlineAsync(PGconn* conn, char* buffer, int bufsize);
        int PQputnbytes(PGconn* conn, char* buffer, int nbytes);
        int PQendcopy(PGconn* conn);
        PGresult* PQfn(PGconn* conn, int fnid, int* result_buf, int* result_len, int result_is_int, PQArgBlock* args, int nargs);
        char* PQresStatus(ExecStatusType status);
        char* PQresultErrorField(PGresult* res, int fieldcode);
        int PQbinaryTuples(PGresult* res);
        char* PQfname(PGresult* res, int field_num);
        Oid PQftable(PGresult* res, int field_num);
        int PQftablecol(PGresult* res, int field_num);
        int PQfsize(PGresult* res, int field_num);
        int PQfmod(PGresult* res, int field_num);
        char* PQoidStatus(PGresult* res);
        Oid PQoidValue(PGresult* res);
        char* PQcmdTuples(PGresult* res);
        int PQnparams(PGresult* res);
        Oid PQparamtype(PGresult* res, int param_num);
        PGresult* PQdescribePrepared(PGconn* conn, char* stmt);
        PGresult* PQdescribePortal(PGconn* conn, char* portal);
        int PQsendDescribePrepared(PGconn* conn, char* stmt);
        int PQsendDescribePortal(PGconn* conn, char* portal);
        PGresult* PQmakeEmptyPGresult(PGconn* conn, ExecStatusType status);
        size_t PQescapeStringConn(PGconn* conn, char* to, char* from, size_t length, int* error);
        ubyte* PQescapeByteaConn(PGconn* conn, ubyte* from, size_t from_length, size_t* to_length);
        ubyte* PQunescapeBytea(ubyte* strtext, size_t* retbuflen);
        size_t PQescapeString(char* to, char* from, size_t length);
        ubyte* PQescapeBytea(ubyte* from, size_t from_length, size_t* to_length);
        char* PQescapeIdentifier(PGconn* conn, const char* str, size_t length);
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
        int PQmblen(char* s, int encoding);
        int PQdsplen(char* s, int encoding);
        int PQenv2encoding();
        char* PQencryptPassword(char* passwd, char* user);
        size_t PQsetInstanceData(PGconn *conn, PGEventProc proc, void *data);
    }
}