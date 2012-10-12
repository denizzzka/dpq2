/// Thread safe non blocking singly linked list
module dpq2.slist;
@trusted:

import core.atomic;

shared struct Container
{
    Container* next;
    int value;
    this( int value ) shared
    {
        this.value = value;
    }
}

shared struct SList
{
    private Container* root;
    
    void pushBack( int newValue )
    {
        shared Container* n = new Container( newValue );
        
        do {
            n.next = root;
        } while( !cas( &root, n.next, n ) );
    }
}

unittest
{
    SList l;
    //l.pushBack( 1 );
}
