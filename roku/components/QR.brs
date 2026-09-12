' A QR encoder in BrightScript, because Roku has no QR API and the one share
' affordance on every other platform is a code the viewer points a phone at
' (F5 — the owner: "did the QR code work not meet Roku's needs?"). Byte mode,
' error-correction level L, versions 1–10 (up to 271 bytes — a share URL is
' ~45–110). Rendered as an 8-bit greyscale PNG written to tmp:/ with STORED
' deflate blocks (no compressor needed), so a Poster draws it crisp.
'
' BrightScript has no XOR; (a OR b) - (a AND b) is exact for non-negatives and
' is used throughout this project. Integers are 32-bit signed; nothing here
' exceeds 2^24 except the CRC, which roByteArray computes itself.

' Integer power of two; `2 ^ i` is a Float in BrightScript.
function pow2(i as Integer) as Integer
    v = 1
    for k = 1 to i
        v = v * 2
    end for
    return v
end function

function qrXor(a as Integer, b as Integer) as Integer
    return (a or b) - (a and b)
end function

' GF(256) with the QR primitive 0x11D.
function qrGF() as Object
    if m.qrGFTables <> invalid then return m.qrGFTables
    exp_ = CreateObject("roArray", 512, false)
    log_ = CreateObject("roArray", 256, false)
    x = 1
    for i = 0 to 254
        exp_[i] = x
        log_[x] = i
        x = x * 2
        if x >= 256 then x = qrXor(x, 285)
    end for
    for i = 255 to 511
        exp_[i] = exp_[i - 255]
    end for
    log_[0] = 0
    m.qrGFTables = { e: exp_, l: log_ }
    return m.qrGFTables
end function

function qrMul(a as Integer, b as Integer) as Integer
    if a = 0 or b = 0 then return 0
    t = qrGF()
    return t.e[t.l[a] + t.l[b]]
end function

' Generator polynomial coefficients for n EC codewords (highest degree first).
function qrGenerator(n as Integer) as Object
    gen = [1]
    t = qrGF()
    for i = 0 to n - 1
        nxt = CreateObject("roArray", gen.Count() + 1, false)
        for k = 0 to gen.Count()
            nxt[k] = 0
        end for
        for k = 0 to gen.Count() - 1
            nxt[k] = qrXor(nxt[k], gen[k])
            nxt[k + 1] = qrXor(nxt[k + 1], qrMul(gen[k], t.e[i]))
        end for
        gen = nxt
    end for
    return gen
end function

function qrECC(data as Object, n as Integer) as Object
    gen = qrGenerator(n)
    res = CreateObject("roArray", n, false)
    for i = 0 to n - 1
        res[i] = 0
    end for
    for each d in data
        f = qrXor(d, res[0])
        for i = 0 to n - 2
            res[i] = res[i + 1]
        end for
        res[n - 1] = 0
        if f <> 0
            for i = 0 to n - 1
                res[i] = qrXor(res[i], qrMul(gen[i + 1], f))
            end for
        end if
    end for
    return res
end function

' Version table, EC level L: [dataCodewords, eccPerBlock, blocks1, len1, blocks2, len2]
' MACHINE-GENERATED from an independent reference and asserted against the JS
' twin by tools/test_qr_tables_match.mjs — hand-transcribing this is what put
' [6, 28, 52] in the alignment table below and malformed every v10 code.
' Cached on m: rebuilding a 40-row array per call is wasted work on a Roku 2 XD.
function qrVersionTable() as Object
    if m.qrVerTbl <> invalid then return m.qrVerTbl
    t = CreateObject("roArray", 40, false)
    t.Push([19, 7, 1, 19, 0, 0])   ' v1
    t.Push([34, 10, 1, 34, 0, 0])   ' v2
    t.Push([55, 15, 1, 55, 0, 0])   ' v3
    t.Push([80, 20, 1, 80, 0, 0])   ' v4
    t.Push([108, 26, 1, 108, 0, 0])   ' v5
    t.Push([136, 18, 2, 68, 0, 0])   ' v6
    t.Push([156, 20, 2, 78, 0, 0])   ' v7
    t.Push([194, 24, 2, 97, 0, 0])   ' v8
    t.Push([232, 30, 2, 116, 0, 0])   ' v9
    t.Push([274, 18, 2, 68, 2, 69])   ' v10
    t.Push([324, 20, 4, 81, 0, 0])   ' v11
    t.Push([370, 24, 2, 92, 2, 93])   ' v12
    t.Push([428, 26, 4, 107, 0, 0])   ' v13
    t.Push([461, 30, 3, 115, 1, 116])   ' v14
    t.Push([523, 22, 5, 87, 1, 88])   ' v15
    t.Push([589, 24, 5, 98, 1, 99])   ' v16
    t.Push([647, 28, 1, 107, 5, 108])   ' v17
    t.Push([721, 30, 5, 120, 1, 121])   ' v18
    t.Push([795, 28, 3, 113, 4, 114])   ' v19
    t.Push([861, 28, 3, 107, 5, 108])   ' v20
    t.Push([932, 28, 4, 116, 4, 117])   ' v21
    t.Push([1006, 28, 2, 111, 7, 112])   ' v22
    t.Push([1094, 30, 4, 121, 5, 122])   ' v23
    t.Push([1174, 30, 6, 117, 4, 118])   ' v24
    t.Push([1276, 26, 8, 106, 4, 107])   ' v25
    t.Push([1370, 28, 10, 114, 2, 115])   ' v26
    t.Push([1468, 30, 8, 122, 4, 123])   ' v27
    t.Push([1531, 30, 3, 117, 10, 118])   ' v28
    t.Push([1631, 30, 7, 116, 7, 117])   ' v29
    t.Push([1735, 30, 5, 115, 10, 116])   ' v30
    t.Push([1843, 30, 13, 115, 3, 116])   ' v31
    t.Push([1955, 30, 17, 115, 0, 0])   ' v32
    t.Push([2071, 30, 17, 115, 1, 116])   ' v33
    t.Push([2191, 30, 13, 115, 6, 116])   ' v34
    t.Push([2306, 30, 12, 121, 7, 122])   ' v35
    t.Push([2434, 30, 6, 121, 14, 122])   ' v36
    t.Push([2566, 30, 17, 122, 4, 123])   ' v37
    t.Push([2702, 30, 4, 122, 18, 123])   ' v38
    t.Push([2812, 30, 20, 117, 4, 118])   ' v39
    t.Push([2956, 30, 19, 118, 6, 119])   ' v40
    m.qrVerTbl = t
    return t
end function

function qrAlignPositions(v as Integer) as Object
    if m.qrAlignTbl = invalid
        a = CreateObject("roArray", 40, false)
        a.Push([])   ' v1
        a.Push([6, 18])   ' v2
        a.Push([6, 22])   ' v3
        a.Push([6, 26])   ' v4
        a.Push([6, 30])   ' v5
        a.Push([6, 34])   ' v6
        a.Push([6, 22, 38])   ' v7
        a.Push([6, 24, 42])   ' v8
        a.Push([6, 26, 46])   ' v9
        a.Push([6, 28, 50])   ' v10
        a.Push([6, 30, 54])   ' v11
        a.Push([6, 32, 58])   ' v12
        a.Push([6, 34, 62])   ' v13
        a.Push([6, 26, 46, 66])   ' v14
        a.Push([6, 26, 48, 70])   ' v15
        a.Push([6, 26, 50, 74])   ' v16
        a.Push([6, 30, 54, 78])   ' v17
        a.Push([6, 30, 56, 82])   ' v18
        a.Push([6, 30, 58, 86])   ' v19
        a.Push([6, 34, 62, 90])   ' v20
        a.Push([6, 28, 50, 72, 94])   ' v21
        a.Push([6, 26, 50, 74, 98])   ' v22
        a.Push([6, 30, 54, 78, 102])   ' v23
        a.Push([6, 28, 54, 80, 106])   ' v24
        a.Push([6, 32, 58, 84, 110])   ' v25
        a.Push([6, 30, 58, 86, 114])   ' v26
        a.Push([6, 34, 62, 90, 118])   ' v27
        a.Push([6, 26, 50, 74, 98, 122])   ' v28
        a.Push([6, 30, 54, 78, 102, 126])   ' v29
        a.Push([6, 26, 52, 78, 104, 130])   ' v30
        a.Push([6, 30, 56, 82, 108, 134])   ' v31
        a.Push([6, 34, 60, 86, 112, 138])   ' v32
        a.Push([6, 30, 58, 86, 114, 142])   ' v33
        a.Push([6, 34, 62, 90, 118, 146])   ' v34
        a.Push([6, 30, 54, 78, 102, 126, 150])   ' v35
        a.Push([6, 24, 50, 76, 102, 128, 154])   ' v36
        a.Push([6, 28, 54, 80, 106, 132, 158])   ' v37
        a.Push([6, 32, 58, 84, 110, 136, 162])   ' v38
        a.Push([6, 26, 54, 82, 110, 138, 166])   ' v39
        a.Push([6, 30, 58, 86, 114, 142, 170])   ' v40
        m.qrAlignTbl = a
    end if
    return m.qrAlignTbl[v - 1]
end function

' Builds the module matrix for `text`; returns { size, modules (array of rows of 0/1) } or invalid.
function qrMatrix(text as String) as Object
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(text)
    n = ba.Count()
    tbl = qrVersionTable()
    v = 0
    for i = 0 to tbl.Count() - 1
        cc = 8
        if i + 1 >= 10 then cc = 16
        ' mode(4) + count(cc) + 8n bits must fit in dataCodewords*8
        if 4 + cc + 8 * n <= tbl[i][0] * 8
            v = i + 1
            exit for
        end if
    end for
    if v = 0 then return invalid
    spec = tbl[v - 1]
    size = 17 + 4 * v

    ' ---- bit stream ----
    bits = []
    ccBits = 8
    if v >= 10 then ccBits = 16
    pushBits(bits, 4, 4)
    pushBits(bits, n, ccBits)
    for i = 0 to n - 1
        pushBits(bits, ba[i], 8)
    end for
    cap = spec[0] * 8
    term = cap - bits.Count()
    if term > 4 then term = 4
    pushBits(bits, 0, term)
    while bits.Count() mod 8 <> 0
        bits.Push(0)
    end while
    pad = 236
    while bits.Count() < cap
        pushBits(bits, pad, 8)
        if pad = 236 then pad = 17 else pad = 236
    end while
    cw = []
    for i = 0 to bits.Count() - 1 step 8
        b = 0
        for k = 0 to 7
            b = b * 2 + bits[i + k]
        end for
        cw.Push(b)
    end for

    ' ---- blocks + interleave ----
    blocks = []
    p = 0
    for b = 1 to spec[2]
        blk = []
        for k = 0 to spec[3] - 1
            blk.Push(cw[p]) : p = p + 1
        end for
        blocks.Push(blk)
    end for
    for b = 1 to spec[4]
        blk = []
        for k = 0 to spec[5] - 1
            blk.Push(cw[p]) : p = p + 1
        end for
        blocks.Push(blk)
    end for
    eccs = []
    for each blk in blocks
        eccs.Push(qrECC(blk, spec[1]))
    end for
    out = []
    maxLen = spec[3]
    if spec[5] > maxLen then maxLen = spec[5]
    for k = 0 to maxLen - 1
        for each blk in blocks
            if k < blk.Count() then out.Push(blk[k])
        end for
    end for
    for k = 0 to spec[1] - 1
        for each e in eccs
            out.Push(e[k])
        end for
    end for
    stream = []
    for each c in out
        pushBits(stream, c, 8)
    end for

    ' ---- matrix + function patterns ----
    mods = CreateObject("roArray", size, false)
    fn = CreateObject("roArray", size, false)
    for y = 0 to size - 1
        row = CreateObject("roArray", size, false)
        frow = CreateObject("roArray", size, false)
        for x = 0 to size - 1
            row[x] = 0 : frow[x] = 0
        end for
        mods[y] = row : fn[y] = frow
    end for
    qrFinder(mods, fn, 0, 0, size)
    qrFinder(mods, fn, size - 7, 0, size)
    qrFinder(mods, fn, 0, size - 7, size)
    ' timing
    for i = 8 to size - 9
        v2 = 1 - (i mod 2)
        mods[6][i] = v2 : fn[6][i] = 1
        mods[i][6] = v2 : fn[i][6] = 1
    end for
    ' alignment
    ' Indexed, NOT `for each`: a nested for-each over the SAME roArray shares
    ' one enumerator, so the inner loop exhausted the outer and the alignment
    ' pattern was never drawn — 25 data bits landed where it belongs, and no
    ' phone could read the code. Measured: the device placed 592 bits where
    ' the reference places 567; 25 is a 5x5 alignment pattern.
    ap = qrAlignPositions(v)
    for ai = 0 to ap.Count() - 1
        ay = ap[ai]
        for aj = 0 to ap.Count() - 1
            ax = ap[aj]
            if not ((ax <= 8 and ay <= 8) or (ax <= 8 and ay >= size - 9) or (ax >= size - 9 and ay <= 8))
                for dy = -2 to 2
                    for dx = -2 to 2
                        d = dx : if dy < 0 and -dy > d then d = -dy
                        if dx < 0 and -dx > d then d = -dx
                        if dy > d then d = dy
                        val = 1
                        if d = 1 then val = 0
                        mods[ay + dy][ax + dx] = val
                        fn[ay + dy][ax + dx] = 1
                    end for
                end for
            end if
        end for
    end for
    ' format info areas reserved (filled later); dark module
    ' Reserved for format info: nine cells beside the top-left finder on
    ' each axis, EIGHT at the far ends (the ninth there was the bug that
    ' shifted every data bit after it), plus the dark module.
    for i = 0 to 8
        fn[8][i] = 1 : fn[i][8] = 1
    end for
    for i = 0 to 7
        fn[8][size - 1 - i] = 1 : fn[size - 1 - i][8] = 1
    end for
    mods[size - 8][8] = 1 : fn[size - 8][8] = 1
    ' version info (v >= 7)
    if v >= 7
        ' BCH(18,6), generator 0x1F25 = 7973. COMPUTED, not tabulated: the old
        ' ten-entry table could not reach past v10, and a 34-row extension of
        ' it would be 34 more chances to mistype a constant.
        remv = v * 4096                      ' v << 12
        for i = 17 to 12 step -1
            if Int(remv / pow2(i)) mod 2 = 1
                remv = qrXor(remv, 7973 * pow2(i - 12))
            end if
        end for
        vb = v * 4096 + (remv mod 4096)
        for i = 0 to 17
            bit = Int(vb / pow2(i)) mod 2
            a = Int(i / 3) : b = i mod 3
            mods[a][size - 11 + b] = bit : fn[a][size - 11 + b] = 1
            mods[size - 11 + b][a] = bit : fn[size - 11 + b][a] = 1
        end for
    end if

    ' ---- place data ----
    idx = 0
    x = size - 1
    up = true
    while x > 0
        if x = 6 then x = x - 1
        for k = 0 to size - 1
            y = k
            if up then y = size - 1 - k
            for c = 0 to 1
                xx = x - c
                if fn[y][xx] = 0
                    bit = 0
                    if idx < stream.Count() then bit = stream[idx]
                    mods[y][xx] = bit
                    idx = idx + 1
                end if
            end for
        end for
        up = not up
        x = x - 2
    end while

    ' ---- mask: choose by penalty ----
    best = -1
    bestScore = 999999999
    bestMods = invalid
    for mask = 0 to 7
        cand = qrApplyMask(mods, fn, size, mask)
        qrWriteFormat(cand, size, mask)
        sc = qrPenalty(cand, size)
        if sc < bestScore
            bestScore = sc : best = mask : bestMods = cand
        end if
    end for
    return { size: size, modules: bestMods, version: v, mask: best }
end function

sub pushBits(bits as Object, val as Integer, n as Integer)
    for i = n - 1 to 0 step -1
        bits.Push(Int(val / pow2(i)) mod 2)
    end for
end sub

sub qrFinder(mods as Object, fn as Object, ox as Integer, oy as Integer, size as Integer)
    for dy = -1 to 7
        for dx = -1 to 7
            x = ox + dx : y = oy + dy
            if x >= 0 and y >= 0 and x < size and y < size
                val = 0
                if dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6
                    if dx = 0 or dx = 6 or dy = 0 or dy = 6 then val = 1
                    if dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4 then val = 1
                end if
                mods[y][x] = val
                fn[y][x] = 1
            end if
        end for
    end for
end sub

function qrMaskBit(mask as Integer, y as Integer, x as Integer) as Boolean
    if mask = 0 then return ((y + x) mod 2 = 0)
    if mask = 1 then return (y mod 2 = 0)
    if mask = 2 then return (x mod 3 = 0)
    if mask = 3 then return ((y + x) mod 3 = 0)
    if mask = 4 then return ((Int(y / 2) + Int(x / 3)) mod 2 = 0)
    if mask = 5 then return (((y * x) mod 2 + (y * x) mod 3) = 0)
    if mask = 6 then return ((((y * x) mod 2) + ((y * x) mod 3)) mod 2 = 0)
    return ((((y + x) mod 2) + ((y * x) mod 3)) mod 2 = 0)
end function

function qrApplyMask(mods as Object, fn as Object, size as Integer, mask as Integer) as Object
    out = CreateObject("roArray", size, false)
    for y = 0 to size - 1
        row = CreateObject("roArray", size, false)
        for x = 0 to size - 1
            v = mods[y][x]
            if fn[y][x] = 0 and qrMaskBit(mask, y, x) then v = 1 - v
            row[x] = v
        end for
        out[y] = row
    end for
    return out
end function

' Format info for EC level L (01) and the mask, BCH(15,5), XOR 0x5412.
sub qrWriteFormat(mods as Object, size as Integer, mask as Integer)
    data = 8 + mask         ' 01 << 3 | mask  (L = 01)
    remv = data * 1024       ' data << 10 (`rem` is the COMMENT keyword)
    for i = 14 to 10 step -1
        if Int(remv / pow2(i)) mod 2 = 1
            remv = qrXor(remv, 1335 * pow2(i - 10))   ' 0x537 shifted
        end if
    end for
    fmtBits = qrXor(data * 1024 + remv, 21522)          ' ^ 0x5412
    ' Bit i (LSB first) goes down column 8 beside the top-left finder and
    ' along row 8 from the right edge — the two copies the spec places. The
    ' first draft had the axes swapped, which a reference diff of the whole
    ' matrix found in one look (254 cells wrong, every one downstream).
    for i = 0 to 14
        bit = Int(fmtBits / pow2(i)) mod 2
        ' vertical copy, column 8
        if i < 6
            mods[i][8] = bit
        else if i < 8
            mods[i + 1][8] = bit
        else
            mods[size - 15 + i][8] = bit
        end if
        ' horizontal copy, row 8
        if i < 8
            mods[8][size - 1 - i] = bit
        else if i < 9
            mods[8][7] = bit
        else
            mods[8][14 - i] = bit
        end if
    end for
end sub

' Penalty rules 1, 2 and 4 (3 — the finder-like runs — is skipped; the other
' three decide readability at the sizes a share URL produces).
function qrPenalty(mods as Object, size as Integer) as Integer
    score = 0
    for y = 0 to size - 1
        runC = 1 : runV = mods[y][0]
        colRunC = 1 : colRunV = mods[0][y]
        for x = 1 to size - 1
            if mods[y][x] = runV
                runC = runC + 1
                if runC = 5 then score = score + 3
                if runC > 5 then score = score + 1
            else
                runV = mods[y][x] : runC = 1
            end if
            if mods[x][y] = colRunV
                colRunC = colRunC + 1
                if colRunC = 5 then score = score + 3
                if colRunC > 5 then score = score + 1
            else
                colRunV = mods[x][y] : colRunC = 1
            end if
        end for
    end for
    dark = 0
    for y = 0 to size - 2
        for x = 0 to size - 2
            a = mods[y][x]
            if a = mods[y][x + 1] and a = mods[y + 1][x] and a = mods[y + 1][x + 1] then score = score + 3
        end for
    end for
    for y = 0 to size - 1
        for x = 0 to size - 1
            dark = dark + mods[y][x]
        end for
    end for
    pct = Int(dark * 100 / (size * size))
    k = Int(Abs(pct - 50) / 5)
    score = score + k * 10
    return score
end function

' ---- PNG writer ------------------------------------------------------------

sub pngU32(ba as Object, v as Integer)
    ' Big-endian, from a possibly NEGATIVE 32-bit value (the CRC).
    hi = (v and &h7F000000) / 16777216
    if v < 0 then hi = hi + 128
    ba.Push(hi)
    ba.Push((v and &hFF0000) / 65536)
    ba.Push((v and &hFF00) / 256)
    ba.Push(v and 255)
end sub

sub pngChunk(png as Object, typ as String, payload as Object)
    pngU32(png, payload.Count())
    chunk = CreateObject("roByteArray")
    chunk.FromAsciiString(typ)
    chunk.Append(payload)
    png.Append(chunk)
    pngU32(png, chunk.GetCRC32())
end sub

' Writes `text` as a QR PNG at `scale` px per module with a 4-module quiet
' zone; returns the tmp:/ path, or "" if the text does not fit.
' The pixel box the share card gives a code. Generating larger and letting the
' Poster scale it down is wasted work; generating smaller and letting the
' Poster scale it UP blurs the module edges, which is the one thing a scanner
' cannot forgive.
function AWQRBox() as Integer : return 520 : end function

function AWQRPng(text as String, scale as Integer) as String
    ' The COST, not just the shape. Mask selection scores all eight candidates
    ' over the whole matrix, so the work grows with the square of the version —
    ' and the oldest player this channel supports is a Roku 2 XD. A share card
    ' that takes seconds to draw is a defect, and the trace is where that shows.
    t0 = CreateObject("roTimespan")
    q = qrMatrix(text)
    if q = invalid then return ""
    encodeMs = t0.TotalMilliseconds()
    size = q.size
    quiet = 4
    mods = size + 2 * quiet

    ' SCALE IS DERIVED, not passed, when the caller asks for a box (scale <= 0).
    ' Generating 648 px to display 392 was pure waste, and the waste grows with
    ' the square: every byte is touched three times by BrightScript loops below.
    ' Deriving it also makes the cost FALL as the version rises — a bigger code
    ' packs more modules into the same box at a smaller scale — which is what
    ' keeps a fifty-film playlist drawable on an old player.
    if scale <= 0
        scale = Int(AWQRBox() / mods)
        if scale < 2 then scale = 2
    end if
    px = mods * scale

    ' Raw scanlines: filter byte 0 + px greyscale bytes.
    '
    ' ONE scanline per MODULE row, repeated `scale` times. The pixel rows inside
    ' a module row are identical, so building each of them separately did the
    ' same work `scale` times over — at scale 8 that is eight times the loop for
    ' a byte-identical result.
    raw = CreateObject("roByteArray")
    rowLen = px + 1
    raw.SetResize(rowLen * px, false)
    for mrow = 0 to mods - 1
        my = mrow - quiet
        line = CreateObject("roByteArray")
        line.SetResize(rowLen, false)
        line.Push(0)
        for x = 0 to px - 1
            mx = Int(x / scale) - quiet
            v = 255
            if my >= 0 and my < size and mx >= 0 and mx < size
                if q.modules[my][mx] = 1 then v = 11
            end if
            line.Push(v)
        end for
        for r = 1 to scale
            raw.Append(line)
        end for
    end for
    ' zlib stream of STORED blocks.
    z = CreateObject("roByteArray")
    z.Push(120) : z.Push(1)
    total = raw.Count()
    p = 0
    while p < total
        n = total - p
        if n > 65535 then n = 65535
        final = 0
        if p + n >= total then final = 1
        z.Push(final)
        z.Push(n and 255) : z.Push((n and &hFF00) / 256)
        nn = 65535 - n
        z.Push(nn and 255) : z.Push((nn and &hFF00) / 256)
        for i = p to p + n - 1
            z.Push(raw[i])
        end for
        p = p + n
    end while
    ' Adler-32 over the raw bytes.
    a = 1 : b = 0
    for i = 0 to total - 1
        a = (a + raw[i]) mod 65521
        b = (b + a) mod 65521
    end for
    z.Push((b and &hFF00) / 256) : z.Push(b and 255)
    z.Push((a and &hFF00) / 256) : z.Push(a and 255)

    png = CreateObject("roByteArray")
    for each c in [137, 80, 78, 71, 13, 10, 26, 10]
        png.Push(c)
    end for
    ihdr = CreateObject("roByteArray")
    pngU32(ihdr, px) : pngU32(ihdr, px)
    ihdr.Push(8) : ihdr.Push(0) : ihdr.Push(0) : ihdr.Push(0) : ihdr.Push(0)
    pngChunk(png, "IHDR", ihdr)
    pngChunk(png, "IDAT", z)
    pngChunk(png, "IEND", CreateObject("roByteArray"))
    path = "tmp:/qr_" + fmt(Len(text)) + "_" + fmt(size) + "_" + fmt(q.mask) + ".png"
    png.WriteFile(path)
    print "AWQR v"; q.version; " size="; size; " mask="; q.mask; " px="; px; " bytes="; png.Count(); " encodeMs="; encodeMs; " totalMs="; t0.TotalMilliseconds(); " -> "; path
    ' Proven 2026-09-05: the matrix, dumped from this console, matched the
    ' python `qrcode` reference cell for cell (v3, mask 2, 0 differences) and
    ' OpenCV decoded a screenshot of the card to the exact URL.
    return path
end function
