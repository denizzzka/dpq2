/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2.dynloader;

version(DerelictPQ_Dynamic):

import dpq2.connection: Connection;
import core.sync.mutex: Mutex;
import dpq2.exception: Dpq2Exception;

immutable class ConnectionFactory
{
    private __gshared Mutex mutex;
    private __gshared bool instanced;

    ReferenceCounter cnt;
    //TODO: add optional path to dynamic library?

    shared static this()
    {
        mutex = new Mutex();
    }

    this()
    {
        this("");
    }

    this(string path)
    {
        import std.exception: enforce;

        mutex.lock();
        scope(exit) mutex.unlock();

        enforce!Dpq2Exception(!instanced, "Already instanced");

        instanced = true;
        cnt = ReferenceCounter(path);
    }

    ~this()
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        assert(instanced);

        instanced = false;
        cnt.__custom_dtor();
    }

    /// Accepts same parameters as Connection ctors in static configuration
    Connection createConnection(T...)(T args)
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        assert(instanced);

        return new Connection(args);
    }
}

package struct ReferenceCounter
{
    import core.atomic;
    import derelict.pq.pq: DerelictPQ;
    debug import std.experimental.logger;

    private __gshared Mutex mutex;
    private __gshared ptrdiff_t instances;

    shared static this()
    {
        mutex = new Mutex();
    }

    this() @disable;

    this(string path)
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        if(instances.atomicFetchAdd(1) == 0)
        {
            debug trace("DerelictPQ loading...");
            DerelictPQ.load(path);
            debug trace("...DerelictPQ loading finished");
        }
    }

    // TODO: here is must be a destructor, but:
    // "This is bug or not? (immutable class containing struct with dtor)"
    // https://forum.dlang.org/post/spim8c$108b$1@digitalmars.com
    // https://issues.dlang.org/show_bug.cgi?id=13628
    void __custom_dtor() const
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        if(instances.atomicFetchSub(1) == 1)
        {
            import std.stdio;

            debug writeln("DerelictPQ unloading...");
            DerelictPQ.unload();
            debug writeln("...DerelictPQ unloading finished");
        }
    }
}

version (integration_tests)
version(DerelictPQ_Dynamic):

/// Used by integration tests facility
package immutable ConnectionFactory connFactory;

shared static this()
{
    import std.exception : assertThrown;

    // Some testing:
    auto f1 = new immutable ConnectionFactory();
    f1.destroy;

    auto f2 = new immutable ConnectionFactory();

    // Only one instance of ConnectionFactory is allowed
    assertThrown!Dpq2Exception(new immutable ConnectionFactory(`path/to/libpq.dll`));

    f2.destroy;

    assert(ReferenceCounter.instances == 0);

    // Integration tests connection factory initialization
    connFactory = new immutable ConnectionFactory;
}
