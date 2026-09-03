sub init()
    m.top.functionName = "run"
end sub

' Download and parse the catalog index, MEASURING both, because the size of
' that file is the open question for this platform: 6.2 MB and ~27,000 items is
' nothing on a phone and may be a great deal on a streaming stick. The numbers
' this prints decide whether the web data plane is reusable as-is or whether
' Roku needs a slimmer feed of its own.
sub run()
    url = m.top.indexUrl
    if url = invalid or url = "" then url = "https://archivewatch.org/catalog-index.json"

    di = CreateObject("roDeviceInfo")
    report = {}
    report.model = di.GetModelDisplayName()
    report.memBefore = di.GetGeneralMemoryLevel()

    m.top.status = "downloading"
    span = CreateObject("roTimespan")
    span.Mark()

    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    ' HTTPS on Roku needs the cert bundle named explicitly; without these two
    ' lines the transfer fails silently and returns an empty string.
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("User-Agent", "ArchiveWatch-Roku/0.1 (+https://archivewatch.org)")
    xfer.EnableEncodings(true)      ' gzip: 6.2 MB on the wire is otherwise wasteful
    body = xfer.GetToString()

    report.downloadMs = span.TotalMilliseconds()
    report.bytes = Len(body)

    if report.bytes = 0
        m.top.status = "error"
        report.error = "empty response from " + url
        m.top.report = report
        print "AWROKU error: empty response from "; url
        return
    end if

    m.top.status = "parsing"
    span.Mark()
    parsed = ParseJson(body)
    report.parseMs = span.TotalMilliseconds()

    if parsed = invalid
        m.top.status = "error"
        report.error = "ParseJson returned invalid"
        m.top.report = report
        print "AWROKU error: ParseJson returned invalid"
        return
    end if

    report.schema = parsed.schema
    report.count = parsed.count
    if parsed.items <> invalid then report.itemCount = parsed.items.Count()
    if parsed.shelves <> invalid then report.shelfCount = parsed.shelves.Count()
    report.memAfter = di.GetGeneralMemoryLevel()

    ' Free the source string before handing the tree over — holding both the
    ' 6 MB string and the parsed tree is the peak this device has to survive.
    body = ""

    ' PRINT BEFORE PUBLISHING. Setting m.top.report fires the Scene's observer,
    ' and a crash in that observer halts the channel — which is exactly what
    ' happened on the first run and hid a measurement that had already been
    ' taken successfully. The number belongs in the log before anything else
    ' can fail.
    print "AWROKU index ok bytes="; report.bytes; " downloadMs="; report.downloadMs; " parseMs="; report.parseMs; " items="; report.itemCount; " shelves="; report.shelfCount; " mem="; report.memBefore; "->"; report.memAfter

    m.top.items = parsed.items
    m.top.report = report
    m.top.status = "ready"
end sub
