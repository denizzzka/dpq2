@trusted:

version( unittest )
{
    import std.getopt;
    
    import conn = dpq2.connection: _unittest;
    import query = dpq2.query: _unittest;
    import answer = dpq2.answer: _unittest;
    import bincast = dpq2.bincast: _unittest;

    int main(string[] args)
    {
        string conninfo;
        getopt( args, "conninfo", &conninfo );

        conn._unittest( conninfo );
        query._unittest( conninfo );
        answer._unittest( conninfo );
        bincast._unittest( conninfo );
        
        return 0;
    }
}
