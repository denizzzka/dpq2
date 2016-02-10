module dpq2;

shared static this()
{
    DerelictPQ.load();
}

shared static ~this()
{
    debug
    {
        import std.stdio: write, writeln;
        write("DerelictPQ unloading... ");
    }
    
    import core.memory: GC;
    GC.collect();
    DerelictPQ.unload();
    
    debug
    {
        writeln("finished.");
    }
}

public
{
    import derelict.pq.pq;
    
    import dpq2.answer;
    import dpq2.connection;
    import dpq2.query;
}
