module dpq2.conv.jsonb;

@safe:

import vibe.data.json;
import dpq2.value: Value;
import dpq2.oids: OidType;
import dpq2.exception;

package:

import std.string;
import std.conv: to;

Json jsonbValueToJson(in Value v) @trusted
{
    assert(v.oidType == OidType.Jsonb);

    if(v.data[0] != 1)
        throw new AnswerConvException(
            ConvExceptionType.CORRUPTED_JSONB,
            "Unknown jsonb format byte: "~v._data[0].to!string,
            __FILE__, __LINE__
            );

    string s = (cast(const(char[])) v._data[1 .. $]).to!string;

    return parseJsonString(s); //TODO: make this @safe
}
