module dpq2.casn;
@trusted:

import core.atomic: cas;

struct _RDCSSDESCRI
{
    T *addr1;
    T oldval1; // added ptr
    T *addr2;
    T oldval2; // added ptr
    T newval2; // added ptr
}

alias int N;

union data
{
    N val;
    _RDCSSDESCRI dsc;
}

struct RDCSSDESCRI
{
    data d;
    bool isDescriptor;
}

alias shared RDCSSDESCRI T;

bool isDescriptor( T d ){ return d.isDescriptor; }

T CAS1( T* ptr, T oldval, T newval )
{
    auto ret = *ptr;
    cas( ptr, oldval, newval );
    return ret;
}

void Complete( RDCSSDESCRI* d )
{
    T val = d.d.dsc.addr1;
    if (val == d.dsc.oldval1)
        CAS1(d.addr2, d, d.newval2);
    else
        CAS1(d.addr2, d, d.oldval2);  
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
int RDCSS( RDCSSDESCRI *d ) {
    int* d_int = cast(int*) d;
    bool res;
    do {
        res = cas(d.addr2, d.oldval2, d_int);
        if( res ) Complete(d);
    } while (!res);
    if (res == d.oldval2) Complete(d);
    return r;
}
*/
