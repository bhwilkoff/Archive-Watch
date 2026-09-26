sub init()
    m.top.functionName = "run"
end sub

function human(bytes as Double) as String
    if bytes >= 1073741824.0# then return fmt(Int(bytes / 107374182.4#) / 10) + " GB"
    if bytes >= 1048576.0# then return fmt(Int(bytes / 1048576.0#)) + " MB"
    return fmt(Int(bytes / 1024.0#)) + " KB"
end function

function copiesOn(aid as String, other as Boolean) as Dynamic
    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archive.org/metadata/" + aid)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = "" then return invalid
    d = ParseJson(body)
    body = ""
    if d = invalid or d.files = invalid then return invalid

    out = []
    for each f in d.files
        n = LCase(fmt(f.name))
        isVid = false
        if Right(n, 4) = ".mp4" or Right(n, 4) = ".m4v" or Right(n, 5) = ".webm" or Right(n, 4) = ".mkv" then isVid = true
        awSkip = (not isVid)
        ' Decision 104 — a private file can never be fetched, so it is never
        ' offered. Showing one would be offering a copy that cannot play.
        if not awSkip then awSkip = (LCase(fmt(f.private)) = "true")
        ' `continue for` is newer than this channel's firmware floor; the guards
        ' keep their conditions verbatim behind a skip flag.
        if not awSkip

            size = 0.0#
            if f.size <> invalid then size = Val(fmt(f.size))
            bits = []
            h = fmt(f.height)
            if h <> "" and h <> "invalid" then bits.Push(h + "p")
            fm = fmt(f.format)
            if fm <> "" and fm <> "invalid" then bits.Push(fm)
            if size > 0 then bits.Push(human(size))
            src = LCase(fmt(f.source))
            tail = "Archive derivative"
            if src = "original" then tail = "uploader original"

            label = ""
            for i = 0 to bits.Count() - 1
                if i > 0 then label = label + " · "
                label = label + bits[i]
            end for
            if label = "" then label = fmt(f.name)
            if other then label = label + " · another upload"
            label = label + " — " + tail

            out.Push({ name: fmt(f.name), label: label, size: size, source: src, item: aid })
        end if
    end for
    return out
end function

' The ids aliases.json forwards to this title — the same file the web reads.
function mergedInto(aid as String) as Object
    ids = []
    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archivewatch.org/aliases.json")
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = "" then return ids
    map = ParseJson(body)
    body = ""
    if map = invalid then return ids
    for each k in map
        if map[k] = aid and k <> aid then ids.Push(k)
    end for
    return ids
end function

sub run()
    aid = m.top.archiveID
    if aid = ""
        m.top.status = "error"
        return
    end if
    out = copiesOn(aid, false)
    if out = invalid
        m.top.status = "error"
        return
    end if
    ' UPLOADS MERGED INTO THIS TITLE (Decision 040), so their copies can be
    ' chosen too. Owner, 2026-09-22, on Keaton's two Scarecrows: "folded
    ' together as different versions that can be pulled in the versions
    ' picker". Read only when the picker opens, like the rest of this task.
    for each other in mergedInto(aid)
        more = copiesOn(other, true)
        if more <> invalid
            for each v in more
                out.Push(v)
            end for
        end if
    end for

    ' Largest first inside each source group, originals last: the pipeline's
    ' pick is usually a derivative and is usually right, so the list opens on
    ' what is already playing rather than reordering the world around a number.
    ordered = []
    for each v in out
        if v.source <> "original" then ordered.Push(v)
    end for
    for each v in out
        if v.source = "original" then ordered.Push(v)
    end for

    print "AWVER "; aid; " playable copies="; ordered.Count()
    m.top.versions = ordered
    m.top.status = "ready"
end sub
