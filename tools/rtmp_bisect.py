#!/usr/bin/env python3
"""Bisect an RTMP publisher against a KNOWN-GOOD one, at the byte level.

Written 2026-09-17, after two rounds of reasoning about the Android
publisher's FLV framing produced nothing. ffmpeg publishes to the same server
correctly, so the difference is observable rather than arguable:

  1. `tools/rtmp_proxy_record.py 19352 19351 out.bin` records the CLIENT->SERVER
     stream of anything publishing through it.
  2. Publish once with ffmpeg and once with the client under test.
  3. Replay either capture verbatim to the server and it is accepted or
     refused exactly as the live client was. THAT is what makes bisection
     possible: the failure reproduces offline, with no client at all.
  4. Splice the two streams at a message boundary and replay the hybrid.
     Each run halves the search space.

The result on first use, in five runs:

    ffmpeg preamble + our media                 FAILED
    our preamble + ffmpeg media                 WORKED
    our preamble + our metadata + ffmpeg media  WORKED
    our sequence headers + ffmpeg frames        WORKED
    ffmpeg sequence headers + our frames        FAILED

That looked conclusive and was WRONG, which is the most useful thing this file
records. The splices kept failing with ffmpeg's OWN bodies in them, every
variable eliminated, until the control that mattered was finally run:

    ffmpeg's full original stream             WORKED
    ffmpeg's first 80 original frame messages FAILED

mediamtx does not declare a path ready on the first second of media. Every
splice above was ~60-80 messages, so each "FAILED" measured the LENGTH OF THE
BURST and not the correctness of the bytes. The publisher was correct
throughout.

ALWAYS RUN THE OPPOSITE CONTROL. Feed the known-good source through the same
harness in the same shape as the thing under test. If the known-good input
also fails, the harness is the bug — and that check costs two minutes against
the session this one cost.
"""
import socket, sys, time

def scan(path):
    """Returns [(start, end, type, csid, bodylen)] for each message, after the handshake."""
    d=open(path,'rb').read(); i=1+1536+1536; chunk=128; prev={}; out=[]
    while i < len(d):
        start=i
        b0=d[i]; fmt=b0>>6; csid=b0&0x3F; i+=1
        if fmt==0: ln=int.from_bytes(d[i+3:i+6],'big'); typ=d[i+6]; i+=11; prev[csid]=(ln,typ)
        elif fmt==1: ln=int.from_bytes(d[i+3:i+6],'big'); typ=d[i+6]; i+=7; prev[csid]=(ln,typ)
        elif fmt==2: i+=3; ln,typ=prev.get(csid,(0,0))
        else: ln,typ=prev.get(csid,(0,0))
        need=ln; body=b''
        while need>0:
            take=min(chunk,need); body+=d[i:i+take]; i+=take; need-=take
            if need>0: i+=1
        if typ==1 and len(body)>=4: chunk=int.from_bytes(body[:4],'big')&0x7FFFFFFF
        out.append((start,i,typ,csid,ln))
        if i>=len(d): break
    return d, out

def send(stream, label):
    s=socket.create_connection(("127.0.0.1",19351),timeout=5)
    s.sendall(stream[:1537]); time.sleep(0.3)
    try: s.recv(65536)
    except Exception: pass
    s.sendall(stream[1537:1537+1536]); time.sleep(0.2)
    s.sendall(stream[1537+1536:]); time.sleep(2.5)
    s.close(); print(f"  sent {label}: {len(stream)} bytes")

kd, km = scan('ff.bin.5.bin')   # kotlin
fd, fm = scan('ff.bin.3.bin')   # ffmpeg
print("kotlin messages:", [(t,c,l) for _,_,t,c,l in km][:8])
print("ffmpeg messages:", [(t,c,l) for _,_,t,c,l in fm][:8])

which = sys.argv[1]
head = kd[:1+1536+1536]
if which == "ffmpeg-connect":
    # our stream, but ffmpeg's connect message spliced in
    fs,fe,_,_,_ = fm[0]
    ks,ke,_,_,_ = km[0]
    out = head + fd[fs:fe] + kd[ke:]
    send(out, "kotlin with ffmpeg's connect")
elif which == "ffmpeg-preamble":
    # ffmpeg's first 6 messages (through publish), then our media
    fend = fm[5][1]
    kstart = km[5][1]
    out = head + fd[1+1536+1536:fend] + kd[kstart:]
    send(out, "ffmpeg preamble + kotlin media")
elif which == "kotlin-preamble":
    # our first 6 messages, then ffmpeg's media
    kend = km[5][1]
    fstart = fm[5][1]
    out = head + kd[1+1536+1536:kend] + fd[fstart:]
    send(out, "kotlin preamble + ffmpeg media")

if which == "ours-through-metadata":
    # our preamble AND our metadata, then ffmpeg's media only
    kend = km[6][1]     # through message 6 = metadata
    fstart = fm[6][1]
    out = head + kd[1+1536+1536:kend] + fd[fstart:]
    send(out, "kotlin preamble+metadata + ffmpeg media")
if which == "ours-media-only":
    # ffmpeg preamble AND ffmpeg metadata, then OUR media only
    fend = fm[6][1]
    kstart = km[6][1]
    out = head + fd[1+1536+1536:fend] + kd[kstart:]
    send(out, "ffmpeg preamble+metadata + kotlin media")

if which == "ours-seqheaders":
    # ours through BOTH sequence headers (msg 8), then ffmpeg's frames
    out = head + kd[1+1536+1536:km[8][1]] + fd[fm[8][1]:]
    send(out, "kotlin preamble+metadata+seqheaders + ffmpeg frames")
if which == "ours-frames":
    # ffmpeg through both sequence headers, then OUR frames
    out = head + fd[1+1536+1536:fm[8][1]] + kd[km[8][1]:]
    send(out, "ffmpeg preamble+metadata+seqheaders + kotlin frames")

if which == "ours-video-frames-only":
    # ffmpeg through both sequence headers, then ONLY our type-9 frames
    out = head + fd[1+1536+1536:fm[8][1]]
    for (st,en,typ,csid,ln) in km[9:]:
        if typ == 9: out += kd[st:en]
    send(out, "ffmpeg headers + kotlin VIDEO frames only")
if which == "ours-audio-frames-only":
    out = head + fd[1+1536+1536:fm[8][1]]
    for (st,en,typ,csid,ln) in km[9:]:
        if typ == 8: out += kd[st:en]
    send(out, "ffmpeg headers + kotlin AUDIO frames only")

if which == "ours-all-x4":
    # the whole kotlin stream, with its frames repeated so the server has
    # several seconds rather than one to make up its mind
    frames = b''.join(kd[st:en] for (st,en,typ,c,l) in km[9:])
    out = head + kd[1+1536+1536:km[8][1]] + frames*4
    send(out, "kotlin, frames x4")
