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
        railW:    216
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
