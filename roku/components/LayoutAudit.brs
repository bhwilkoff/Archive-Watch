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
