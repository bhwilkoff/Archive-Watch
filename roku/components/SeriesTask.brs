sub init()
    m.top.functionName = "run"
end sub

sub run()
    slug = m.top.slug
    if slug = "" 
        m.top.status = "error"
        return
    end if
    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archivewatch.org/series/" + slug + ".json")
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = ""
        print "AWSER fetch failed "; slug
        m.top.status = "error"
        return
    end if
    d = ParseJson(body)
    body = ""
    if d = invalid or d.seasons = invalid
        m.top.status = "error"
        return
    end if
    n = 0
    for each s in d.seasons
        if s.episodes <> invalid then n = n + s.episodes.Count()
    end for
    print "AWSER "; slug; " seasons="; d.seasons.Count(); " episodes="; n
    m.top.series = d
    m.top.status = "ready"
end sub
