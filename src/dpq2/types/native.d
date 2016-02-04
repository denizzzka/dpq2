module dpq2.types.native;

import dpq2.answer;
import dpq2.oids;

import std.traits;
import std.datetime;
import std.uuid;

// Supported PostgreSQL binary types
alias PGsmallint =      short; /// smallint
alias PGinteger =       int; /// integer
alias PGbigint =        long; /// bigint
alias PGreal =          float; /// real
alias PGdouble_precision = double; /// double precision
alias PGtext =          string; /// text
alias PGbytea =         const ubyte[]; /// bytea
alias PGuuid =          UUID; /// UUID

private void throwTypeComplaint(OidType receivedType, string expectedType, string file, size_t line)
{
    throw new AnswerException(
            ExceptionType.NOT_NATIVE,
            "Format of the column ("~to!string(receivedType)~") doesn't match to D native "~expectedType,
            file, line
        );
}

private alias VF = ValueFormat;
private alias AE = AnswerException;
private alias ET = ExceptionType;

/// Returns value as bytes from binary formatted field
@property T as(T)(const Value v)
if( is( T == const(ubyte[]) ) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    if(!(v.oidType == OidType.ByteArray))
        throwTypeComplaint(v.oidType, "byte array or string", __FILE__, __LINE__);

    return v.value;
}

/// Returns cell value as native string type
@property T as(T)(const Value v)
if(is(T == string))
{
    if(v.format == VF.BINARY && !(v.oidType == OidType.Text))
        throwTypeComplaint(v.oidType, "string", __FILE__, __LINE__);

    return to!string( cast(const(char[])) v.value );
}

/// Returns cell value as native integer or decimal values
///
/// Postgres type "numeric" is oversized and not supported by now
@property T as(T)(const Value v)
if( isNumeric!(T) )
{
    if(!(v.format == VF.BINARY))
        throw new AE(ET.NOT_BINARY,
            msg_NOT_BINARY, __FILE__, __LINE__);

    static if(isIntegral!(T))
        if(!isNativeInteger(v.oidType))
            throwTypeComplaint(v.oidType, "integral types", __FILE__, __LINE__);

    static if(isFloatingPoint!(T))
        if(!isNativeFloat(v.oidType))
            throwTypeComplaint(v.oidType, "floating point types", __FILE__, __LINE__);

    if(!(v.value.length == T.sizeof))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to type size", __FILE__, __LINE__);

    ubyte[T.sizeof] s = v.value[0..T.sizeof];
    return bigEndianToNative!(T)(s);
}

/// Returns cell value as native date and time
@property T as(T)(const Value v)
if( is( T == SysTime ) )
{
    pragma(msg, "Date and time type support isn't tested very well and not recommended for use");

    ulong pre_time = v.as!(ulong)();
    // UTC because server always sends binary timestamps in UTC, not in TZ
    return SysTime( pre_time * 10, UTC() );
}

/// Returns UUID as native UUID value
@property T as(T)(const Value v)
if( is( T == UUID ) )
{
    if(!(v.oidType == OidType.UUID))
        throwTypeComplaint(v.oidType, "UUID", __FILE__, __LINE__);

    if(!(v.value.length == 16))
        throw new AE(ET.SIZE_MISMATCH,
            "Value length isn't equal to UUID size", __FILE__, __LINE__);

    UUID r;
    r.data = v.value;
    return r;
}
