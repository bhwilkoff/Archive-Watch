import Foundation

/// Rewrites a plain (non-fragmented) MP4 into a FRAGMENTED one, without
/// re-encoding a single sample.
///
/// WHY THIS EXISTS. Measured on the owner's Apple TV (tvOS 27.0, 24J5360a):
/// a non-fragmented MP4 loses its AUDIO after ~3-5 minutes while video plays
/// on -- with a healthy buffer, an empty error log, the audio track still
/// enabled and 2 channels still on the route. A FRAGMENTED mp4 of the same
/// footage, same codecs, same server, ran 9+ minutes untouched, and HLS ran a
/// whole feature. The container is the trigger.
///
/// Every cheaper remedy was tried on the glass and rejected: muting does not
/// revive the render, nor does re-selecting the audio track; only a genuine
/// stop does, and even a single-runloop-turn stop is audible -- "a movie that
/// pauses temporarily every 2 minutes is unwatchable". So the fix has to be
/// in what we hand the player.
///
/// WHAT IT PRODUCES. An init segment (ftyp + moov whose sample tables are
/// empty, plus mvex/trex) followed by fragments (moof + mdat). The media
/// bytes are copied verbatim from the source mdat, so quality, codecs and
/// duration are untouched.
///
/// The output LAYOUT is computed up front, before any media is read, because
/// the resource loader must answer arbitrary byte-range requests and report an
/// exact content length. `plan()` builds that map; `data(for:)` realises only
/// the bytes a request actually needs.
struct MP4Fragmenter {

    // MARK: - Box scanning

    struct Box {
        let type: String
        let range: Range<Int>       // whole box, including header
        let payload: Range<Int>
    }

    static func boxes(in d: Data, range: Range<Int>) -> [Box] {
        var out: [Box] = []
        var i = range.lowerBound
        while i + 8 <= range.upperBound {
            let size32 = Int(be32(d, i))
            let type = String(bytes: d[(i + 4)..<(i + 8)], encoding: .isoLatin1) ?? "????"
            var size = size32
            var header = 8
            if size32 == 1 {                       // 64-bit largesize
                guard i + 16 <= range.upperBound else { break }
                size = Int(be64(d, i + 8))
                header = 16
            } else if size32 == 0 {                // extends to end
                size = range.upperBound - i
            }
            guard size >= header, i + size <= range.upperBound else { break }
            out.append(Box(type: type, range: i..<(i + size),
                           payload: (i + header)..<(i + size)))
            i += size
        }
        return out
    }

    /// Top-level box HEADERS, tolerating a box whose body runs past the end of
    /// what we have. `boxes(in:)` deliberately refuses a truncated box -- right
    /// for parsing, wrong for DISCOVERY: a faststart moov is megabytes and a
    /// probe read is kilobytes, so requiring containment reported "no moov" on
    /// exactly the files that have one at the front.
    struct Header { let type: String; let offset: Int; let size: Int }

    static func scanHeaders(_ d: Data, limit: Int = 16) -> [Header] {
        var out: [Header] = []
        var i = 0
        while i + 8 <= d.count && out.count < limit {
            var size = Int(be32(d, i))
            var header = 8
            if size == 1 {
                guard i + 16 <= d.count else { break }
                size = Int(be64(d, i + 8)); header = 16
            } else if size == 0 {
                size = d.count - i
            }
            guard size >= header else { break }
            let type = String(bytes: d[(i + 4)..<(i + 8)], encoding: .isoLatin1) ?? "????"
            out.append(Header(type: type, offset: i, size: size))
            i += size                      // may run past the buffer; that is fine
        }
        return out
    }

    static func find(_ type: String, in d: Data, range: Range<Int>) -> Box? {
        boxes(in: d, range: range).first { $0.type == type }
    }

    static func be16(_ d: Data, _ i: Int) -> UInt16 {
        (UInt16(d[i]) << 8) | UInt16(d[i + 1])
    }
    static func be32(_ d: Data, _ i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i + 1]) << 16)
            | (UInt32(d[i + 2]) << 8) | UInt32(d[i + 3])
    }
    static func be64(_ d: Data, _ i: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v = (v << 8) | UInt64(d[i + k]) }
        return v
    }

    // MARK: - Parsed model

    struct Sample {
        var offset: Int             // in the SOURCE file
        var size: Int
        var duration: UInt32        // in the track timescale
        var compositionOffset: Int32
        var isSync: Bool
    }

    struct Track {
        var id: UInt32
        var timescale: UInt32
        var duration: UInt64
        var handler: String         // "vide" / "soun"
        var trakBox: Data           // the ORIGINAL trak, rewritten for init
        var samples: [Sample]
    }

    struct Movie {
        var timescale: UInt32
        var duration: UInt64
        var tracks: [Track]
        var ftyp: Data
    }

    // MARK: - Parsing

    /// `head` must contain ftyp + the whole moov. Media bytes are NOT needed.
    static func parse(head d: Data) throws -> Movie {
        let top = boxes(in: d, range: 0..<d.count)
        guard let ftypBox = top.first(where: { $0.type == "ftyp" }) else {
            throw Err.missing("ftyp")
        }
        guard let moovBox = top.first(where: { $0.type == "moov" }) else {
            throw Err.missing("moov")   // caller must fetch more of the file
        }
        guard let mvhd = find("mvhd", in: d, range: moovBox.payload) else {
            throw Err.missing("mvhd")
        }
        let mvVersion = d[mvhd.payload.lowerBound]
        var mvTimescale: UInt32 = 600
        var mvDuration: UInt64 = 0
        if mvVersion == 1 {
            mvTimescale = be32(d, mvhd.payload.lowerBound + 20)
            mvDuration = be64(d, mvhd.payload.lowerBound + 24)
        } else {
            mvTimescale = be32(d, mvhd.payload.lowerBound + 12)
            mvDuration = UInt64(be32(d, mvhd.payload.lowerBound + 16))
        }

        var tracks: [Track] = []
        for trak in boxes(in: d, range: moovBox.payload) where trak.type == "trak" {
            if let t = try parseTrack(d, trak) { tracks.append(t) }
        }
        guard !tracks.isEmpty else { throw Err.missing("trak") }
        return Movie(timescale: mvTimescale, duration: mvDuration,
                     tracks: tracks, ftyp: d.subdata(in: ftypBox.range))
    }

    private static func parseTrack(_ d: Data, _ trak: Box) throws -> Track? {
        guard let tkhd = find("tkhd", in: d, range: trak.payload),
              let mdia = find("mdia", in: d, range: trak.payload),
              let mdhd = find("mdhd", in: d, range: mdia.payload),
              let hdlr = find("hdlr", in: d, range: mdia.payload),
              let minf = find("minf", in: d, range: mdia.payload),
              let stbl = find("stbl", in: d, range: minf.payload)
        else { return nil }

        let tkVer = d[tkhd.payload.lowerBound]
        let trackID = tkVer == 1 ? be32(d, tkhd.payload.lowerBound + 20)
                                 : be32(d, tkhd.payload.lowerBound + 12)
        let mdVer = d[mdhd.payload.lowerBound]
        let timescale = mdVer == 1 ? be32(d, mdhd.payload.lowerBound + 20)
                                   : be32(d, mdhd.payload.lowerBound + 12)
        let duration: UInt64 = mdVer == 1 ? be64(d, mdhd.payload.lowerBound + 24)
                                          : UInt64(be32(d, mdhd.payload.lowerBound + 16))
        let handler = String(bytes: d[(hdlr.payload.lowerBound + 8)..<(hdlr.payload.lowerBound + 12)],
                             encoding: .isoLatin1) ?? "----"

        let samples = try buildSamples(d, stbl: stbl)
        guard !samples.isEmpty else { return nil }

        return Track(id: trackID, timescale: timescale, duration: duration,
                     handler: handler, trakBox: d.subdata(in: trak.range),
                     samples: samples)
    }

    /// The heart of it: stts + stsc + stsz + stco/co64 (+ ctts, stss) give an
    /// absolute file offset and a duration for every sample.
    private static func buildSamples(_ d: Data, stbl: Box) throws -> [Sample] {
        guard let sttsB = find("stts", in: d, range: stbl.payload),
              let stscB = find("stsc", in: d, range: stbl.payload),
              let stszB = find("stsz", in: d, range: stbl.payload)
        else { throw Err.missing("stbl children") }
        let chunkOffsets: [Int] = {
            if let co = find("stco", in: d, range: stbl.payload) {
                let n = Int(be32(d, co.payload.lowerBound + 4))
                return (0..<n).map { Int(be32(d, co.payload.lowerBound + 8 + $0 * 4)) }
            }
            if let co = find("co64", in: d, range: stbl.payload) {
                let n = Int(be32(d, co.payload.lowerBound + 4))
                return (0..<n).map { Int(be64(d, co.payload.lowerBound + 8 + $0 * 8)) }
            }
            return []
        }()
        guard !chunkOffsets.isEmpty else { throw Err.missing("stco/co64") }

        // sizes
        let defaultSize = Int(be32(d, stszB.payload.lowerBound + 4))
        let sampleCount = Int(be32(d, stszB.payload.lowerBound + 8))
        var sizes = [Int](repeating: defaultSize, count: sampleCount)
        if defaultSize == 0 {
            for i in 0..<sampleCount {
                sizes[i] = Int(be32(d, stszB.payload.lowerBound + 12 + i * 4))
            }
        }

        // durations (stts run-length)
        var durations = [UInt32](); durations.reserveCapacity(sampleCount)
        let sttsN = Int(be32(d, sttsB.payload.lowerBound + 4))
        for i in 0..<sttsN {
            let base = sttsB.payload.lowerBound + 8 + i * 8
            let count = Int(be32(d, base)), delta = be32(d, base + 4)
            for _ in 0..<count where durations.count < sampleCount {
                durations.append(delta)
            }
        }
        while durations.count < sampleCount { durations.append(durations.last ?? 0) }

        // composition offsets
        var ctts = [Int32](repeating: 0, count: sampleCount)
        if let c = find("ctts", in: d, range: stbl.payload) {
            let n = Int(be32(d, c.payload.lowerBound + 4))
            var idx = 0
            for i in 0..<n {
                let base = c.payload.lowerBound + 8 + i * 8
                let count = Int(be32(d, base))
                let off = Int32(bitPattern: be32(d, base + 4))
                for _ in 0..<count where idx < sampleCount { ctts[idx] = off; idx += 1 }
            }
        }

        // sync samples: absent stss, EVERY sample is a sync sample (audio).
        var sync = [Bool](repeating: find("stss", in: d, range: stbl.payload) == nil,
                          count: sampleCount)
        if let s = find("stss", in: d, range: stbl.payload) {
            let n = Int(be32(d, s.payload.lowerBound + 4))
            for i in 0..<n {
                let num = Int(be32(d, s.payload.lowerBound + 8 + i * 4))
                if num >= 1 && num <= sampleCount { sync[num - 1] = true }
            }
        }

        // stsc -> samples per chunk, then walk chunks to get offsets
        struct SC { var firstChunk: Int; var perChunk: Int }
        let stscN = Int(be32(d, stscB.payload.lowerBound + 4))
        var entries: [SC] = []
        for i in 0..<stscN {
            let base = stscB.payload.lowerBound + 8 + i * 12
            entries.append(SC(firstChunk: Int(be32(d, base)),
                              perChunk: Int(be32(d, base + 4))))
        }

        var samples: [Sample] = []; samples.reserveCapacity(sampleCount)
        var s = 0
        // Walk stsc IN STEP with the chunks. Re-scanning the entry table for
        // every chunk is O(chunks x entries): harmless on a short clip, and on
        // a feature (hundreds of thousands of chunks) it hangs long enough to
        // look like a deadlock -- which is exactly how it presented, with the
        // moov fetched and no plan ever produced.
        var entryIdx = 0
        for (ci, chunkOffset) in chunkOffsets.enumerated() {
            let chunkNo = ci + 1
            while entryIdx + 1 < entries.count,
                  entries[entryIdx + 1].firstChunk <= chunkNo {
                entryIdx += 1
            }
            let perChunk = entries.isEmpty ? 1 : entries[entryIdx].perChunk
            var off = chunkOffset
            for _ in 0..<perChunk {
                guard s < sampleCount else { break }
                samples.append(Sample(offset: off, size: sizes[s],
                                      duration: durations[s],
                                      compositionOffset: ctts[s], isSync: sync[s]))
                off += sizes[s]
                s += 1
            }
            if s >= sampleCount { break }
        }
        return samples
    }

    enum Err: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self { case .missing(let w): return "MP4Fragmenter: missing \(w)" }
        }
    }
}

// MARK: - Writing

extension MP4Fragmenter {

    static func u8(_ v: UInt8) -> Data { Data([v]) }
    static func u16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
    static func u32(_ v: UInt32) -> Data {
        Data([UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
    static func u64(_ v: UInt64) -> Data {
        var d = Data(); for k in stride(from: 56, through: 0, by: -8) {
            d.append(UInt8((v >> UInt64(k)) & 0xFF)) }
        return d
    }
    static func box(_ type: String, _ payload: Data) -> Data {
        var d = u32(UInt32(payload.count + 8))
        d.append(type.data(using: .isoLatin1)!)
        d.append(payload)
        return d
    }
    static func fullBox(_ type: String, version: UInt8, flags: UInt32, _ payload: Data) -> Data {
        var p = u8(version)
        p.append(Data([UInt8((flags >> 16) & 0xFF), UInt8((flags >> 8) & 0xFF), UInt8(flags & 0xFF)]))
        p.append(payload)
        return box(type, p)
    }

    /// Rewrite a source `trak` so its sample tables are EMPTY. The init
    /// segment must describe the tracks (stsd carries the codec configuration)
    /// while declaring no samples -- those arrive in the fragments.
    static func emptiedTrak(_ trak: Data) -> Data {
        func rewrite(_ d: Data, _ range: Range<Int>, container: Bool) -> Data {
            var out = Data()
            for b in boxes(in: d, range: range) {
                switch b.type {
                case "stss", "ctts":
                    // OMIT, do not empty. An stss with entry_count 0 does not
                    // mean "unknown", it declares that the track has NO sync
                    // samples -- so the player can find no random-access point
                    // and never starts, which is exactly what the device did:
                    // playlist parsed, init accepted, segment 0 fetched, then
                    // silence. ffmpeg's own fMP4 init omits both boxes; ours
                    // was the only structural difference.
                    continue
                case "stts", "stsc":
                    out.append(fullBox(b.type, version: 0, flags: 0, u32(0)))
                case "stsz":
                    var p = u32(0); p.append(u32(0))            // sample_size, count
                    out.append(fullBox("stsz", version: 0, flags: 0, p))
                case "stco":
                    out.append(fullBox("stco", version: 0, flags: 0, u32(0)))
                case "co64":
                    out.append(fullBox("stco", version: 0, flags: 0, u32(0)))
                case "edts":
                    // DROP the edit list. It is written against the source's
                    // own sample table and, carried into a fragmented file
                    // whose tables are empty, it re-maps the track timeline:
                    // AVFoundation then reported the movie 217s longer than
                    // its tracks and delivered audio with presentation times
                    // at the END of the film (94 samples, last pts 5632s)
                    // while video decoded correctly. Fragments carry their own
                    // decode times via tfdt, so no edit is needed.
                    continue
                case "trak", "mdia", "minf", "stbl":
                    out.append(box(b.type, rewrite(d, b.payload, container: true)))
                default:
                    out.append(d.subdata(in: b.range))
                }
            }
            return out
        }
        guard let t = boxes(in: trak, range: 0..<trak.count).first(where: { $0.type == "trak" })
        else { return trak }
        return box("trak", rewrite(trak, t.payload, container: true))
    }

    static func initSegment(_ m: Movie) -> Data {
        var moov = Data()
        // mvhd (version 0; duration 0 is correct for fragmented -- the real
        // duration is advertised via mehd below).
        var mvhd = Data()
        mvhd.append(u32(0)); mvhd.append(u32(0))           // created, modified
        mvhd.append(u32(m.timescale)); mvhd.append(u32(0)) // timescale, duration
        mvhd.append(u32(0x0001_0000))                      // rate 1.0
        mvhd.append(u16(0x0100)); mvhd.append(u16(0))      // volume, reserved
        mvhd.append(Data(repeating: 0, count: 8))
        for v in [UInt32(0x0001_0000), 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] {
            mvhd.append(u32(v))                             // unity matrix
        }
        mvhd.append(Data(repeating: 0, count: 24))         // predefined
        mvhd.append(u32((m.tracks.map { $0.id }.max() ?? 1) + 1))
        moov.append(fullBox("mvhd", version: 0, flags: 0, mvhd))

        for t in m.tracks { moov.append(emptiedTrak(t.trakBox)) }

        // mvex: mehd (total duration) + one trex per track
        var mvex = Data()
        mvex.append(fullBox("mehd", version: 1, flags: 0, u64(m.duration)))
        for t in m.tracks {
            var trex = u32(t.id)
            trex.append(u32(1))          // default_sample_description_index
            trex.append(u32(0)); trex.append(u32(0)); trex.append(u32(0))
            mvex.append(fullBox("trex", version: 0, flags: 0, trex))
        }
        moov.append(box("mvex", mvex))

        // OUR OWN ftyp, not the source's. The fragments below set the tfhd
        // `default-base-is-moof` flag (0x020000), and that is only legal in a
        // file whose compatible brands include `iso5`. A plain archive.org MP4
        // declares `isom`/`mp42` and nothing later, so copying its ftyp
        // verbatim produced fragments a strict parser may refuse -- the
        // segment is fetched, accepted, and then playback silently never
        // starts.
        var brands = Data("isom".utf8)                 // major brand
        brands.append(u32(512))                        // minor version
        for b in ["isom", "iso2", "iso5", "iso6", "avc1", "mp41", "mp42", "cmfc", "dash"] {
            brands.append(Data(b.utf8))
        }
        var out = box("ftyp", brands)
        out.append(box("moov", moov))
        return out
    }

    /// The segment index. WITHOUT it a player must SCAN the file to learn
    /// where fragments are and how long the movie runs: measured on the Apple
    /// TV, AVFoundation issued requests at output offsets 0, 4.7 MB, 7.5 MB,
    /// 14 MB and 17 MB within ONE SECOND, cancelling each -- 657 MB fetched
    /// from archive.org with playback still at t=0. Over a LAN that scan is
    /// free, which is why the same code played perfectly from a local server.
    /// One sidx makes the whole layout knowable from the init segment.
    static func sidx(_ m: Movie, _ frags: [Fragment], refTrack: Track) -> Data {
        var p = u32(refTrack.id)
        p.append(u32(refTrack.timescale))
        p.append(u64(0))                       // earliest_presentation_time
        p.append(u64(0))                       // first_offset: sidx abuts moof 1
        p.append(u16(0))                       // reserved
        p.append(u16(UInt16(min(frags.count, 65535))))
        for f in frags.prefix(65535) {
            // reference_type 0 (media) in the high bit, then the byte size.
            p.append(u32(UInt32(f.size) & 0x7FFF_FFFF))
            var dur: UInt64 = 0
            if let ft = f.tracks.first(where: { $0.trackID == refTrack.id }) {
                for i in ft.firstSample..<(ft.firstSample + ft.count) {
                    dur += UInt64(refTrack.samples[i].duration)
                }
            }
            p.append(u32(UInt32(truncatingIfNeeded: dur)))
            // starts_with_SAP = 1, SAP_type = 1: every fragment opens on a
            // keyframe, which the planner guarantees.
            p.append(u32(0x9000_0000))
        }
        return fullBox("sidx", version: 1, flags: 0, p)
    }

    // MARK: - Layout

    struct FragTrack {
        var trackID: UInt32
        var firstSample: Int
        var count: Int
        var baseDecodeTime: UInt64
        var byteCount: Int
    }
    struct Fragment {
        var sequence: UInt32
        var tracks: [FragTrack]
        var outOffset: Int          // byte offset of this moof in the OUTPUT
        var size: Int               // moof + mdat, total
    }
    struct Plan {
        var initSegment: Data
        var fragments: [Fragment]
        var totalLength: Int
    }

    /// Group samples into ~`seconds`-long fragments, and compute every output
    /// byte offset BEFORE any media is fetched -- the resource loader has to
    /// answer arbitrary ranges and state an exact content length.
    static func plan(_ m: Movie, seconds: Double = 2.0) -> Plan {
        var frags: [Fragment] = []
        var cursor = [Int](repeating: 0, count: m.tracks.count)
        var decode = [UInt64](repeating: 0, count: m.tracks.count)
        var seq: UInt32 = 1
        // The VIDEO track sets each fragment's boundary, because only it has
        // keyframe constraints; every other track then covers the SAME time
        // span. Letting each track choose independently produced 5.3s of video
        // beside 2.0s of audio in one fragment -- so two seconds of sound
        // dragged five seconds of picture, and the imbalance grew with every
        // fragment. Measured as ~9x the native bitrate and a stall at ~100s.
        let masterIdx = m.tracks.firstIndex { $0.handler == "vide" } ?? 0
        while true {
            var fts: [FragTrack] = []
            var spanSeconds = seconds

            // 1. The master track: run to at least `seconds`, then to the next
            //    sync sample so the fragment is independently decodable.
            let mt = m.tracks[masterIdx]
            if cursor[masterIdx] < mt.samples.count {
                let want = UInt64(Double(mt.timescale) * seconds)
                var taken = 0, dur: UInt64 = 0, bytes = 0
                var i = cursor[masterIdx]
                while i < mt.samples.count {
                    if taken > 0, dur >= want, mt.samples[i].isSync { break }
                    dur += UInt64(mt.samples[i].duration)
                    bytes += mt.samples[i].size
                    taken += 1; i += 1
                }
                if taken > 0 {
                    fts.append(FragTrack(trackID: mt.id, firstSample: cursor[masterIdx],
                                         count: taken, baseDecodeTime: decode[masterIdx],
                                         byteCount: bytes))
                    spanSeconds = Double(dur) / Double(mt.timescale)
                    cursor[masterIdx] += taken
                    decode[masterIdx] += dur
                }
            }

            // 2. Every other track covers exactly that span.
            for (ti, t) in m.tracks.enumerated() where ti != masterIdx {
                guard cursor[ti] < t.samples.count else { continue }
                let want = UInt64(Double(t.timescale) * spanSeconds)
                var taken = 0, dur: UInt64 = 0, bytes = 0
                var i = cursor[ti]
                while i < t.samples.count {
                    if taken > 0, dur >= want { break }
                    dur += UInt64(t.samples[i].duration)
                    bytes += t.samples[i].size
                    taken += 1; i += 1
                }
                guard taken > 0 else { continue }
                fts.append(FragTrack(trackID: t.id, firstSample: cursor[ti],
                                     count: taken, baseDecodeTime: decode[ti],
                                     byteCount: bytes))
                cursor[ti] += taken
                decode[ti] += dur
            }
            guard !fts.isEmpty else { break }
            let moofSize = moofLength(m, fts)
            let mdat = 8 + fts.reduce(0) { $0 + $1.byteCount }
            // outOffset is filled in below, once the init segment (which now
            // contains a sidx sized by these very fragments) is known.
            frags.append(Fragment(sequence: seq, tracks: fts,
                                  outOffset: 0, size: moofSize + mdat))
            seq += 1
        }

        let refTrack = m.tracks.first { $0.handler == "vide" } ?? m.tracks[0]
        // NO sidx. It was added for the single-virtual-file shape (to stop
        // AVFoundation scanning) and that shape is retired: an HLS playlist
        // now declares the index. An EXT-X-MAP init segment is expected to be
        // ftyp + moov alone, and the stray sidx is the difference between a
        // segment being accepted and playback silently never starting.
        _ = refTrack
        let head = initSegment(m)
        var out = head.count
        for i in frags.indices {
            frags[i].outOffset = out
            out += frags[i].size
        }
        return Plan(initSegment: head, fragments: frags, totalLength: out)
    }

    /// Size of the moof for a given fragment. Deterministic, so the layout can
    /// be computed without building it.
    static func moofLength(_ m: Movie, _ fts: [FragTrack]) -> Int {
        var n = 8 + 16                                   // moof + mfhd
        for ft in fts {
            // traf(8) + tfhd(16) + tfdt(20)
            //   + trun(8 + 4 ver/flags + 4 count + 4 data_offset + 16/sample)
            // SIXTEEN per sample: duration, size, flags, composition offset.
            // Twelve here mis-planned the layout by exactly 4 x sampleCount
            // bytes, which the write/plan equality check caught.
            n += 8 + 16 + 20 + (20 + 16 * ft.count)
        }
        return n
    }

    /// Build one fragment. `media` supplies the SOURCE bytes for a range.
    static func fragment(_ m: Movie, _ f: Fragment,
                         media: (Int, Int) throws -> Data) rethrows -> Data {
        var trafs: [Data] = []
        var mdat = Data()
        // data_offset is relative to the moof start, so the moof must be sized
        // first; build trafs with a placeholder, then patch.
        var runOffsets: [Int] = []
        for ft in f.tracks {
            guard let ti = m.tracks.firstIndex(where: { $0.id == ft.trackID }) else { continue }
            let t = m.tracks[ti]
            var tfhd = u32(ft.trackID)
            // default-base-is-moof (0x020000): offsets are from the moof, which
            // is what every modern parser expects and avoids absolute offsets.
            let traf0 = fullBox("tfhd", version: 0, flags: 0x02_0000, tfhd)
            var tfdtP = u64(ft.baseDecodeTime)
            let traf1 = fullBox("tfdt", version: 1, flags: 0, tfdtP)
            // trun: data-offset(0x1) + duration(0x100) + size(0x200)
            //       + flags(0x400) + composition offset(0x800)
            var trunP = u32(UInt32(ft.count))
            runOffsets.append(trafs.count)              // patch site marker
            trunP.append(u32(0))                        // data_offset placeholder
            for s in ft.firstSample..<(ft.firstSample + ft.count) {
                let smp = t.samples[s]
                trunP.append(u32(smp.duration))
                trunP.append(u32(UInt32(smp.size)))
                // sample_flags: non-sync samples are not random-access points
                trunP.append(u32(smp.isSync ? 0x0200_0000 : 0x0101_0000))
                trunP.append(u32(UInt32(bitPattern: smp.compositionOffset)))
            }
            let traf2 = fullBox("trun", version: 1, flags: 0x0F_01, trunP)
            var traf = Data(); traf.append(traf0); traf.append(traf1); traf.append(traf2)
            trafs.append(box("traf", traf))
            tfhd = Data()
        }

        var mfhd = fullBox("mfhd", version: 0, flags: 0, u32(f.sequence))
        var moofPayload = mfhd
        for t in trafs { moofPayload.append(t) }
        var moof = box("moof", moofPayload)

        // Now patch each trun's data_offset and gather the media.
        var dataCursor = moof.count + 8            // past moof + mdat header
        var searchFrom = 0
        for ft in f.tracks {
            guard let ti = m.tracks.firstIndex(where: { $0.id == ft.trackID }) else { continue }
            let t = m.tracks[ti]
            // locate this traf's trun data_offset field
            if let site = trunDataOffsetSite(in: moof, from: searchFrom) {
                let v = u32(UInt32(dataCursor))
                moof.replaceSubrange(site..<(site + 4), with: v)
                searchFrom = site + 4
            }
            for s in ft.firstSample..<(ft.firstSample + ft.count) {
                let smp = t.samples[s]
                mdat.append(try media(smp.offset, smp.size))
            }
            dataCursor += ft.byteCount
        }
        var out = moof
        out.append(u32(UInt32(mdat.count + 8)))
        out.append("mdat".data(using: .isoLatin1)!)
        out.append(mdat)
        return out
    }

    /// Find the byte position of the next trun's data_offset field.
    private static func trunDataOffsetSite(in moof: Data, from: Int) -> Int? {
        let tag = "trun".data(using: .isoLatin1)!
        var i = max(from, 4)
        while i + 4 <= moof.count {
            if moof.subdata(in: i..<(i + 4)) == tag {
                // trun header: [size][trun][ver+flags(4)][sample_count(4)][data_offset]
                return i + 4 + 4 + 4
            }
            i += 1
        }
        return nil
    }
}
