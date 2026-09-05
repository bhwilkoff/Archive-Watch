' ROKU-DESIGN.md §5 — the one place colours and type sizes are named.
'
' Two rules from that doc are enforced here rather than remembered:
'   §4.2  every dimension divides by 3 (Roku downscales FHD→HD at exactly 2/3)
'   §5.3b no channel exceeds 235 — pure white fails certification, so the
'         brand's #FF5C35 is rendered as #EB5531 in any FILL on this platform.
' A Font node for a bundled face at an explicit size. Roku loads and caches
' the file once per channel, so creating the node per component is cheap; it
' is the descriptor, not the glyphs.
function AWFont(uri as String, size as Integer) as Object
    f = CreateObject("roSGNode", "Font")
    f.uri = uri
    f.size = size
    return f
end function

' Roku's Label has no tracking. An eyebrow ("FEATURE FILM", "1950S
' TELEVISION") wants letter-spacing to read as a label rather than a shout,
' so the spacing is put INTO the string as hair spaces (U+200A). Only for
' short caps labels — never for prose.
function AWTracked(t as String) as String
    out = ""
    hair = Chr(&h200A)
    for i = 1 to Len(t)
        c = Mid(t, i, 1)
        if out = "" then out = c else out = out + hair + c
    end for
    return out
end function

' 9034 -> "9,034". BrightScript has no grouping format.
function AWGroup(n as Integer) as String
    s = n.ToStr()
    out = ""
    k = 0
    for i = Len(s) to 1 step -1
        out = Mid(s, i, 1) + out
        k = k + 1
        if k mod 3 = 0 and i > 1 then out = "," + out
    end for
    return out
end function

function Theme() as Object
    return {
        canvas:    "0x0B0B0CFF"
        surface:   "0x16161AFF"
        marquee:   "0xEB5531FF"    ' broadcast-safe #FF5C35
        textPri:   "0xEBEBEBFF"    ' NOT 0xF2F2F2 — see §5.3b
        textSec:   "0x9A9AA0FF"
        scrim:     "0x0B0B0CCC"

        ' §5.1 — the six levels, now REAL. Until this tick every level was one
        ' of six named system fonts at whatever size Roku chose, so a hero
        ' title, a row title and a caption were three sizes of the same sans
        ' — the reason the whole channel read as "boxy and rudimentary". The
        ' house display face (Fraunces, the same serif tvOS and the web lead
        ' with) and Inter are bundled as Latin subsets: 516 KB for six faces
        ' against the 4 MB cap. Every size divides by 3 (§4.2).
        uMarquee: AWFont("pkg:/fonts/Fraunces-Display-Black.ttf", 66)
        uScreen:  AWFont("pkg:/fonts/Fraunces-Display-SemiBold.ttf", 45)
        uRow:     AWFont("pkg:/fonts/Inter-SemiBold.ttf", 33)
        uBody:    AWFont("pkg:/fonts/Inter-Regular.ttf", 27)
        uItem:    AWFont("pkg:/fonts/Inter-Medium.ttf", 27)
        uMeta:    AWFont("pkg:/fonts/Inter-Regular.ttf", 24)
        ' Two VOICES on existing levels, not a seventh size: the eyebrow is
        ' Meta in SemiBold, set in caps by the caller; the tagline is Body in
        ' the display family's italic. Same six sizes.
        uEyebrow: AWFont("pkg:/fonts/Inter-SemiBold.ttf", 24)
        uTagline: AWFont("pkg:/fonts/Fraunces-Text-Italic.ttf", 27)
        ' Detail titles sit one step below the hero marquee so a long title
        ' has room for two lines beside the art.
        uTitle:   AWFont("pkg:/fonts/Fraunces-Display-Black.ttf", 57)

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
        ' The DRAWN tile. posterFW/FH below is the CELL, and the cell must stay
        ' LARGER than the drawn tile — the caption is anchored at posterFH,
        ' so a cell smaller than the art puts the title across the poster.
        posterW:  224
        posterH:  336
        ' Two rows of shelf must be reachable under the hero — at 288x432 one
        ' row filled the screen and Home read as a single shelf under a
        ' banner, which is not "a warm introduction to the films". 224x336 is
        ' the size Roku's own rows use for 2:3 art and it still reads at ten
        ' feet.
        posterFW: 248
        posterFH: 360
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
' The category as a viewer reads it. A raw contentType slug ("feature-film",
' "tv-special") was being printed as a LABEL on the hero eyebrow and the
' Detail chip — a hyphen in the middle of a word on screen is the surest
' sign that nobody looked.
function KindLabel(contentType as String) as String
    t = LCase(contentType)
    if t = "feature-film" then return "Feature Film"
    if t = "tv-series" then return "Television"
    if t = "tv-special" then return "Television"
    if t = "tv-episode" then return "Episode"
    if t = "silent-film" then return "Silent Era"
    if t = "animation" then return "Animation"
    if t = "newsreel" then return "Newsreel"
    if t = "documentary" then return "Documentary"
    if t = "ephemeral" then return "Ephemera"
    if t = "short-film" then return "Short Film"
    if t = "commercial" then return "Commercial"
    if t = "home-movie" then return "Home Movie"
    if t = "" then return "Featured"
    return contentType
end function

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
' §13.3 / §13.4 — the FRAME around a piece of art: four rounded-corner
' overlays (always on, canvas-coloured, so a poster reads as a rounded card)
' and a light ring built from corner + edge slices (only on focus). Slices,
' not a .9.png: a nine-patch keeps its guide pixels when a plain Poster
' draws it. Twelve Posters per tile; the RowList only instantiates the
' visible ones, so this is ~40 tiles x 12, not 600 x 12.
function AWFrameBuild(parent as Object) as Object
    f = { corners: [], ring: [] }
    for each n in ["tl", "tr", "bl", "br"]
        p = parent.CreateChild("Poster")
        p.uri = "pkg:/images/slices/corner_" + n + ".png"
        p.width = 12 : p.height = 12
        ' Hidden until placed: an unplaced corner is four 12 px canvas squares
        ' at the component's origin.
        p.visible = false
        f.corners.Push(p)
    end for
    for each n in ["tl", "tr", "bl", "br", "t", "b", "l", "r"]
        p = parent.CreateChild("Poster")
        p.uri = "pkg:/images/slices/ring_" + n + ".png"
        p.visible = false
        f.ring.Push(p)
    end for
    return f
end function

' Places the frame around the DRAWN art (bitmapWidth/Height give the real
' aspect once loaded; the tile itself is 2:3 and the art often is not), so a
' landscape still gets a landscape frame. `lit` draws the ring.
sub AWFramePlace(f as Object, art as Object, lit as Boolean)
    if f = invalid or art = invalid then return
    w = art.width : h = art.height
    ' A Rectangle has no bitmap fields; the frame then fits the node itself.
    ' (`bw > 0` on Invalid is a Type Mismatch that halts the whole component —
    ' the Surprise grid and the rail both went down on it.)
    bw = 0 : bh = 0
    if art.HasField("bitmapWidth")
        if art.bitmapWidth <> invalid then bw = art.bitmapWidth
        if art.bitmapHeight <> invalid then bh = art.bitmapHeight
    end if
    dw = w : dh = h
    if bw > 0 and bh > 0
        sx = w / bw : sy = h / bh
        sc = sx : if sy < sc then sc = sy
        dw = Int(bw * sc) : dh = Int(bh * sc)
    end if
    x = Int((w - dw) / 2) : y = Int((h - dh) / 2)
    ' The frame group sits at the PARENT's origin; the art may not. A tile's
    ' art is at [0,0], but the Detail poster is at [42,318], the rail pill at
    ' [12,0] and the ON NOW chip at [840,18] — their corners were landing at
    ' the parent's top-left, invisible on the canvas, and the art stayed
    ' square. Offset by the art's own translation.
    t = art.translation
    if t <> invalid and t.Count() = 2
        x = x + Int(t[0]) : y = y + Int(t[1])
    end if
    ready = true
    if art.HasField("loadStatus") then ready = (art.loadStatus = "ready")
    ' Corners: on the art's own rectangle, only once there IS art.
    c = f.corners
    c[0].translation = [x, y]
    c[1].translation = [x + dw - 12, y]
    c[2].translation = [x, y + dh - 12]
    c[3].translation = [x + dw - 12, y + dh - 12]
    for each p in c
        p.visible = ready
    end for
    ' Ring: the slices carry a 12 px glow OUTSIDE a 3 px stroke that sits on
    ' the art edge, so the ring rectangle is the art inset by -12 on every
    ' side, with 24 px corners.
    r = f.ring
    g = 12 : k = 24
    rx = x - g : ry = y - g : rw = dw + 2 * g : rh = dh + 2 * g
    r[0].translation = [rx, ry] : r[0].width = k : r[0].height = k
    r[1].translation = [rx + rw - k, ry] : r[1].width = k : r[1].height = k
    r[2].translation = [rx, ry + rh - k] : r[2].width = k : r[2].height = k
    r[3].translation = [rx + rw - k, ry + rh - k] : r[3].width = k : r[3].height = k
    r[4].translation = [rx + k, ry] : r[4].width = rw - 2 * k : r[4].height = k
    r[5].translation = [rx + k, ry + rh - k] : r[5].width = rw - 2 * k : r[5].height = k
    r[6].translation = [rx, ry + k] : r[6].width = k : r[6].height = rh - 2 * k
    r[7].translation = [rx + rw - k, ry + k] : r[7].width = k : r[7].height = rh - 2 * k
    for each p in r
        p.visible = (lit and ready)
    end for
end sub

' §13.5 — a BUTTON is a 60 px pill built from two end caps and a stretched
' middle slice, in one of three finishes: "rest" (11% white), "focus" (solid
' light, dark type) and "marquee" (orange, the one primary action). Built
' once, restyled on focus by swapping the three uris; the label is the
' caller's, centred over it.
function AWPillBuild(parent as Object) as Object
    pill = { l: parent.CreateChild("Poster"), m: parent.CreateChild("Poster"), r: parent.CreateChild("Poster"), w: 0, h: 60 }
    pill.l.width = 30 : pill.l.height = 60
    pill.r.width = 30 : pill.r.height = 60
    pill.m.height = 60
    pill.m.loadDisplayMode = "scaleToFill"
    AWPillStyle(pill, "rest")
    return pill
end function

sub AWPillStyle(pill as Object, finish as String)
    base = "pkg:/images/slices/pill_" + finish
    pill.l.uri = base + "_l.png"
    pill.m.uri = base + "_m.png"
    pill.r.uri = base + "_r.png"
end sub

sub AWPillLayout(pill as Object, x as Integer, y as Integer, w as Integer)
    if w < 60 then w = 60
    pill.w = w
    pill.l.translation = [x, y]
    pill.m.translation = [x + 30, y]
    pill.m.width = w - 60
    pill.r.translation = [x + w - 30, y]
end sub

sub AWPillVisible(pill as Object, v as Boolean)
    pill.l.visible = v : pill.m.visible = v : pill.r.visible = v
end sub

' Retained for callers not yet moved to AWFrame (draws four rectangles).
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
    ' The ring sits just INSIDE the art, overlapping its edge by a few pixels.
    ' Drawn outside it, a tile whose art fills its cell put the ring beyond the
    ' cell bounds and the list clipped the top and the left edges off — which is
    ' exactly what "the selection rectangle is cut off" looks like.
    th = 4
    x = Int((w - dw) / 2)
    y = Int((h - dh) / 2)
    rw = dw
    rh = dh
    ring[0].translation = [x, y] : ring[0].width = rw : ring[0].height = th
    ring[1].translation = [x, y + rh - th] : ring[1].width = rw : ring[1].height = th
    ring[2].translation = [x, y] : ring[2].width = th : ring[2].height = rh
    ring[3].translation = [x + rw - th, y] : ring[3].width = th : ring[3].height = rh
    for each r in ring
        r.visible = true
    end for
end sub

' The audience star on a meta line. One glyph, from the font, never an image.
function AWStar() as String
    return Chr(9733)
end function
