module dpq2;

import derelict.pq.pq;
debug import std.experimental.logger;

static __gshared bool __initialized;

static this()
{
    import std.concurrency : initOnce;
    initOnce!__initialized({
        debug
        {
            trace("DerelictPQ loading...");
        }

        DerelictPQ.load();

        debug
        {
            trace("...DerelictPQ loading finished");
        }
        return true;
    }());
}

public
{
    import dpq2.connection;
    import dpq2.query;
    import dpq2.result;
    import dpq2.oids;
}
