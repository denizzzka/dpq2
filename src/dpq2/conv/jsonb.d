///
module dpq2.conv.jsonb;

@safe:

import vibe.data.json;
import dpq2.value;
import dpq2.oids: OidType;

package:

import std.string;
import std.conv: to;

///
Json jsonbValueToJson(in Value v) @trusted
{
    assert(v.oidType == OidType.Jsonb);

    if(v.data[0] != 1)
        throw new ValueConvException(
            ConvExceptionType.CORRUPTED_JSONB,
            "Unknown jsonb format byte: "~v._data[0].to!string,
            __FILE__, __LINE__
            );

    string s = (cast(const(char[])) v._data[1 .. $]).to!string;

    return parseJsonString(s); //TODO: make this @safe
}
