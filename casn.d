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

void Complete(V)( V v )
{
    auto d = cast( RDCSSDESCRI* ) v;
    
    T val = *d.addr1;
    if (val == d.oldval1)
        cas(d.addr2, d, d.newval2); // C2, make descriptor inactive
    else
        cas(d.addr2, d, d.oldval2); // C3, make descriptor inactive
}

bool IsDescriptor(V)( V val )
{
    auto v = cast(T) val;
    return hasLSB( v );
}

// Restricted Double-Compare Single-Swap
T RDCSS( RDCSSDESCRI* d )
{
    T r = *d.addr2;
    
    while( !cas( d.addr2, d.oldval2, cast(T) d ) ){} // C1 + B1
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
    } while( IsDescriptor(r) ); // B2
    return r;
}

enum CASNDStatus : T { UNDECIDED, FAILED, SUCCEEDED };

struct ent
{
    T* addr;
    T _new;
    T old;
}

shared struct CASNDescriptor
{
    CASNDStatus status;
    int n;
    ent[] entry;
}

bool IsCASNDescriptor(V)( V val )
{
    auto v = cast(T) val;
    return hasLSB( v );
}

bool CASN( CASNDescriptor* cd )
{
    if( cd.status == CASNDStatus.UNDECIDED ) // R4
    {
        // phase 1:
        auto status = CASNDStatus.SUCCEEDED;
        for( int i = 0; i < cd.n && (status == CASNDStatus.SUCCEEDED); i++ ) // L1
        {
            retry_entry:
            auto entry = cd.entry[i];
            
            auto d = new RDCSSDESCRI;
            d.addr1 = cast(T*) &(cd.status);
            T oldval1 = CASNDStatus.UNDECIDED;
            T* addr2 = entry.addr;
            T oldval2 = entry.old;
            T newval2 = cast(T) cd;
            
            auto val = RDCSS( d ); // X1
            if( IsCASNDescriptor( val ) )
            {
                if( val != cast(T) cd )
                {
                    CASN( cast(CASNDescriptor*) val ); // H3
                    goto retry_entry;
                }
            } else if( val != entry.old ) status = CASNDStatus.FAILED;
        }
        cas( cast(T*) &(cd.status), cast(T) CASNDStatus.UNDECIDED, cast(T) status ); // C4
    }
    
    // phase 2:
    bool succeeded = ( cd.status == CASNDStatus.SUCCEEDED );
    for( int i = 0; i < cd.n; i++ )
        cas( cd.entry[i].addr, cd,
            succeeded ? (cd.entry[i]._new) : (cd.entry[i].old) ); // C5
    return succeeded;
}    

T CASNRead( T* addr )
{
    T r;
    do {
        r = RDCSSRead( addr ); // R5
        if( IsCASNDescriptor( r ) ) CASN( cast(CASNDescriptor*) r ); // H4
    } while( IsCASNDescriptor( r ) ); // B3
    return r;
}
