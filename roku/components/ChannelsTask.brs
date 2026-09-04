sub init()
    m.top.functionName = "run"
end sub

sub run()
    print SchedSelfTest()
    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archivewatch.org/channel-pools.json")
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
    if d = invalid or d.channels = invalid
        m.top.status = "error"
        return
    end if
    print "AWCH pools channels="; d.channels.Count(); " commercials="; (d.commercials <> invalid)
    m.top.channels = { list: d.channels, ads: d.commercials }
    m.top.status = "ready"
end sub
