#!/usr/bin/env python3
"""A TCP proxy that THROTTLES the client->server direction after a delay.

WATCH-TOGETHER §6.4's condition: an uplink that is not gone (that is §6.6)
but too narrow for the program. Throttling here rather than in the publisher
is the whole point — the publisher must discover congestion the way it will
on a real network, through its own send buffer filling up.

    rtmp_throttle_proxy.py <listen> <target> <open_seconds> <rate_bps> <throttle_seconds>

Full rate for `open_seconds` so the publish completes and the stream settles,
then `rate_bps` for `throttle_seconds`, then full rate again so recovery is
observable too. A token bucket, refilled every 50 ms.

Only connections that actually send bytes are counted, so a harness's
port-readiness probe cannot be mistaken for the publisher — that mistake cost
a whole run of the §6.6 harness, where the probe absorbed the event.
"""
import os, socket, sys, threading, time

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])
open_seconds = float(sys.argv[3])
rate_bps = float(sys.argv[4])
throttle_seconds = float(sys.argv[5])

started = None
lock = threading.Lock()
counted = 0


def phase(now):
    """'open' | 'throttled' | 'recovered'"""
    if started is None:
        return "open"
    t = now - started
    if t < open_seconds:
        return "open"
    if t < open_seconds + throttle_seconds:
        return "throttled"
    return "recovered"


def pump_throttled(src, dst):
    """Client -> server, rate-limited BY THE READ.

    Throttling the WRITE is the obvious mistake and it does not test anything:
    a proxy that does `recv(65536)` at full speed and then dawdles on the
    forward drains the client's socket into its own memory, so the client never
    feels congestion. Measured 2026-09-17 against the macOS Studio: the server
    saw the intended 400 kbps while the app reported `queued` near zero and
    dropped NOTHING, because from its side the link was never slow.

    Real back-pressure comes from NOT READING. The token bucket therefore sizes
    each `recv`, and when there are no tokens this loop sleeps WITHOUT reading —
    the client's send buffer fills, and on Apple that is exactly what defers
    `NWConnection`'s contentProcessed and makes queuedBytes climb.
    """
    tokens = 0.0
    last = time.time()
    announced = None
    try:
        while True:
            now = time.time()
            ph = phase(now)
            if ph != announced:
                print(f"phase: {ph}", flush=True)
                announced = ph
            if ph == "throttled":
                tokens += (now - last) * rate_bps / 8.0
                last = now
                # Never bank the whole outage: a burst on re-open would hide
                # the congestion being measured.
                tokens = min(tokens, rate_bps / 8.0 * 0.25)
                if tokens < 1500:
                    time.sleep(0.02)      # deliberately NOT reading
                    continue
                want = min(int(tokens), 65536)
                b = src.recv(want)
                if not b:
                    break
                tokens -= len(b)
                dst.sendall(b)
            else:
                last = time.time()
                tokens = 0.0
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


def pump_plain(src, dst):
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
    global started, counted
    # LOG THE ACCEPT, not just the publish. A connection that arrives and sends
    # nothing is invisible otherwise, and so is one that never arrives — which
    # made a failing back-pressure run on 2026-09-20 indistinguishable between
    # "the publisher went somewhere else" and "the proxy dropped it".
    try:
        peer = client.getpeername()
    except Exception:
        peer = "?"
    print(f"accept from {peer}", flush=True)
    try:
        first = client.recv(65536)
    except Exception:
        print(f"accept from {peer}: recv failed", flush=True)
        client.close(); return
    if not first:
        print(f"accept from {peer}: sent nothing (a readiness probe)", flush=True)
        client.close(); return          # a readiness probe, not a publisher
    with lock:
        counted += 1
        index = counted
        if started is None:
            started = time.time()
    try:
        upstream = socket.create_connection(("127.0.0.1", target_port))
    except Exception as e:
        print(f"conn {index}: upstream refused: {e}", flush=True)
        client.close(); return
    print(f"conn {index}: open (full rate for {open_seconds}s, then "
          f"{rate_bps/1000:.0f} kbps for {throttle_seconds}s)", flush=True)
    upstream.sendall(first)
    threading.Thread(target=pump_throttled, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump_plain, args=(upstream, client), daemon=True).start()


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
# 127.0.0.1 by DEFAULT: a harness on this machine should not open a port
# to the network. AW_PROXY_BIND=0.0.0.0 is the opt-in for driving a real
# DEVICE at it, which is the only way the Android engine can be tested
# through the shipping app rather than from a JVM.
bind_host = os.environ.get("AW_PROXY_BIND", "127.0.0.1")
srv.bind((bind_host, listen_port))
srv.listen(8)
print(f"throttle-proxy {bind_host}:{listen_port} -> {target_port}", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
