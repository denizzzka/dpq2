/**
 * This package is not intended for direct use by end users.
 * It exists solely to facilitate writing asynchronous wrappers around dpq2/PosgreSQL connections.
 */
module dpq2.async;

public import dpq2.async.waiter;
public import dpq2.async.poll;
public import dpq2.async.connection;
