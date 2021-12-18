/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2.dynloader;

version(DerelictPQ_Dynamic):

import dpq2.connection: Connection;

auto getConnectionFactory(T...)()
{
    immutable cnt = ReferenceCounter(true);

    /// Accepts same parameters as Connection ctors in static configuration
    Connection createConnection(T...)(T args)
    {
        return new Connection(args);
    }

    return &createConnection!T;
}

import core.sync.mutex: Mutex;

private __gshared Mutex mutex;
private __gshared ptrdiff_t instances;

shared static this()
{
    mutex = new Mutex();
}

package struct ReferenceCounter
{
    import core.atomic;
    import derelict.pq.pq: DerelictPQ;
    debug import std.experimental.logger;

    this() @disable;

    this(bool)
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

    // TODO: "This is bug or not? (immutable class containing struct with dtor)"
    // https://forum.dlang.org/post/spim8c$108b$1@digitalmars.com
    void __custom_dtor() const
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        import std.stdio;
        writeln("Instances ", instances);

        if(instances.atomicFetchSub(1) == 1)
        {
            import std.stdio;

            debug writeln("DerelictPQ unloading...");
            DerelictPQ.unload();
            debug writeln("...DerelictPQ unloading finished");
        }
    }
}
