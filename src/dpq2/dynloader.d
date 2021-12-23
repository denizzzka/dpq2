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
    private ReferenceCounter cnt;

    shared static this()
    {
        mutex = new Mutex();
    }

    this()
    {
        this("");
    }

    // If ctor throws dtor will be called. This is behaviour of current D design.
    // https://issues.dlang.org/show_bug.cgi?id=704
    private bool isSucessfulConstructed;

    this(string path)
    {
        import std.exception: enforce;

        mutex.lock();
        scope(success) instanced = true;
        scope(exit) mutex.unlock();

        enforce!Dpq2Exception(!instanced, "Already instanced");

        cnt = ReferenceCounter(path);
        assert(ReferenceCounter.instances == 1);

        isSucessfulConstructed = true;
    }

    ~this()
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        if(isSucessfulConstructed)
        {
            assert(instanced);

            cnt.__custom_dtor();
        }

        instanced = false;
    }

    /// This method is need to forbid attempts to create connection without properly loaded libpq
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
    import std.stdio: writeln;

    debug(dpq2_verbose) invariant()
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        import std.stdio;
        debug writeln("Instances ", instances);
    }

    private __gshared Mutex mutex;
    private __gshared ptrdiff_t instances;

    shared static this()
    {
        mutex = new Mutex();
    }

    this() @disable;
    this(this) @disable;

    /// Used only by connection factory
    this(string path)
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        assert(instances == 0);

        debug trace("DerelictPQ loading...");
        DerelictPQ.load(path);
        debug trace("...DerelictPQ loading finished");

        instances++;
    }

    /// Used by all other objects
    this(bool)
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        assert(instances > 0);

        instances++;
    }

    // TODO: here is must be a destructor, but:
    // "This is bug or not? (immutable class containing struct with dtor)"
    // https://forum.dlang.org/post/spim8c$108b$1@digitalmars.com
    // https://issues.dlang.org/show_bug.cgi?id=13628
    void __custom_dtor() const
    {
        mutex.lock();
        scope(exit) mutex.unlock();

        assert(instances > 0);

        instances--;

        if(instances == 0)
        {
            //TODO: replace writeln by trace?
            debug trace("DerelictPQ unloading...");
            DerelictPQ.unload();
            debug trace("...DerelictPQ unloading finished");
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
    {
        auto f = new immutable ConnectionFactory();
        assert(ConnectionFactory.instanced);
        assert(ReferenceCounter.instances == 1);
        f.destroy;
    }

    assert(ConnectionFactory.instanced == false);
    assert(ReferenceCounter.instances == 0);

    {
        auto f = new immutable ConnectionFactory();

        // Only one instance of ConnectionFactory is allowed
        assertThrown!Dpq2Exception(new immutable ConnectionFactory());

        assert(ConnectionFactory.instanced);
        assert(ReferenceCounter.instances == 1);

        f.destroy;
    }

    assert(!ConnectionFactory.instanced);
    assert(ReferenceCounter.instances == 0);

    {
        import derelict.util.exception: SharedLibLoadException;

        assertThrown!SharedLibLoadException(
            new immutable ConnectionFactory(`wrong/path/to/libpq.dll`)
        );

        assert(!ConnectionFactory.instanced);
        assert(ReferenceCounter.instances == 0);
    }

    // Integration tests connection factory initialization
    connFactory = new immutable ConnectionFactory;

    assert(ConnectionFactory.instanced);
    assert(ReferenceCounter.instances == 1);
}
