module dpq2.all;

version(BINDINGS_DYNAMIC)
{
    shared static this()
    {
        DerelictPQ.load();
    }

    shared static ~this()
    {
        debug
        {
            import std.stdio;
            write("DerelictPQ is unloading... ");
        }
        
        import core.memory;
        GC.collect();
        DerelictPQ.unload();
        
        debug
        {
            writeln("finished.");
        }
    }
}

public
{
    import derelict.pq.pq;
    
    import dpq2.answer;
    import dpq2.connection;
    import dpq2.query;
}
