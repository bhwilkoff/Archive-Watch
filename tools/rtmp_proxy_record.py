#!/usr/bin/env python3
"""A TCP proxy that records the CLIENT->SERVER byte stream.

Written because two rounds of reasoning about the Android publisher's FLV
framing produced no answer. ffmpeg publishes to the same server correctly, so
the difference is observable: run both through this and compare.
"""
import socket, sys, threading

listen_port = int(sys.argv[1]); target_port = int(sys.argv[2]); out = sys.argv[3]

def pump(src, dst, sink):
    try:
        while True:
            b = src.recv(65536)
            if not b: break
            if sink: sink.write(b); sink.flush()
            dst.sendall(b)
    except Exception:
        pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except Exception: pass

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", listen_port)); srv.listen(4)
print(f"proxy {listen_port} -> {target_port}, recording c->s to {out}", flush=True)
n = 0
while True:
    c, _ = srv.accept()
    n += 1
    s = socket.create_connection(("127.0.0.1", target_port))
    f = open(f"{out}.{n}.bin", "wb")
    threading.Thread(target=pump, args=(c, s, f), daemon=True).start()
    threading.Thread(target=pump, args=(s, c, None), daemon=True).start()
