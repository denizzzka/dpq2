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
    auto val = *d.addr1;
    if (val == d.oldval1)
        CAS1(d.addr2, d, d.newval2);
    else
        CAS1(d.addr2, d, d.oldval2);  
}

bool IsDescriptor(T)( T val )
{
    return hasLSB( val );
}


T RDCSS( RDCSSDESCRI* d ) {
    T res;
    do {
        res = CAS1(d.addr2, d.oldval2, cast(T) d);  // STEP1
    //if (IsDescriptor(res)) Complete(res); // STEP2
  } while (IsDescriptor(res));             // STEP3
  //if (res == d.oldval2) Complete(d);     // STEP4
  return res;
}

/*
 * Restricted Double-Compare Single-Swap

Semantic:

int RDCSS(int *addr1, int oldval1, int *addr2, int oldval2, int newval2) {
  int res = *addr;
  if (res == oldval2 && *addr1 == oldval1) *addr2 = newval2;
  return res;
}
*/
/*
RDCSSDESCRI* RDCSS( RDCSSDESCRI* d ) {
  RDCSSDESCRI* res;
  do {
    res = cast(RDCSSDESCRI*) CAS1( d.addr2, d.oldval2, *cast(T*) d );  // STEP1
    if (IsDescriptor(cast(T)res)) Complete(res); // STEP2
  } while (IsDescriptor(cast(T)res));             // STEP3
  if (res == cast(RDCSSDESCRI*) d.oldval2) Complete(d);     // STEP4
  return res;
}
*/
