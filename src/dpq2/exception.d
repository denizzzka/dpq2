///
module dpq2.exception;

/// Base for all dpq2 exceptions classes
class Dpq2Exception : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure @safe
    {
        super(msg, file, line);
    }
}
