/// Bindings for the PostgreSQL libpq library written and available for the D programming language

/// Authors: Jeff Davey

/// See_Also: Homepage of the original file: http://pgfoundry.org/projects/pgd

/**
 * Bugs: Invalid storage classes for unused functions.
 * 
 * Please check function arguments and return values before first usage and fix
 * them if they are wrong.
 */

module dpq2.libpq;
@safe

import std.c.stdio: FILE;

extern (C) nothrow
{
    alias uint Oid; /// OID

    enum valueFormat {
        TEXT,
        BINARY
    }

    enum ConnStatusType
    {
        /*
         * Although it is okay to add to this list, values which become unused
         * should never be removed, nor should ants be redefined - that would
         * break compatibility with existing code.
         */
        CONNECTION_OK,
        CONNECTION_BAD,
        /* Non-blocking mode only below here */

        /*
         * The existence of these should never be relied upon - they should only
         * be used for user feedback or similar purposes.
         */
        CONNECTION_STARTED,         /** Waiting for connection to be made.  */
        CONNECTION_MADE,            /** Connection OK; waiting to send.    */
        CONNECTION_AWAITING_RESPONSE,       /** Waiting for a response from the
                                             * postmaster.        */
        CONNECTION_AUTH_OK,         /** Received authentication; waiting for
                                     * backend startup. */
        CONNECTION_SETENV,          /** Negotiating environment. */
        CONNECTION_SSL_STARTUP,     /** Negotiating SSL. */
        CONNECTION_NEEDED           /** Internal state: connect() needed */
    };

    enum PostgresPollingStatusType
    {
        PGRES_POLLING_FAILED = 0,
        PGRES_POLLING_READING,      /** These two indicate that one may   */
        PGRES_POLLING_WRITING,      /** use select before polling again.   */
        PGRES_POLLING_OK,
        PGRES_POLLING_ACTIVE        /** unused; keep for awhile for backwards
                                     * compatibility */
    };

    enum ExecStatusType
    {
        PGRES_EMPTY_QUERY = 0,      /** empty query string was executed */
        PGRES_COMMAND_OK,           /** a query command that doesn't return
                                     * anything was executed properly by the
                                     * backend */
        PGRES_TUPLES_OK,            /** a query command that returns tuples was
                                     * executed properly by the backend, PGresult
                                     * contains the result tuples */
        PGRES_COPY_OUT,             /** Copy Out data transfer in progress */
        PGRES_COPY_IN,              /** Copy In data transfer in progress */
        PGRES_BAD_RESPONSE,         /** an unexpected response was recv'd from the
                                     * backend */
        PGRES_NONFATAL_ERROR,       /** notice or warning message */
        PGRES_FATAL_ERROR           /** query failed */
    };

    enum PGTransactionStatusType
    {
        PQTRANS_IDLE,               /** connection idle */
        PQTRANS_ACTIVE,             /** command in progress */
        PQTRANS_INTRANS,            /** idle, within transaction block */
        PQTRANS_INERROR,            /** idle, within failed transaction */
        PQTRANS_UNKNOWN             /** cannot determine status */
    };

    enum PGVerbosity
    {
        PQERRORS_TERSE,             /** single-line error messages */
        PQERRORS_DEFAULT,           /** recommended style */
        PQERRORS_VERBOSE            /** all the facts, ma'am */
    };

    /* PGconn encapsulates a connection to the backend.
     * The contents of this struct are not supposed to be known to applications.
     */
    struct PGconn {};

    /* PGresult encapsulates the result of a query (or more precisely, of a single
     * SQL command --- a query string given to PQsendQuery can contain multiple
     * commands and thus return multiple PGresult objects).
     * The contents of this struct are not supposed to be known to applications.
     */
    struct PGresult {};

    /* PGcancel encapsulates the information needed to cancel a running
     * query on an existing connection.
     * The contents of this struct are not supposed to be known to applications.
     */
    struct PGcancel {};

    /* PGnotify represents the occurrence of a NOTIFY message.
     * Ideally this would be an opaque typedef, but it's so simple that it's
     * unlikely to change.
     * NOTE: in Postgres 6.4 and later, the be_pid is the notifying backend's,
     * whereas in earlier versions it was always your own backend's PID.
     */
    struct PGnotify
    {
        char       *relname;        /** notification condition name */
        int         be_pid;         /** process ID of notifying server process */
        char       *extra;          /** notification parameter */
        /* Fields below here are private to libpq; apps should not use 'em */
        private PGnotify *next;     /* list link */
    };

    /* Function types for notice-handling callbacks */
    alias void function(void *arg, PGresult *res) PGnoticeReceiver;
    alias void function(void *arg, char *message) PGnoticeProcessor;

    /* Print options for PQprint() */
    alias char pqbool;

    struct PQprintOpt
    {
        pqbool      header;         /** print output field headings and row count */
        pqbool      alignment;      /** fill align the fields */
        pqbool      standard;       /** old brain dead format */
        pqbool      html3;          /** output html tables */
        pqbool      expanded;       /** expand tables */
        pqbool      pager;          /** use pager for output if needed */
        char       *fieldSep;       /** field separator */
        char       *tableOpt;       /** insert to HTML <table ...> */
        char       *caption;        /** HTML <caption> */
        char      **fieldName;      /** null terminated array of replacement field
                                     * names */
    };

    /* ----------------
     * Structure for the conninfo parameter definitions returned by PQconndefaults
     *
     * All fields except "val" point at static strings which must not be altered.
     * "val" is either NULL or a malloc'd current-value string.  PQconninfoFree()
     * will release both the val strings and the PQconninfoOption array itself.
     * ----------------
     */
    struct PQconninfoOption
    {
        char       *keyword;        /** The keyword of the option           */
        char       *envvar;         /** Fallback environment variable name  */
        char       *compiled;       /** Fallback compiled in default value  */
        char       *val;            /** Option's current value, or NULL      */
        char       *label;          /** Label for field in connect dialog   */
        char       *dispchar;       /** Character to display for this field in a
                                     * connect dialog. Values are: "" Display
                                     * entered value as is "*" Password field -
                                     * hide value "D"  Debug option - don't show
                                     * by default */
        int         dispsize;       /** Field size in characters for dialog */
    };

    /* ----------------
     * PQArgBlock -- structure for PQfn() arguments
     * ----------------
     */
    struct PQArgBlock
    {
        int         len;
        int         isint;
        union u
        {
            int        *ptr;        /** can't use void (dec compiler barfs)  */
            int         integer;
        };
    };

    /* ----------------
     * Exported functions of libpq
     * ----------------
     */

    /* ===  in fe-connect.c === */

    /* make a new client connection to the backend */
    /* Asynchronous (non-blocking) */

    PGconn* PQconnectStart(char *connInfo);
    PostgresPollingStatusType PQconnectPoll(PGconn *conn);

    /* Synchronous (blocking) */
    PGconn* PQconnectdb(immutable char* connInfo); 
    PGconn* PQsetdbLogin(char *pghost, char *pgport, char *pgoptions, char *pgtty, char *dbName, char *login, char *pwd);

    void PQfinish(PGconn *conn);
    PQconninfoOption* PQconndefaults();
    void PQconninfoFree(PQconninfoOption *connOptions);

    
    /*
     * close the current connection and restablish a new one with the same
     * parameters
     */
    /* Asynchronous (non-blocking) */
    int PQresetStart(PGconn *conn);
    PostgresPollingStatusType PQresetPoll(PGconn *conn);

    /* Synchronous (blocking) */
    void PQreset(PGconn *conn);

    /* request a cancel structure */
    PGcancel* PQgetCancel(PGconn *conn);

    /* free a cancel structure */
    void PQfreeCancel(PGcancel *cancel);

    /* issue a cancel request */
    int PQcancel(PGcancel *cnacel, char *errbuff, int errbufsize);

    /* backwards compatible version of PQcancel; not thread-safe */
    int PQrequestCancel(PGconn *conn);

    /* Accessor functions for PGconn objects */
    char* PQdb(PGconn *conn);
    char* PQuser(PGconn *conn);
    char* PQpass(PGconn *conn);
    char* PQhost(PGconn *conn);
    char* PQport(PGconn *conn);
    char* PQtty(PGconn *conn);
    char* PQoptions(PGconn *conn);
    ConnStatusType PQstatus(PGconn *conn);
    PGTransactionStatusType PQtransactionStatus(PGconn *conn);
    char* PQparameterStatus(PGconn *conn, char *paramName);
    int PQprotocolVersion(PGconn *conn);
    int PQserverVersion(PGconn *conn);
    char* PQerrorMessage(PGconn *conn);
    int PQsocket(PGconn *conn);
    int PQbackendPID(PGconn *conn);
    int PQclientEncoding(PGconn *conn);
    int PQsetClientEncoding(PGconn *conn, char *encoding);

    /* Get the OpenSSL structure associated with a connection. Returns NULL for
     * unencrypted connections or if any other TLS library is in use. */
    void *PQgetssl(PGconn *conn);

    /* Tell libpq whether it needs to initialize OpenSSL */
    void PQinitSSL(int do_init);

    /* Set verbosity for PQerrorMessage and PQresultErrorMessage */
    PGVerbosity PQsetErrorVerbosity(PGconn *conn, PGVerbosity verbosity);

    /* Enable/disable tracing */
    void PQtrace(PGconn *conn, FILE *debug_port);
    void PQuntrace(PGconn *conn);

    alias void function(void *arg, PGresult *res) PQnoticeReceiver;
    alias void function(void *arg, char *message) PQnoticeProcessor;

    /* Override default notice handling routines */
    PQnoticeReceiver PQsetNoticeReceiver(PGconn *conn, PQnoticeReceiver proc, void *arg);
    PQnoticeProcessor PQsetNoticeProcessor(PGconn *conn, PQnoticeProcessor proc, void *arg);

    /*
     *     Used to set callback that prevents concurrent access to
     *     non-thread safe functions that libpq needs.
     *     The default implementation uses a libpq internal mutex.
     *     Only required for multithreaded apps that use kerberos
     *     both within their app and for postgresql connections.
     */
    alias void function(int acquire) pgthreadlock_t;

    pgthreadlock_t PQregisterThreadLock(pgthreadlock_t newhandler);

    /* === in fe-exec.c === */

    /* Simple synchronous query */
    PGresult *PQexec(PGconn *conn, const char* query);
    PGresult *PQexecParams(PGconn *conn, const char* command, int nParams, Oid *paramTypes, const byte** paramValues, int *paramLengths, int *paramFormats, int resultFormat);
    PGresult *PQprepare(PGconn *conn,  char *stmtName,  char *query, int nParams,  Oid *paramTypes);
    PGresult *PQexecPrepared(PGconn *conn,  char *stmtName, int nParams,  char * * paramValues,  int *paramLengths,  int *paramFormats, int resultFormat);

    /* Interface for multiple-result or asynchronous queries */
    int PQsendQuery(PGconn *conn, char *query);
    int PQsendQueryParams(PGconn *conn, char *command, int nParams, Oid *paramTypes, char * * paramValues, int *paramLengths, int *paramFormats, int resultFormat);
    int PQsendPrepare(PGconn *conn, char *stmtName, char *query, int nParams, Oid *paramTypes);
    int PQsendQueryPrepared(PGconn *conn, char *stmtName, int nParams, char * * paramValues, int *paramLengths, int *paramFormats, int resultFormat);
    PGresult *PQgetResult(PGconn *conn);

    /* Routines for managing an asynchronous query */
    int PQisBusy(PGconn *conn);
    int PQconsumeInput(PGconn *conn);

    /* LISTEN/NOTIFY support */
    PGnotify *PQnotifies(PGconn *conn);

    /* Routines for copy in/out */
    int PQputCopyData(PGconn *conn, char *buffer, int nbytes);
    int PQputCopyEnd(PGconn *conn, char *errormsg);
    int PQgetCopyData(PGconn *conn, char **buffer, int async);

    /* Deprecated routines for copy in/out */
    int PQgetline(PGconn *conn, char *string, int length);
    int PQputline(PGconn *conn, char *string);
    int PQgetlineAsync(PGconn *conn, char *buffer, int bufsize);
    int PQputnbytes(PGconn *conn, char *buffer, int nbytes);
    int PQendcopy(PGconn *conn);

    /* Set blocking/nonblocking connection to the backend */
    int PQsetnonblocking(PGconn *conn, int arg);
    int PQisnonblocking(PGconn *conn);
    int PQisthreadsafe();

    /* Force the write buffer to be written (or at least try) */
    int PQflush(PGconn *conn);

    /*
     * "Fast path" interface --- not really recommended for application
     * use
     */
    PGresult *PQfn(PGconn *conn, int fnid, int *result_buf, int *result_len, int result_is_int, PQArgBlock *args, int nargs);

    /* Accessor functions for PGresult objects */
    ExecStatusType PQresultStatus(PGresult *res);
    char* PQresStatus(ExecStatusType status);
    char *PQresultErrorMessage( PGresult *res);
    char *PQresultErrorField( PGresult *res, int fieldcode);
    int PQntuples( PGresult *res);
    int PQnfields( PGresult *res);
    int PQbinaryTuples( PGresult *res);
    char *PQfname( PGresult *res, int field_num);
    int PQfnumber( PGresult *res,  immutable char *field_name);
    Oid PQftable( PGresult *res, int field_num);
    int PQftablecol( PGresult *res, int field_num);
    valueFormat PQfformat( PGresult *res, int field_num);
    Oid PQftype( PGresult *res, int field_num);
    int PQfsize( PGresult *res, int field_num);
    int PQfmod( PGresult *res, int field_num);
    char *PQcmdStatus(PGresult *res);
    char *PQoidStatus( PGresult *res);
    Oid PQoidValue( PGresult *res);
    char *PQcmdTuples(PGresult *res);
    immutable(byte)* PQgetvalue( PGresult *res, int tup_num, int field_num);
    int PQgetlength( PGresult *res, int tup_num, int field_num);
    int PQgetisnull( PGresult *res, int tup_num, int field_num);
    int PQnparams( PGresult *res);
    Oid PQparamtype( PGresult *res, int param_num);

    /* Describe prepared statements and portals */
    PGresult *PQdescribePrepared(PGconn *conn,  char *stmt);
    PGresult *PQdescribePortal(PGconn *conn,  char *portal);
    int PQsendDescribePrepared(PGconn *conn,  char *stmt);
    int PQsendDescribePortal(PGconn *conn,  char *portal);

    /* Delete a PGresult */
    void PQclear(PGresult *res);

    /* For freeing other alloc'd results, such as PGnotify structs */
    void PQfreemem(void *ptr);

    /*
     * Make an empty PGresult with given status (some apps find this
     * useful). If conn is not NULL and status indicates an error, the
     * conn's errorMessage is copied.
     */
    PGresult *PQmakeEmptyPGresult(PGconn *conn, ExecStatusType status);


    /* Quoting strings before inclusion in queries. */
    size_t PQescapeStringConn(PGconn *conn, char *to,  char *from, size_t length, int *error);
    ubyte *PQescapeByteaConn(PGconn *conn,  ubyte *from, size_t from_length, size_t *to_length);
    ubyte *PQunescapeBytea( ubyte *strtext, size_t *retbuflen);

    /* These forms are deprecated! */
    size_t PQescapeString(char *to,  char *from, size_t length);
    ubyte *PQescapeBytea( ubyte *from, size_t from_length, size_t *to_length);



    /* === in fe-print.c === */

    void PQprint(FILE *fout,     PGresult *res,  PQprintOpt *ps);

    /*
     * really old printing routines
     */
    void PQdisplayTuples( PGresult *res, FILE *fp, int fillAlign,  char *fieldSep,  int printHeader, int quiet);

    void PQprintTuples( PGresult *res, FILE *fout, int printAttName, int terseOutput, int width);


    /* === in fe-lobj.c === */

    /* Large-object access routines */
    int lo_open(PGconn *conn, Oid lobjId, int mode);
    int lo_close(PGconn *conn, int fd);
    int lo_read(PGconn *conn, int fd, char *buf, size_t len);
    int lo_write(PGconn *conn, int fd,  char *buf, size_t len);
    int lo_lseek(PGconn *conn, int fd, int offset, int whence);
    Oid lo_creat(PGconn *conn, int mode);
    Oid lo_create(PGconn *conn, Oid lobjId);
    int lo_tell(PGconn *conn, int fd);
    int lo_unlink(PGconn *conn, Oid lobjId);
    Oid lo_import(PGconn *conn,  char *filename);
    int lo_export(PGconn *conn, Oid lobjId,  char *filename);

    /* === in fe-misc.c === */

    /* Determine length of multibyte encoded char at *s */
    int PQmblen( char *s, int encoding);

    /* Determine display length of multibyte encoded char at *s */
    int PQdsplen( char *s, int encoding);

    /* Get encoding id from environment variable PGCLIENTENCODING */
    int PQenv2encoding();

    /* === in fe-auth.c === */

    char *PQencryptPassword( char *passwd,  char *user); 
}

