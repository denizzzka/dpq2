module dpq2.exception;

/// Base for all dpq2 exceptions classes
class Dpq2Exception : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}

import std.conv: to, ConvException;

/// Conversion exception types
enum ConvExceptionType
{
    NOT_ARRAY, /// Format of the value isn't array
    NOT_BINARY, /// Format of the column isn't binary
    NOT_TEXT, /// Format of the column isn't text string
    NOT_IMPLEMENTED, /// Support of this type isn't implemented (or format isn't matches to specified D type)
    SIZE_MISMATCH, /// Result value size is not matched to the received Postgres value
    CORRUPTED_JSONB, /// Corrupted JSONB value
}

class AnswerConvException : ConvException
{
    const ConvExceptionType type; /// Exception type

    this(ConvExceptionType t, string msg, string file, size_t line) pure @safe
    {
        type = t;
        super(msg, file, line);
    }
}
