/// Thread safe non blocking singly linked FIFO list
module dpq2.slist;
@trusted:

import core.atomic: cas;

shared class SList
{
    shared struct Container
    {
        Container* next;
        int value;
    }
    
    private Container* head;
    private Container* tail;
    private size_t icount;
    private size_t ocount;
    
    shared this()
    {
        auto n = new shared(Container);
        head = n;
        tail = n;
    }
    
    void pushBack( int newValue ) shared
    {
        auto n = new shared(Container);
        n.value = newValue;
        n.next = tail;
        
        do {
            auto _icount = icount;
            auto _tail = tail;
            
            if( cas( &tail.next, tail, n ) )
                break;
            //else
                //cas( &tail, _tail, _icount, _tail.next, _icount + 1 );
        } while( false ); // FIXME: to true
    }
}

unittest
{
    auto l = new shared(SList);
    l.pushBack( 1 );
}
