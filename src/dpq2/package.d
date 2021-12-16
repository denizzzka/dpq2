/**
 * Main module
 *
 * Include it to use common functions.
 */
module dpq2;

public import dpq2.dynloader;
public import dpq2.connection;
public import dpq2.query;
public import dpq2.result;
public import dpq2.oids;


version(DerelictPQ_Static){}
else version(DerelictPQ_Dynamic) {}
else static assert(false, "DerelictPQ type (dynamic or static) isn't defined");
