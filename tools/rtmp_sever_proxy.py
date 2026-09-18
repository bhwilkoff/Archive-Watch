#!/usr/bin/env python3
"""A TCP proxy that SEVERS the first connection after N seconds.

WATCH-TOGETHER §6.6's negative event. Killing mediamtx itself would also end
the recording we need to read the answer out of, and pulling real Wi-Fi is not
something a harness can do; severing the socket in the middle reproduces
exactly what a domestic link does, once, on demand.

    rtmp_sever_proxy.py <listen> <target> <sever_after_seconds>

The FIRST connection is cut after the delay. Every later connection — the
publisher's reconnect — is proxied untouched, so the test can tell "resumed"
from "never stopped". Prints one line per event so the harness can assert the
sever actually happened rather than assuming it did.
"""
import os, socket, struct, sys, threading, time

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])
sever_after = float(sys.argv[3])

conn_index = 0
index_lock = threading.Lock()

def pump(src, dst):
    try:
        while True:
            b = src.recv(65536)
            if not b:
                break
            dst.sendall(b)
    except Exception:
        pass
    finally:
        for s in (src, dst):
            try: s.close()
            except Exception: pass

def serve(client):
    """Forward one connection, and cut the first one that carries MEDIA.

    The index is assigned only once the client has actually sent bytes. A
    readiness probe that connects and closes without speaking would otherwise
    become connection 1 and absorb the sever — which is exactly what happened
    the first time this ran: the harness's own "is the port listening?" check
    ate the cut, the publisher was never severed, and the CONTROL arm recorded
    a full clean stream. A test instrument must not be visible to the test.
    """
    global conn_index
    try:
        first = client.recv(65536)
    except Exception:
        client.close()
        return
    if not first:
        # A probe, not a publisher. Nothing to forward and nothing to count.
        client.close()
        return
    with index_lock:
        conn_index += 1
        index = conn_index
    try:
        upstream = socket.create_connection(("127.0.0.1", target_port))
    except Exception as e:
        print(f"conn {index}: upstream refused: {e}", flush=True)
        client.close()
        return
    print(f"conn {index}: open", flush=True)
    upstream.sendall(first)
    if index == 1:
        def cut():
            time.sleep(sever_after)
            print(f"conn {index}: SEVERED after {sever_after}s", flush=True)
            # RST rather than a polite FIN: a link that drops does not say
            # goodbye, and a FIN is the one case the publisher already handled.
            try:
                client.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                                  struct.pack("ii", 1, 0))
            except Exception:
                pass
            for s in (client, upstream):
                try: s.close()
                except Exception: pass
        threading.Thread(target=cut, daemon=True).start()
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
# 127.0.0.1 by DEFAULT: a harness on this machine should not open a port
# to the network. AW_PROXY_BIND=0.0.0.0 is the opt-in for driving a real
# DEVICE at it, which is the only way the Android engine can be tested
# through the shipping app rather than from a JVM.
bind_host = os.environ.get("AW_PROXY_BIND", "127.0.0.1")
srv.bind((bind_host, listen_port))
srv.listen(8)
print(f"sever-proxy {bind_host}:{listen_port} -> {target_port}, cutting conn 1 after {sever_after}s", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
