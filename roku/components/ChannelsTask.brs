sub init()
    m.top.functionName = "run"
end sub

function fetchJson(url as String) as Dynamic
    x = CreateObject("roUrlTransfer")
    x.SetUrl(url)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = "" then return invalid
    return ParseJson(body)
end function

' The guide is the published schedule (ROKU-DESIGN 6.7). Without it there is
' no guide at all — never a local stand-in, which would put this Roku on a
' different programme from every other screen. The pools file is still read
' for the commercials between programmes and the Cartoon Marathon's queue.
sub run()
    t0 = CreateObject("roTimespan")
    sched = fetchJson("https://archivewatch.org/channel-schedule.json")
    print "AWCH schedule parsed in "; t0.TotalMilliseconds(); " ms"
    if sched = invalid or sched.channels = invalid or sched.programs = invalid
        m.top.status = "error"
        return
    end if
    pools = fetchJson("https://archivewatch.org/channel-pools.json")
    byId = {}
    ads = invalid
    if pools <> invalid and pools.channels <> invalid
        for each c in pools.channels
            byId[fmt(c.id)] = c.programs
        end for
        ads = pools.commercials
    end if
    gap = 120
    if sched.gap <> invalid then gap = Int(sched.gap)
    nowS = nowUtcSeconds()
    list = []
    for each c in sched.channels
        slots = slotsFromSchedule(c, sched.programs, gap, nowS)
        if slots.Count() > 0
            list.Push({ id: c.id, title: c.title, tagline: c.tagline, accent: c.accent,
                        programs: byId[fmt(c.id)], slots: slots })
        end if
    end for
    sched = invalid
    pools = invalid
    print "AWCH schedule channels="; list.Count(); " commercials="; (ads <> invalid); " built in "; t0.TotalMilliseconds(); " ms"
    if list.Count() = 0
        m.top.status = "error"
        return
    end if
    m.top.channels = { list: list, ads: ads }
    m.top.status = "ready"
end sub
