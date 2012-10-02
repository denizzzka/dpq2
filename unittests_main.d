@trusted:

version( unittest )
{
    import std.getopt;
    
    import conn = dpq2.connection: external_unittest;
    import query = dpq2.query: external_unittest;

    int main(string[] args)
    {
        string conninfo;
        getopt( args, "conninfo", &conninfo );

        conn.external_unittest( conninfo );
        query.external_unittest( conninfo );
        
        return 0;
    }
}
