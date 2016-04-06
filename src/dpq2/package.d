module dpq2;

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

/// Base for all dpq2 exceptions classes
class Dpq2Exception : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}

public
{
    import derelict.pq.pq;
    
    import dpq2.connection;
    import dpq2.query;
    import dpq2.result;
    import dpq2.oids;
}
