module dpq2.conv.inet;

import dpq2.conv.to_d_types;
import dpq2.oids: OidType;
import dpq2.value;

import std.bitmanip: bigEndianToNative, nativeToBigEndian;
import std.conv: to;
import std.socket;

@safe:

enum PgFamily : ubyte {
    PGSQL_AF_INET = AddressFamily.INET,
    PGSQL_AF_INET6,
}

alias InetAddress = TInetAddress!false;
alias CidrAddress = TInetAddress!true;

package struct TInetAddress (bool isCIDR)
{
    PgFamily family;
    ubyte netmask;
    AddrValue addr;
    alias addr this;

    ///
    this(in InternetAddress ia, ubyte mask = 32)
    {
        addr4 = ia.addr;
        family = PgFamily.PGSQL_AF_INET;
        netmask = mask;
    }

    ///
    this(in Internet6Address ia, ubyte mask = 128)
    {
        addr6 = ia.addr;
        family = PgFamily.PGSQL_AF_INET6;
        netmask = mask;
    }

    ///
    Address createStdAddr(ushort port = InternetAddress.PORT_ANY) const
    {
        switch(family)
        {
            case PgFamily.PGSQL_AF_INET:
                return new InternetAddress(addr4, port);

            case PgFamily.PGSQL_AF_INET6:
                return new Internet6Address(addr6, port);

            default:
                assert(0, "Unsupported address family "~family.to!string);
        }
    }

    ///
    auto toString() const
    {
        import std.format: format;

        switch (family)
        {
            case PgFamily.PGSQL_AF_INET:
            case PgFamily.PGSQL_AF_INET6:
                return format("%s/%d", createStdAddr.toAddrString, this.netmask);

            default:
                return format("Unsupported address family %s", family.to!string); //TODO: deduplicate this code
        }
    }
}

unittest
{
    auto std_addr = new InternetAddress("127.0.0.1", 123);
    auto pg_addr = InetAddress(std_addr);

    assert(pg_addr.createStdAddr.toAddrString == "127.0.0.1");

    auto v = pg_addr.toValue;
    assert(v.binaryValueAs!InetAddress.toString == "127.0.0.1/32");
    assert(v.binaryValueAs!InetAddress.createStdAddr.toAddrString == "127.0.0.1");
    assert(v.binaryValueAs!InetAddress == pg_addr);
}

unittest
{
    auto std_addr = new Internet6Address("::1", 123);
    auto pg_addr = InetAddress(std_addr);

    assert(pg_addr.createStdAddr.toAddrString == "::1");

    auto v = pg_addr.toValue;
    assert(v.binaryValueAs!InetAddress.toString == "::1/128");
    assert(v.binaryValueAs!InetAddress.createStdAddr.toAddrString == "::1");
    assert(v.binaryValueAs!InetAddress == pg_addr);
}

///
InetAddress vibe2pg(VibeNetworkAddress)(VibeNetworkAddress a)
{
    InetAddress r;

    switch(a.family)
    {
        case AddressFamily.INET:
            r.family = PgFamily.PGSQL_AF_INET;
            r.netmask = 32;
            r.addr4 = a.sockAddrInet4.sin_addr.s_addr.representAsBytes.bigEndianToNative!uint;
            break;

        case AddressFamily.INET6:
            r.family = PgFamily.PGSQL_AF_INET6;
            r.netmask = 128;
            r.addr6 = AddrValue(a.sockAddrInet6.sin6_addr.s6_addr).swapEndiannesForBigEndianSystems;
            break;

        default:
            throw new ValueConvException(
                ConvExceptionType.NOT_IMPLEMENTED,
                "Unsupported address family: "~a.family.to!string
            );
    }

    return r;
}

private ref ubyte[T.sizeof] representAsBytes(T)(const ref return T s) @trusted
{
    return *cast(ubyte[T.sizeof]*) &s;
}

private union Hdr
{
    ubyte[4] bytes;

    struct
    {
        PgFamily family;
        ubyte netmask;
        ubyte always_zero;
        ubyte addr_len;
    }
}

/// Constructs Value from InetAddress or from CidrAddress
Value toValue(T)(T v)
if(is(T == InetAddress) || is(T == CidrAddress))
{
    Hdr hdr;
    hdr.family = v.family;

    ubyte[] addr_net_byte_order;

    switch(v.family)
    {
        case PgFamily.PGSQL_AF_INET:
            addr_net_byte_order ~= v.addr4.nativeToBigEndian;
            break;

        case PgFamily.PGSQL_AF_INET6:
            addr_net_byte_order ~= v.addr.swapEndiannesForBigEndianSystems;
            break;

        default:
            throw new ValueConvException(
                ConvExceptionType.NOT_IMPLEMENTED,
                "Unsupported address family: "~v.family.to!string
            );
    }

    hdr.addr_len = addr_net_byte_order.length.to!ubyte;
    hdr.netmask = v.netmask;

    immutable r = (hdr.bytes ~ addr_net_byte_order).idup;
    return Value(r, OidType.HostAddress);
}

package:

/// Convert Value to network address type
T binaryValueAs(T)(in Value v)
if(is(T == InetAddress) || is(T == CidrAddress))
{
    enum oidType = is(T == InetAddress) ? OidType.HostAddress : OidType.NetworkAddress;
    enum typeName = is(T == InetAddress) ? "inet" : "cidr";

    if(v.oidType != oidType)
        throwTypeComplaint(v.oidType, typeName);

    Hdr hdr;
    enum headerLen = hdr.sizeof;
    enum ipv4_addr_len = 4;

    if(v.data.length < hdr.sizeof + ipv4_addr_len)
        throw new ValueConvException(ConvExceptionType.SIZE_MISMATCH, "unexpected data ending");

    hdr.bytes = v.data[0 .. hdr.bytes.length];

    ubyte lenMustBe;
    switch(hdr.family)
    {
        case PgFamily.PGSQL_AF_INET: lenMustBe = ipv4_addr_len; break;
        case PgFamily.PGSQL_AF_INET6: lenMustBe = 16; break;
        default:
            throw new ValueConvException(
                ConvExceptionType.NOT_IMPLEMENTED,
                "Unsupported address family: "~hdr.family.to!string
            );
    }

    if(hdr.addr_len != lenMustBe && hdr.always_zero == 0)
        throw new ValueConvException(
            ConvExceptionType.SIZE_MISMATCH,
            "Wrong address length, must be "~lenMustBe.to!string
        );

    if(headerLen + hdr.addr_len != v.data.length)
        throw new ValueConvException(
            ConvExceptionType.SIZE_MISMATCH,
            "Address length not matches to Value data length"
        );

    import std.bitmanip: bigEndianToNative;

    T r;
    r.family = hdr.family;
    r.netmask = hdr.netmask;

    switch(hdr.family)
    {
        case PgFamily.PGSQL_AF_INET:
            const ubyte[4] b = v.data[headerLen..$];
            r.addr4 = b.bigEndianToNative!uint;
            break;

        case PgFamily.PGSQL_AF_INET6:
            AddrValue av;
            av.addr6 = v.data[headerLen..$];
            r.addr6 = av.swapEndiannesForBigEndianSystems;
            break;

        default: assert(0);
    }

    return r;
}

private:

private union AddrValue
{
    ubyte[16] addr6; // IPv6 address in native byte order
    short[8] addr6_parts; // for endiannes swap purpose

    struct
    {
        ubyte[12] __unused;
        uint addr4; // IPv4 address in native byte order
    }
}

import std.system: Endian, endian;

static if(endian == Endian.littleEndian)
auto swapEndiannesForBigEndianSystems(in AddrValue s)
{
    // do nothing for little endian
    return s.addr6;
}
else
{

ubyte[16] swapEndiannesForBigEndianSystems(in AddrValue s)
{
    import std.bitmanip: swapEndian;

    AddrValue r;
    enum len = AddrValue.addr6_parts.length;

    foreach(ubyte i; 0 .. len)
        r.addr6_parts[i] = s.addr6_parts[i].swapEndian;

    return r.addr6;
}

}
