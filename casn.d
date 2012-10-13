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
/*
T CAS1(T,V1,V2)( T* ptr, V1 oldval, V2 newval )
{
    auto ret = *ptr;
    cas( ptr, oldval, newval );
    return ret;
}
*/
void Complete(V)( V v ) // changes only content under v ptr
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

/// Restricted Double-Compare Single-Swap
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

enum CASNDStatus { UNDECIDED, FAILED, SUCCEEDED };

struct CASNDescriptor
{
    CASNDStatus status;    
}

bool CASN( CASNDescriptor* cd )
{
    if( cd.status == UNDECIDED ) // R4
    {
        status = SUCCEEDED;
        for( int t = 0; i < cd.n && (status == SUCCEEDED); i++ ) // L1
        {
            entry = cd.entry[i];
            val = RDCSS( new RDCSSDESCRI (&(cd.status), UNDECIDED, entry.addr, entry.old, cd )); // X1
            if( IsCASNDescriptor( val ) )
            {
                if( val != cd )
                {
                    CASN( val; // H3
                    goto retry_entry;
                }
            } else if( val != entry.old ) status = FAILED;
        }
        cas( &(cd.status), UNDECIDED, status ); // C4
    }
    
    succeeded = ( cd.status == SUCCEEDED );
    for( int i = 0; i < cd.n; i++ )
        cas( cd.entry[i].addr, cd, succeeded ? (cd.entry[i].new) : (cd.entry[i].old); // C5
    return succeeded;
}    
/*
T CASNRead( T* addr )
{
    do {
        r = RDCSSRead( addr ); // R5
        if( IsCASNDescriptor( r ) ) CASN( r ); // H4
    } while( IsCASNDescriptor( r ) ); // B3
    return r;
}
*/
