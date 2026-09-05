sub init()
    m.top.functionName = "run"
end sub

' The shard is the LOW BYTE of the FNV-1a 32-bit hash of the archiveID
' (tools/build_web_details.py; watch.js implements the same function).
'
' BrightScript integers are 32-bit SIGNED, so the real algorithm's
' multiply-and-wrap is awkward and easy to get subtly wrong. It is also
' unnecessary: multiplication modulo 256 depends only on the operands modulo
' 256, and XOR touches the low byte using only the low byte — so the whole
' hash can be carried in 8 bits and still agree exactly with the 32-bit
' version. Verified against 240 real ids from the published shards before this
' was written: zero mismatches.
'   2166136261 mod 256 = 197      16777619 mod 256 = 147
function shardOf(id as String) as String
    h = 197
    for i = 0 to Len(id) - 1
        b = Asc(Mid(id, i + 1, 1))
        ' BrightScript has no XOR operator. For non-negative integers
        ' a XOR b == (a OR b) - (a AND b); verified over all 65,536 byte pairs.
        hb = h and 255
        bb = b and 255
        h = ((hb or bb) - (hb and bb)) * 147
        h = h mod 256
    end for
    hex = "0123456789abcdef"
    hi = (h - (h mod 16)) / 16
    lo = h mod 16
    return Mid(hex, hi + 1, 1) + Mid(hex, lo + 1, 1)
end function

sub run()
    aid = m.top.archiveID
    if aid = invalid or aid = ""
        m.top.status = "error"
        return
    end if
    m.top.status = "loading"

    url = "https://archivewatch.org/details/" + shardOf(aid) + ".json"
    x = CreateObject("roUrlTransfer")
    x.SetUrl(url)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.3 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = ""
        print "AWROKU detail: empty shard "; url
        m.top.status = "error"
        return
    end if

    shard = ParseJson(body)
    if shard = invalid or shard[aid] = invalid
        print "AWROKU detail: "; aid; " not in shard "; shardOf(aid)
        m.top.status = "error"
        return
    end if

    ' Record order (build_web_details.py): url, synopsis, director, cast,
    ' genres, runtimeSeconds, backdrop, captions, community, extras.
    r = shard[aid]
    d = {}
    if r.Count() > 0 then d.url = r[0]
    if r.Count() > 1 then d.synopsis = r[1]
    if r.Count() > 2 then d.director = r[2]
    if r.Count() > 3 then d.cast = r[3]
    if r.Count() > 4 then d.genres = r[4]
    if r.Count() > 5 then d.runtime = r[5]
    if r.Count() > 6 then d.backdrop = r[6]
    if r.Count() > 7 then d.captions = r[7]
    ' archive.org community signals (Decision 041): { r: avg rating, v: views,
    ' f: favorites, rv: [[stars, title, body, reviewer, date], ...] }.
    if r.Count() > 8 and r[8] <> invalid then d.community = r[8]
    if r.Count() > 9 and r[9] <> invalid
        ' Decision 100 — a film's other release title is SHOWN, never
        ' reconciled. `ct` is the canonical title from the external match.
        if r[9].ct <> invalid then d.canonicalTitle = r[9].ct
    end if
    print "AWROKU detail ok "; aid; " url="; (d.url <> invalid)
    m.top.detail = d
    m.top.status = "ready"
end sub
