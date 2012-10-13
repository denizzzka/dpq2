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

T CAS1(T,V1,V2)( T* ptr, V1 oldval, V2 newval ) nothrow
{
    auto ret = *ptr;
    cas( ptr, oldval, newval );
    return ret;
}


void Complete( RDCSSDESCRI* d )
{
    T val = *d.addr1;
    if (val == d.oldval1)
        CAS1(d.addr2, d, d.newval2);
    else
        CAS1(d.addr2, d, d.oldval2);  
}

void Complete( T d )
{
    Complete( cast( RDCSSDESCRI* ) d );
}

bool IsDescriptor(V)( V val )
{
    auto v = cast(T) val;
    return hasLSB( v );
}


/// Restricted Double-Compare Single-Swap
T RDCSS( RDCSSDESCRI* d ) {
    T res;
    do {
        res = CAS1(d.addr2, d.oldval2, cast(T) d);
        if (IsDescriptor(res)) Complete(res);
    } while (IsDescriptor(res));
    if (res == d.oldval2) Complete(d);
    return res;
}
