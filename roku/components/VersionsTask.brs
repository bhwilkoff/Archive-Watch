sub init()
    m.top.functionName = "run"
end sub

function human(bytes as Double) as String
    if bytes >= 1073741824.0# then return fmt(Int(bytes / 107374182.4#) / 10) + " GB"
    if bytes >= 1048576.0# then return fmt(Int(bytes / 1048576.0#)) + " MB"
    return fmt(Int(bytes / 1024.0#)) + " KB"
end function

sub run()
    aid = m.top.archiveID
    if aid = ""
        m.top.status = "error"
        return
    end if
    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archive.org/metadata/" + aid)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = ""
        m.top.status = "error"
        return
    end if
    d = ParseJson(body)
    body = ""
    if d = invalid or d.files = invalid
        m.top.status = "error"
        return
    end if

    out = []
    for each f in d.files
        n = LCase(fmt(f.name))
        isVid = false
        if Right(n, 4) = ".mp4" or Right(n, 4) = ".m4v" or Right(n, 5) = ".webm" or Right(n, 4) = ".mkv" then isVid = true
        if not isVid then continue for
        ' Decision 104 — a private file can never be fetched, so it is never
        ' offered. Showing one would be offering a copy that cannot play.
        if LCase(fmt(f.private)) = "true" then continue for

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
        label = label + " — " + tail

        out.Push({ name: fmt(f.name), label: label, size: size, source: src })
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
