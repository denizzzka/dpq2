module dpq2;

shared static this()
{
    DerelictPQ.load();
}

shared static ~this()
{
    import core.memory: GC;
    GC.collect();
    DerelictPQ.unload();
}

/// Base for all dpq2 exceptions classes
class Dpq2Exception : Exception
{
    this(string msg, string file, size_t line) pure
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
