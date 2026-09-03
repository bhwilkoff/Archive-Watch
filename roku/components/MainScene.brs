sub init()
    m.status = m.top.FindNode("status")
    m.detail = m.top.FindNode("detail")

    ' A Scene must hold focus or the remote does nothing at all — the Roku
    ' equivalent of the tvOS/Compose rule that something is ALWAYS focused.
    m.top.setFocus(true)

    m.task = CreateObject("roSGNode", "CatalogTask")
    m.task.ObserveField("status", "onStatus")
    m.task.ObserveField("report", "onReport")
    m.task.control = "RUN"

    print "AWROKU scene init"
end sub

sub onStatus()
    s = m.task.status
    if s = "downloading"
        m.status.text = "Downloading the catalog index…"
    else if s = "parsing"
        m.status.text = "Parsing 6.2 MB of catalog…"
    else if s = "ready"
        m.status.text = "Catalog ready"
    else if s = "error"
        m.status.text = "Could not load the catalog"
    end if
    print "AWROKU status="; s
end sub

sub onReport()
    r = m.task.report
    if r = invalid then return

    if r.error <> invalid
        m.detail.text = r.error
        return
    end if

    ' Put the measurement ON THE GLASS. A screenshot then proves the numbers,
    ' which is the standing rule here: never trust the app's own report alone,
    ' but a number rendered on the device and photographed is evidence.
    lines = []
    lines.Push("device       " + fmt(r.model))
    lines.Push("index        " + fmt(r.bytes) + " bytes, schema " + fmt(r.schema))
    lines.Push("download     " + fmt(r.downloadMs) + " ms")
    lines.Push("ParseJson    " + fmt(r.parseMs) + " ms")
    lines.Push("items        " + fmt(r.itemCount))
    lines.Push("shelves      " + fmt(r.shelfCount))
    lines.Push("memory level " + fmt(r.memBefore) + " -> " + fmt(r.memAfter))
    m.detail.text = lines.Join(Chr(10))
end sub

' BrightScript has no universal to-string. `Str()` takes a FLOAT, so calling it
' on a String is a runtime Type Mismatch that halts the channel — it took down
' the first build here. Anything printed to the screen goes through this.
function fmt(v as Dynamic) as String
    if v = invalid then return "?"
    t = type(v)
    if t = "String" or t = "roString" then return v
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" then return v.ToStr()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Str(v).Trim()
    if t = "Boolean" or t = "roBoolean" then
        if v then return "true"
        return "false"
    end if
    return "?"
end function

' Back at the root closes the channel, which is the Roku convention and a
' certification requirement — do NOT trap it.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press then print "AWROKU key="; key
    return false
end function
