/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2.dynloader;

/// Available only for dynamic libpq config
version(DerelictPQ_Dynamic)
immutable class DynamicLoader
{
    import derelict.pq.pq: DerelictPQ;
    import core.sync.mutex: Mutex;
    import core.atomic;
    debug import std.experimental.logger;

    private __gshared static Mutex mutex;
    private shared static ptrdiff_t instances;

    shared static this()
    {
        mutex = new Mutex();
    }

    /*
        It is possible to setup DerelictPQ.missingSymbolCallback
        before. So it is possible to use this library even with
        previous versions of libpq with some missing symbols.
    */
    this()
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        if(instances.atomicFetchAdd(1) == 0)
        {
            debug trace("DerelictPQ loading...");

            DerelictPQ.load();

            debug trace("...DerelictPQ loading finished");
        }
    }

    ~this()
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        if(instances.atomicFetchSub(1) == 1)
        {
            import std.stdio;
            writeln("Unload PQ");
            DerelictPQ.unload();
        }
    }

    import dpq2.connection: Connection;

    /// Accepts same parameters as Connection ctors in static configuration
    Connection createConnection(T...)(T args)
    {
        return new Connection(this, args);
    }
}
