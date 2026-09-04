' Layout audit — finds overlapping and off-screen TEXT, by measurement.
'
' Collisions on this platform are invisible in code: a Label's height depends
' on its font, its wrap and its content, so two elements that look 60px apart
' in the source can sit on top of each other for a long title in Spanish. I
' have been fixing these one at a time by eye, which is why they kept coming
' back. This walks the live scene graph and asks each node where it ACTUALLY
' is, using sceneBoundingRect() — the only source of truth for that.
'
' Reported:
'   OVERLAP   two visible Labels whose rects intersect
'   OFFSCREEN a visible Label crossing 1920x1080 or the action-safe inset
'
' Labels are compared to Labels only. Text over a scrim, a plate or a poster is
' deliberate everywhere in this app; text over TEXT never is.

function awCollectLabels(node as Object, out as Object) as Object
    if node = invalid then return out
    if node.HasField("visible")
        if node.visible = false then return out
    end if
    if node.subtype() = "Label"
        t = ""
        if node.HasField("text") then t = node.text
        if t <> ""
            r = node.sceneBoundingRect()
            if r <> invalid and r.width > 0 and r.height > 0
                out.Push({ id: node.id, text: t, r: r })
            end if
        end if
    end if
    for i = 0 to node.GetChildCount() - 1
        awCollectLabels(node.GetChild(i), out)
    end for
    return out
end function

function awRectsOverlap(a as Object, b as Object) as Boolean
    ' A 4px tolerance: fonts carry leading, and two lines whose declared boxes
    ' touch by a pixel or two do not read as overlapping on a television.
    pad = 4
    if a.x + a.width - pad <= b.x then return false
    if b.x + b.width - pad <= a.x then return false
    if a.y + a.height - pad <= b.y then return false
    if b.y + b.height - pad <= a.y then return false
    return true
end function

function awAuditLayout(root as Object, screenName as String) as String
    labels = awCollectLabels(root, [])
    findings = []

    for i = 0 to labels.Count() - 1
        for j = i + 1 to labels.Count() - 1
            if awRectsOverlap(labels[i].r, labels[j].r)
                findings.Push("OVERLAP  '" + Left(labels[i].text, 26) + "' [" + labels[i].id + "] x '" + Left(labels[j].text, 26) + "' [" + labels[j].id + "]")
            end if
        end for
    end for

    for each l in labels
        r = l.r
        if r.x < 0 or r.y < 0 or (r.x + r.width) > 1920 or (r.y + r.height) > 1080
            findings.Push("OFFSCREEN '" + Left(l.text, 26) + "' [" + l.id + "] at " + fmt(Int(r.x)) + "," + fmt(Int(r.y)) + " " + fmt(Int(r.width)) + "x" + fmt(Int(r.height)))
        end if
    end for

    out = "AWLAYOUT " + screenName + ": " + fmt(labels.Count()) + " labels, " + fmt(findings.Count()) + " findings"
    for each f in findings
        out = out + Chr(10) + "   " + f
    end for
    return out
end function

' A compact, machine-readable description of whatever is on screen: the route,
' and every list's name plus how many things it is actually showing.
'
' The point is to assert CONTENT, not just that a screen drew. A surface with
' its heading, its chrome and an empty list looks fine in a screenshot and is
' the exact failure this build has hit repeatedly — Library's empty state
' beside its own "2 in progress" line, Classic TV's zero-row shelves, a Browse
' grid frozen under a changed sort label.
function awReportLists(node as Object, out as Object) as Object
    if node = invalid then return out
    if node.HasField("visible")
        if node.visible = false then return out
    end if
    st = node.subtype()
    if st = "RowList" or st = "MarkupGrid" or st = "LabelList" or st = "MarkupList"
        rows = 0
        items = 0
        c = node.content
        if c <> invalid
            rows = c.GetChildCount()
            if st = "RowList"
                for i = 0 to rows - 1
                    items = items + c.GetChild(i).GetChildCount()
                end for
            else
                items = rows
            end if
        end if
        id = node.id
        if id = "" then id = st
        out.Push(id + "=" + fmt(rows) + "/" + fmt(items))
        ' A row COUNT cannot answer "is Hidden Gems on Home". Name the rows,
        ' so a shelf claimed in the parity table is provable rather than
        ' asserted — three rows were marked "not built" that had been
        ' rendering all along.
        if st = "RowList" and c <> invalid
            names = ""
            for i = 0 to rows - 1
                t = fmt(c.GetChild(i).title)
                if t <> ""
                    if names = "" then names = t else names = names + " | " + t
                end if
            end for
            if names <> "" then out.Push("ROWS[" + names + "]")
        end if
    end if
    for i = 0 to node.GetChildCount() - 1
        awReportLists(node.GetChild(i), out)
    end for
    return out
end function

function awReport(root as Object, route as String) as String
    lists = awReportLists(root, [])
    s = "AWREPORT route=" + route
    for each l in lists
        s = s + " " + l
    end for
    return s
end function
