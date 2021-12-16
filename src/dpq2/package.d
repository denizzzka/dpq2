/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2;

public import dpq2.connection;
public import dpq2.query;
public import dpq2.result;
public import dpq2.oids;

//FIXME: delete this
version(DerelictPQ_Static){}
else
{
DynamicLoader dl;

static this()
{
    dl = new DynamicLoader;
}

static ~this()
{
    dl.destroy;
}

}

version(DerelictPQ_Static){}
else
class DynamicLoader
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
            debug trace("DerelictPQ unloading...");

            DerelictPQ.unload();

            debug trace("...DerelictPQ unloading finished");
        }
    }
}
