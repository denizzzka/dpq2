module dpq2.casn;
@trusted:
nothrow:

import core.atomic: cas;

V* setLSB(V)( V* ptr )
{
    return cast(T*) (cast(size_t) ptr | 1);
}

V* clearLSB(V)( V* ptr )
{
    return cast(V*) (cast(size_t) ptr | 0);
}

bool hasLSB(V)( V v )
{
    V mask = 0 | 1;
    return (v & mask) == 1;
}

alias shared size_t T;

shared struct RDCSSDESCRI
{
    T* addr1;
    T oldval1;
    T* addr2;
    T oldval2;
    T newval2;
}

T CAS1(T,V1,V2)( T* ptr, V1 oldval, V2 newval )
{
    auto ret = *ptr;
    cas( ptr, oldval, newval );
    return ret;
}

void Complete(V)( V v ) // changes only content under v ptr
{
    auto d = cast( RDCSSDESCRI* ) v;
    
    T val = *d.addr1;
    if (val == d.oldval1)
        cas(d.addr2, d, d.newval2); // C2
    else
        cas(d.addr2, d, d.oldval2); // C3
}

bool IsDescriptor(V)( V val )
{
    auto v = cast(T) val;
    return hasLSB( v );
}

/// Restricted Double-Compare Single-Swap
T RDCSS( RDCSSDESCRI* d )
{
    T r = *d.addr2;
    
    while( !cas( d.addr2, d.oldval2, cast(T) d ) ){} // C1
    Complete ( r ); // H1
    
    if( r == d.oldval2 ) Complete( d );
    
    return r;
}

T RDCSSRead( T* addr )
{
    T r;
    do {
        r = *addr; // R1
        if( IsDescriptor(r) ) Complete( r ); // H2
    } while( IsDescriptor( r ) ); // B2
    return r;
}

enum CASNDStatus { UNDECIDED, FAILED, SUCCEEDED };

struct CASNDescriptor
{
    CASNDStatus status;
    
    T* ref1;
    T o1;
    T* ref2;
    T o2;
    T n2;
    
    RDCSSDESCRI RDCSSDescriptor;
}
