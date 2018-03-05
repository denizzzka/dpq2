/// Wrapper around socket types
/// Copyright: Copyright (c) 2017 Nemanja Boric
module dpq2.native_conn.internal.socket;

struct Socket
{
    import std.bitmanip;
    import std.array;

    static if(__traits(compiles, (){ import vibe.core.net; } ))
    {
        import vibe.core.net;

        private TCPConnection conn;

        // receive buffer
        private ubyte[] receive_buf;

        public void connect (string host, ushort port)
        {
            this.conn = connectTCP(host, port);
            this.conn.keepAlive = true;
        }

        public ptrdiff_t receive (ref Appender!(ubyte[]) app,
                size_t bytes_need)
        {
            this.receive_buf.assumeSafeAppend.length = bytes_need;
            this.conn.read(this.receive_buf);
            app.put(this.receive_buf[0..$]);
            return bytes_need;
        }

        public ptrdiff_t receive(T) (ref T t)
        {
            ubyte[T.sizeof] buf;
            this.conn.read(buf);

            t = bigEndianToNative!(T, T.sizeof)(buf);
            return T.sizeof;
        }

        public void send (ubyte[] data)
        {
            this.conn.write(data);
        }

    }
    else
    {
        import PhobosSocket = std.socket;

        private PhobosSocket.Socket sock;

        /// Receive buffer
        private const chunk_size = 1024;

        /// ditto
        private ubyte[chunk_size] receive_buf;

        public void connect (string host, ushort port)
        {
            this.sock = new typeof(this.sock)(
                    PhobosSocket.AddressFamily.INET,
                    PhobosSocket.SocketType.STREAM);

            this.sock.connect(new PhobosSocket.InternetAddress(host, port));

            version (linux)
            {
                this.sock.setKeepAlive(5, 5);
            }
        }

        public ptrdiff_t receive (ref Appender!(ubyte[]) app,
                size_t bytes_need)
        {
            ptrdiff_t received = 0;

            while (received < bytes_need)
            {
                auto need = bytes_need - received;
                auto recv = need > chunk_size ? chunk_size : need;

                auto ret = this.sock.receive(this.receive_buf[0..need]);

                if (ret == PhobosSocket.Socket.ERROR)
                {
                    return ret;
                }

                app.put(this.receive_buf[0..need]);

                received += need;
            }

            return received;
        }

        public ptrdiff_t receive(T) (ref T t)
        {
            ubyte[T.sizeof] buf;
            auto ret = this.sock.receive(buf);

            if (ret == PhobosSocket.Socket.ERROR)
            {
                return ret;
            }

            t = bigEndianToNative!(T, T.sizeof)(buf);
            return ret;
        }

        public void send (void[] data)
        {
            this.sock.send(data);
        }

        public ~this()
        {
            this.sock.shutdown(
                    PhobosSocket.SocketShutdown.BOTH
            );

            this.sock.close();
        }
    }
}
