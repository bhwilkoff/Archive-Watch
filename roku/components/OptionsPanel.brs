sub init()
    m.t = Theme()
    m.dim = m.top.FindNode("dim")
    m.plate = m.top.FindNode("plate")
    m.title = m.top.FindNode("title")
    m.rowsG = m.top.FindNode("rows")
    m.note = m.top.FindNode("note")

    m.dim.width = 1920 : m.dim.height = 1080 : m.dim.color = "0x000000BB"

    pw = 726
    px = 1920 - pw
    m.plate.translation = [px, 0]
    m.plate.width = pw : m.plate.height = 1080
    m.plate.color = "0x121216FF"

    m.title.font = m.t.uScreen : m.title.color = m.t.textPri
    m.title.translation = [px + 42, 78]
    m.title.text = "Options"

    ' LabelList is Roku's OWN menu control — left-aligned rows, platform focus
    ' behaviour, no per-row wiring. The first build of this panel used Button
    ' nodes, which centre their text against a decorative bullet and read
    ' nothing like a Roku overlay.
    m.rowsG.translation = [px + 42, 186]
    m.rowsG.itemSize = [642, 78]
    m.rowsG.itemSpacing = [0, 18]
    m.rowsG.numRows = 4
    m.rowsG.font = m.t.uBody
    m.rowsG.color = m.t.textPri
    m.rowsG.focusedColor = m.t.marquee
    m.rowsG.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.rowsG.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.rowsG.drawFocusFeedbackOnTop = true
    m.rowsG.vertFocusAnimationStyle = "fixedFocusWrap"
    m.rowsG.ObserveField("itemSelected", "onRow")

    m.note.font = m.t.uMeta : m.note.color = m.t.textSec
    m.note.translation = [px + 42, 654]
    m.note.width = pw - 84 : m.note.wrap = true
    m.note.text = "This product uses the TMDB API but is not endorsed or certified by TMDB." + Chr(10) + Chr(10) + "Metadata: TMDb, OMDb, TheTVDB, Wikidata, Wikimedia Commons, Library of Congress. Films: archive.org." + Chr(10) + Chr(10) + "Archive Watch is free. The Internet Archive is not — support it at archive.org/donate."

    m.defs = [
        { id: "hidewatched", label: "Hide watched titles" },
        { id: "autoplay", label: "Autoplay next episode" },
        { id: "clearcw",  label: "Clear Continue Watching" },
        { id: "close",    label: "Done" }
    ]
    m.idx = 0
end sub

sub open()
    m.top.visible = true
    m.idx = 0
    paint()
    m.rowsG.jumpToItem = 0
    m.rowsG.setFocus(true)
    print "AWFOCUS options"
end sub

sub paint()
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.defs.Count() - 1
        d = m.defs[i]
        t = d.label
        if d.id = "hidewatched"
            ' NOTE: there is deliberately no mature-content toggle here. The
            ' web catalog index this platform reads drops adult items upstream
            ' (Decision 012 is enforced in the pipeline), so a toggle would be
            ' a control that changes nothing — the dead affordance the "Offer
            ' automatic captions" switch was removed for.
            if awGetSetting("hidewatched", false)
                t = t + "   On"
            else
                t = t + "   Off"
            end if
        else if d.id = "autoplay"
            if awGetSetting("autoplay", true)
                t = t + "   On"
            else
                t = t + "   Off"
            end if
        end if
        n = root.CreateChild("ContentNode")
        n.title = t
    end for
    m.rowsG.content = root
end sub

sub onRow()
    m.idx = m.rowsG.itemSelected
    d = m.defs[m.idx]
    if d.id = "close"
        closePanel()
    else if d.id = "clearcw"
        awClearProgress()
        m.rowsG.content.GetChild(m.idx).title = "Continue Watching cleared"
        m.top.changed = "progress"
    else
        if d.id = "hidewatched"
            awSetSetting("hidewatched", not awGetSetting("hidewatched", false))
        else
            awSetSetting("autoplay", not awGetSetting("autoplay", true))
        end if
        paint()
        m.top.changed = d.id
    end if
end sub

sub closePanel()
    m.top.visible = false
    m.top.closed = true
end sub

sub onFocusOn()
    if m.top.focusOn and m.top.visible then m.rowsG.setFocus(true)
end sub

' Up/Down walk the rows; `*` and Back both close, which is what every Roku
' overlay does and therefore what the viewer already expects.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.visible then return false
    if key = "back" or key = "options" or key = "left"
        closePanel()
        return true
    end if
    return false
end function
