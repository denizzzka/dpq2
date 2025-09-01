/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2;

public import dpq2.dynloader;
public import dpq2.cancellation;
public import dpq2.connection;
public import dpq2.query;
public import dpq2.result;
public import dpq2.oids;


version(Dpq2_Static){}
else version(Dpq2_Dynamic){}
else static assert(false, "dpq2 link type (dynamic or static) isn't defined");
