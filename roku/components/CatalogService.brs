sub init()
    m.top.functionName = "run"
end sub

sub run()
    port = CreateObject("roMessagePort")
    ' queryId is the ONLY trigger. Observing every query field separately would
    ' recompute once per field on a multi-field change; the caller sets the
    ' fields and then bumps queryId exactly once.
    m.top.ObserveField("queryId", port)

    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archivewatch.org/catalog-index.json")
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = ""
        print "AWSVC index fetch failed"
        return
    end if
    idx = ParseJson(body)
    body = ""
    if idx = invalid or idx.items = invalid
        print "AWSVC index parse failed"
        return
    end if
    m.items = idx.items
    print "AWSVC ready items="; m.items.Count()
    m.top.ready = true

    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent"
            if msg.GetField() = "queryId" then runQuery()
        end if
    end while
end sub

' Index row order (build_catalog_index.py fields):
'   0 id  1 title  2 year  3 contentType  4 poster  5 pro  6 search  7 backdrop
sub appendRow(root as Object, r as Object)
    it = root.CreateChild("ContentNode")
    it.id = r[0]
    it.title = r[1]
    it.HDPOSTERURL = r[4]
    it.SHORTDESCRIPTIONLINE1 = metaFor(r)
    it.AddField("awBackdrop", "string", false)
    it.AddField("awType", "string", false)
    if r[7] <> invalid then it.awBackdrop = r[7]
    if r[3] <> invalid then it.awType = r[3]
end sub

sub runQuery()
    span = CreateObject("roTimespan")
    span.Mark()

    ' A deep link asks for ONE id and must not pay for a full scan-and-sort.
    wantId = m.top.qId
    if wantId <> ""
        root = CreateObject("roSGNode", "ContentNode")
        for each r in m.items
            if fmt(r[0]) = wantId
                appendRow(root, r)
                exit for
            end if
        end for
        print "AWSVC lookup "; wantId; " found="; root.GetChildCount()
        m.top.total = root.GetChildCount()
        m.top.results = root
        return
    end if
    wantType = LCase(m.top.qType)
    decade = m.top.qDecade
    text = LCase(m.top.qText)
    sort = m.top.qSort

    hits = []
    for each r in m.items
        if wantType <> "" and wantType <> "all"
            t = LCase(fmt(r[3]))
            ' TV browse shows SERIES, never loose episodes (Decision 036).
            if wantType = "tv-series"
                if t <> "tv-series" and t <> "tv-special" then goto_next = true else goto_next = false
            else
                goto_next = (t <> wantType)
            end if
            if goto_next then continue for
        end if
        if decade > 0
            y = r[2]
            if y = invalid then continue for
            if y < decade or y > decade + 9 then continue for
        end if
        if text <> ""
            ' Title first, then the prebuilt search blob — the index carries a
            ' keyword field precisely so a client does not have to fetch more.
            hay = LCase(fmt(r[1]))
            if Instr(1, hay, text) = 0
                blob = LCase(fmt(r[6]))
                if Instr(1, blob, text) = 0 then continue for
            end if
        end if
        hits.Push(r)
    end for

    ' §6.2 — professional posters lead. This is the Home gate (Decision 097)
    ' relaxed into an ORDERING for Browse, where hiding a film the viewer
    ' explicitly filtered for would be worse than showing a plain card.
    if sort = "popular"
        sorted = []
        for each r in hits
            if r[5] = 1 then sorted.Push(r)
        end for
        for each r in hits
            if r[5] <> 1 then sorted.Push(r)
        end for
        hits = sorted
    else if sort = "newest" or sort = "oldest"
        hits = sortByYear(hits, sort = "oldest")
    end if

    total = hits.Count()
    root = CreateObject("roSGNode", "ContentNode")
    n = total
    if n > 300 then n = 300          ' one screenful plus deep scroll
    for i = 0 to n - 1
        appendRow(root, hits[i])
    end for
    print "AWSVC query type="; wantType; " decade="; decade; " text='"; text; "' hits="; total; " in "; span.TotalMilliseconds(); "ms"
    m.top.total = total
    m.top.results = root
end sub

' Insertion sort is fine here: the filtered set is what gets sorted, not the
' whole catalog, and BrightScript has no stable sort for arrays of arrays.
function sortByYear(rows as Object, ascending as Boolean) as Object
    ' A year-less row sorts LAST either way. SQLite's NULL-first default is
    ' exactly the bug the Android TV audit found in Browse's "Oldest", where
    ' page one was year-less modern uploads instead of the oldest films.
    withYear = []
    without = []
    for each r in rows
        if r[2] = invalid then without.Push(r) else withYear.Push(r)
    end for
    n = withYear.Count()
    for i = 1 to n - 1
        cur = withYear[i]
        j = i - 1
        while j >= 0
            cmp = false
            if ascending then cmp = (withYear[j][2] > cur[2]) else cmp = (withYear[j][2] < cur[2])
            if not cmp then exit while
            withYear[j + 1] = withYear[j]
            j = j - 1
        end while
        withYear[j + 1] = cur
    end for
    for each r in without
        withYear.Push(r)
    end for
    return withYear
end function

function metaFor(r as Object) as String
    out = ""
    if r[2] <> invalid then out = fmt(r[2])
    if r[3] <> invalid and r[3] <> ""
        if out <> "" then out = out + "  ·  "
        out = out + prettyType(fmt(r[3]))
    end if
    return out
end function

function prettyType(t as String) as String
    if t = "feature-film" then return "Feature Film"
    if t = "silent-film" then return "Silent Era"
    if t = "short-film" then return "Short Film"
    if t = "tv-series" then return "Classic TV"
    if t = "tv-special" then return "TV"
    if t = "tv-episode" then return "Episode"
    if t = "animation" then return "Animation"
    if t = "newsreel" then return "Newsreel"
    if t = "documentary" then return "Documentary"
    if t = "ephemeral" then return "Ephemeral"
    if t = "commercial" then return "Commercial"
    return t
end function
