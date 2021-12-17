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

private __gshared static Mutex mutex;
private shared ptrdiff_t instances;

package struct ReferenceCounter
{
    import core.atomic;
    import derelict.pq.pq: DerelictPQ;
    debug import std.experimental.logger;

    this() @disable;

    this(bool)
    {
        if(instances.atomicFetchAdd(1) == 0)
        {
            debug trace("DerelictPQ loading...");
            DerelictPQ.load();
            debug trace("...DerelictPQ loading finished");
        }
    }

    //~ ~this()
    //~ {
        //~ mutex.lock();
        //~ scope(exit) mutex.unlock();

        //~ if(instances.atomicFetchSub(1) == 1)
        //~ {
            //~ import std.stdio;

            //~ debug writeln("DerelictPQ unloading...");
            //~ DerelictPQ.unload();
            //~ debug writeln("...DerelictPQ unloading finished");
        //~ }
    //~ }
}
