' ROKU-DESIGN.md §5 — the one place colours and type sizes are named.
'
' Two rules from that doc are enforced here rather than remembered:
'   §4.2  every dimension divides by 3 (Roku downscales FHD→HD at exactly 2/3)
'   §5.3b no channel exceeds 235 — pure white fails certification, so the
'         brand's #FF5C35 is rendered as #EB5531 in any FILL on this platform.
function Theme() as Object
    return {
        canvas:    "0x0B0B0CFF"
        surface:   "0x16161AFF"
        marquee:   "0xEB5531FF"    ' broadcast-safe #FF5C35
        textPri:   "0xEBEBEBFF"    ' NOT 0xF2F2F2 — see §5.3b
        textSec:   "0x9A9AA0FF"
        scrim:     "0x0B0B0CCC"

        ' §5.1 — the six levels, expressed as Roku's named system fonts.
        ' The px column of ROKU-DESIGN §5.1 is the INTENT; Roku does not publish
        ' the system sizes and a Font node cannot carry an arbitrary size for a
        ' system face, so the exact scale waits on a bundled TTF. Using the
        ' system family is also what §5.2 prescribes: most native, zero bytes
        ' against the 4 MB package cap.
        uMarquee: "font:LargeBoldSystemFont"
        uScreen:  "font:LargeBoldSystemFont"
        uRow:     "font:MediumBoldSystemFont"
        uBody:    "font:MediumSystemFont"
        uItem:    "font:MediumSystemFont"
        uMeta:    "font:SmallSystemFont"

        ' §5.1 — six levels, all divisible by 3. A seventh is refused.
        fMarquee: 66
        fScreen:  45
        fRow:     33
        fBody:    27
        fItem:    27
        fMeta:    24

        ' §4.3 / §4.4
        safeX:    96
        safeY:    54
        readX:    192
        overhang: 115
        contentY: 169
        colW:     1728

        ' §4.6 — resting and focused sizes are STATED, never a scale factor.
        posterW:  264
        posterH:  396
        posterFW: 288
        posterFH: 432
        gutter:   24
        ' The rail is COLLAPSED by default and content is laid out against this
        ' width. It expands OVER the content when focused, so nothing moves —
        ' a rail that pushed 26,000 posters sideways on every focus change
        ' would be the most expensive animation in the app.
        railW:    84
        railExpandedW: 288
    }
end function

' Per-category semantic accent (CLAUDE.md). CONTENT MEANING ONLY — never a
' focus ring, never a button (ROKU-DESIGN §5.3).
function AccentFor(contentType as String) as String
    if contentType = "tv-series" or contentType = "tv-special" or contentType = "tv-episode" then return "0x2D5BFFFF"
    if contentType = "silent-film" then return "0xC9A66BFF"
    if contentType = "animation" then return "0xFF4D8DFF"
    if contentType = "newsreel" then return "0x8A8F98FF"
    if contentType = "documentary" then return "0x3FA796FF"
    if contentType = "ephemeral" then return "0x7C5BBAFF"
    if contentType = "short-film" then return "0xE8A317FF"
    return "0xEB5531FF"
end function

' BrightScript has no universal to-string: Str() takes a FLOAT, so Str(aString)
' is a runtime Type Mismatch that halts the channel. Everything printable goes
' through here.
function fmt(v as Dynamic) as String
    if v = invalid then return ""
    t = type(v)
    if t = "String" or t = "roString" then return v
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" then return v.ToStr()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Str(v).Trim()
    if t = "Boolean" or t = "roBoolean"
        if v then return "true"
        return "false"
    end if
    return ""
end function


' Roku's broadcast-safe rule (ROKU-DESIGN §4.5): no channel above 235, because
' a TV set to a video-range signal clips anything brighter and a "pure" colour
' blooms. The shared editorial palette is authored for phones and the web, so
' its accents arrive above the ceiling (#FF5C35 has a 255 red) and have to be
' clamped before they reach the screen.
function BroadcastSafe(hex as String) as String
    h = hex
    if Left(h, 1) = "#" then h = Mid(h, 2)
    if Len(h) < 6 then return "0xEBEBEBFF"
    out = "0x"
    for i = 0 to 2
        v = Val("&H" + Mid(h, i * 2 + 1, 2))
        if v > 235 then v = 235
        d = Int(v)
        digits = "0123456789ABCDEF"
        hi = Int(d / 16) : lo = d - hi * 16
        out = out + Mid(digits, hi + 1, 1) + Mid(digits, lo + 1, 1)
    end for
    return out + "FF"
end function


' Archive and TVDb descriptions arrive with HTML in them — "<div>", "<br />",
' "&amp;" — and a Label renders those characters literally. Seen on the glass
' as: "Family Feud S17 E47<div>Aired July 16, 2022". Every string that reaches
' a Label from the network goes through here.
function StripHTML(src as String) as String
    if src = "" then return src
    out = ""
    depth = 0
    for i = 0 to Len(src) - 1
        c = Mid(src, i + 1, 1)
        if c = "<"
            depth = depth + 1
        else if c = ">"
            if depth > 0 then depth = depth - 1
            ' A closed tag becomes a SPACE, not nothing: "one<br/>two" must not
            ' read as "onetwo".
            if depth = 0 then out = out + " "
        else if depth = 0
            out = out + c
        end if
    end for
    out = DecodeEntities(out)
    ' Collapse the runs of whitespace the stripping just created.
    clean = ""
    prevSpace = false
    for i = 0 to Len(out) - 1
        c = Mid(out, i + 1, 1)
        isSpace = (c = " " or c = Chr(9) or c = Chr(10) or c = Chr(13))
        if isSpace
            if not prevSpace then clean = clean + " "
            prevSpace = true
        else
            clean = clean + c
            prevSpace = false
        end if
    end for
    ' Trim
    while Len(clean) > 0 and Left(clean, 1) = " "
        clean = Mid(clean, 2)
    end while
    while Len(clean) > 0 and Right(clean, 1) = " "
        clean = Left(clean, Len(clean) - 1)
    end while
    return clean
end function

function DecodeEntities(src as String) as String
    out = src
    pairs = [["&amp;", "&"], ["&lt;", "<"], ["&gt;", ">"], ["&quot;", Chr(34)],
             ["&#39;", "'"], ["&apos;", "'"], ["&nbsp;", " "], ["&mdash;", "—"],
             ["&ndash;", "–"], ["&hellip;", "…"], ["&rsquo;", "'"], ["&lsquo;", "'"],
             ["&ldquo;", Chr(34)], ["&rdquo;", Chr(34)]]
    for each p in pairs
        parts = []
        rest = out
        idx = Instr(1, rest, p[0])
        while idx > 0
            parts.Push(Left(rest, idx - 1))
            rest = Mid(rest, idx + Len(p[0]))
            idx = Instr(1, rest, p[0])
        end while
        if parts.Count() > 0
            joined = ""
            for each x in parts
                joined = joined + x + p[1]
            end for
            out = joined + rest
        end if
    end for
    return out
end function

' Sizes a four-rectangle selection ring to the ART's rendered bounds.
'
' Shared because three tile shapes need it and the reasoning is identical: a
' cell has a fixed aspect, the artwork does not, and a ring drawn at cell size
' encloses empty margins whenever the two disagree (ROKU-DESIGN §5.4a).
' `art` is the Poster; `ring` is [top, bottom, left, right].
sub AWRing(art as Object, ring as Object, focused as Boolean)
    if ring = invalid or art = invalid then return
    if not focused
        for each r in ring
            r.visible = false
        end for
        return
    end if
    w = art.width
    h = art.height
    bw = art.bitmapWidth
    bh = art.bitmapHeight
    dw = w
    dh = h
    if bw > 0 and bh > 0
        sx = w / bw
        sy = h / bh
        sc = sx
        if sy < sc then sc = sy
        dw = Int(bw * sc)
        dh = Int(bh * sc)
    end if
    pad = 5
    th = 4
    x = Int((w - dw) / 2) - pad
    y = Int((h - dh) / 2) - pad
    rw = dw + pad * 2
    rh = dh + pad * 2
    ring[0].translation = [x, y] : ring[0].width = rw : ring[0].height = th
    ring[1].translation = [x, y + rh - th] : ring[1].width = rw : ring[1].height = th
    ring[2].translation = [x, y] : ring[2].width = th : ring[2].height = rh
    ring[3].translation = [x + rw - th, y] : ring[3].width = th : ring[3].height = rh
    for each r in ring
        r.visible = true
    end for
end sub
