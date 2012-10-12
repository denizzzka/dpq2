/// Thread safe non blocking singly linked list
module dpq2.slist;
@trusted:

import core.atomic: cas;

shared struct SList
{
    shared struct Container
    {
        Container* next;
        int value;
        this( int value ) shared
        {
            this.value = value;
        }
    }
    
    private Container* root;
    
    void pushBack( int newValue ) shared
    {
        auto n = new Container( newValue );
        
        do {
            n.next = root;
        } while( !cas( &root, n.next, n ) );
    }
}

unittest
{
    shared SList l;
    l.pushBack( 1 );
}
