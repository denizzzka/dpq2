@trusted:

version( unittest )
{
    import std.getopt;
    
    import conn = dpq2.connection: _unittest;
    import query = dpq2.query: _unittest;

    int main(string[] args)
    {
        string conninfo;
        getopt( args, "conninfo", &conninfo );

        conn._unittest( conninfo );
        query._unittest( conninfo );
        
        return 0;
    }
}
