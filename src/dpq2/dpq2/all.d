module dpq2.all;

version(BINDINGS_DYNAMIC)
{
    public 
    {
        import derelict.pq.pq;
        import dpq2.answer;
        import dpq2.connection;
        import dpq2.query;
    }

    shared static this()
    {
        DerelictPQ.load();
    }

    shared static ~this()
    {
        import std.stdio;
        write("DerelictPQ is unloading... ");
        import core.memory;
        GC.collect();
        DerelictPQ.unload();
        writeln("finished.");
    }
}
version(BINDINGS_STATIC)
{
    public 
    {
        import dpq2.libpq;
        import dpq2.answer;
        import dpq2.connection;
        import dpq2.query;
    }
}
