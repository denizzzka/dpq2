module dpq2.exception;

/// Base for all dpq2 exceptions classes
class Dpq2Exception : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}
