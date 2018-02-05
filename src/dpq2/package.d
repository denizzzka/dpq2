module dpq2;

import derelict.pq.pq;
debug import std.experimental.logger;

shared static this()
{
    debug
    {
        trace("DerelictPQ loading...");
    }

    DerelictPQ.load();

    debug
    {
        trace("...DerelictPQ loading finished");
    }
}

public
{
    import dpq2.connection;
    import dpq2.query;
    import dpq2.result;
    import dpq2.oids;
}
