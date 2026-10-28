sub init()
    m.top.functionName = "lookUpAlias"
end sub

sub lookUpAlias()
    aid = m.top.archiveID
    if aid = ""
        m.top.target = ""
        return
    end if
    ' Kept in tmp:/ for the rest of the launch, so a second miss costs a read.
    body = ReadAsciiFile("tmp:/aliases.json")
    if body = ""
        x = CreateObject("roUrlTransfer")
        x.SetUrl("https://archivewatch.org/aliases.json")
        x.SetCertificatesFile("common:/certs/ca-bundle.crt")
        x.InitClientCertificates()
        x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
        x.EnableEncodings(true)
        body = x.GetToString()
        if body <> "" then WriteAsciiFile("tmp:/aliases.json", body)
    end if
    target = ""
    if body <> ""
        map = ParseJson(body)
        body = ""
        if map <> invalid
            if GetInterface(map, "ifAssociativeArray") <> invalid
                ' A chain (a survivor later merged again) is followed, a few
                ' steps at most, never round a loop.
                cur = aid
                for hops = 1 to 4
                    nxt = map[cur]
                    if nxt = invalid then exit for
                    if fmt(nxt) = "" or fmt(nxt) = cur then exit for
                    cur = fmt(nxt)
                end for
                if cur <> aid then target = cur
            end if
        end if
    end if
    print "AWALIAS "; aid; " -> '"; target; "'"
    m.top.target = target
end sub
