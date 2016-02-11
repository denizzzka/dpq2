module dpq2;

debug import std.stdio: write, writeln;

shared static this()
{
    debug
    {
        write("DerelictPQ loading... ");
    }

    DerelictPQ.load();

    debug
    {
        writeln("DerelictPQ loading finished");
    }
}

shared static ~this()
{
    debug
    {
        write("DerelictPQ unloading... ");
    }
    
    import core.memory: GC;
    GC.collect();
    DerelictPQ.unload();
    
    debug
    {
        writeln("DerelictPQ unloading finished");
    }
}

public
{
    import derelict.pq.pq;
    
    import dpq2.answer;
    import dpq2.connection;
    import dpq2.query;
}
