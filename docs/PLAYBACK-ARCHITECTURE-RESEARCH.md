# The Quality Program: research synthesis and plan (2026-08-17)

Commissioned after the owner's direction: full best-practices research before
fixes; no re-implementing rejected approaches; best-in-class, works every
time. Four research reports feed this (docs/research/
streaming-architecture-2026.md, captions-architecture-2026.md,
sync-architecture-2026.md, pipeline-and-pickers-2026.md — each with sources
and verified-vs-inferred markings). This document is the binding plan.

## The core insight across all four reports

The app's fragility is not any single bug — it is that playback exists as a
MATRIX of paths (custom-scheme loader / plain URL / HLS wrapper / overlay /
native track), and every Apple media feature keys on "is this a plain
asset?". The industry solution, used in production at scale (KTVHTTPCache,
Alibaba, and tacitly endorsed by Apple's own forum guidance), is a LOCAL
REVERSE PROXY: one plain `http://127.0.0.1` URL for AVPlayer, with all our
resilience engineering behind it. One path. Plain-asset status everywhere.

## The plan, in phases

### Phase 0 — Data correctness (RUNNING NOW; no architecture dependency)
- Codec gate: ffprobe-verified `videoCodec` on every uploader-original file
  (tools/audit_codecs.py, in progress over 9,101 items); AV1/VP9 →
  same-item h.264 derivative swap, else reversible exclude. The Oregon
  Trail class dies at the catalog, not the error screen.
- Derivative-ladder preference in the pipeline: compliant original →
  h.264 IA → h.264 → 512Kb. (IA's own player uses derivatives ONLY.)
- Later rung: repair-and-rehost (`archivewatch-fix-<slug>` items via the
  existing IAS3 keys) for the popular tail with no safe copy — needs owner
  sign-off on uploading under their account.
- Codec safety policy recorded (research doc) and enforced as `codecSafe`.

### Phase 1 — LocalMediaServer (the keystone)
- NWListener loopback HTTP server (Apple-frameworks-only), fronting the
  ResilientStreamLoader ENGINE (chunking, resume-from-exact-byte, node
  pin/failover, block cache) ported behind normal HTTP semantics.
- Non-negotiables from research: exact 206/Content-Range semantics, HEAD,
  identity encoding, streamed bodies, loopback bind + per-launch token +
  ephemeral port, disconnect-as-cancellation.
- The scout uses the proxy too: one origin connection pool — the caption
  engine stops competing with playback at the TCP level.
- Two device verifications BEFORE cutover (paired-ATV harness, one shape
  per process, assert emitted text / external playback):
  1. tvOS 27 generated captions emit through the proxy (inferred-strong).
  2. LAN-bind variant AirPlays with resilience (plausible; D051 swap stays
     regardless — never worse than today).
- The byte path becomes curl-diffable against origin over a full film —
  this convicts or exonerates the loader in the audio-static hunt (task
  #46) as a side effect of the migration test suite.
- Cutover gated on: byte-diff clean, scenario suite green at full speed AND
  through the 10 Mbps throttled gate, His Girl Friday + TtCRB-4K soaks.

### Phase 2 — Captions that hold
- File timing fixed AT SOURCE catalog-wide with industry tools: alass
  (primary; handles splices/segment drift the bespoke judge is blind to) +
  ffsubsync (cross-check), applied only on agreement ≤0.5s — and they run
  on plain CI (VAD, no speech models — removes the local-only constraint).
  Sync-on-ingest for all new provider fetches (Bazarr's pattern).
- The overlay renderer stays (Infuse/VLC/Plex all render their own);
  upgrade its drawing to AVCaptionRenderer so styling matches system
  captions exactly.
- The SpeechAnalyzer scout remains the generated engine (no public
  equivalent exists; it IS the state of the art) — kept as-is, pointed at
  the proxy.
- Optional later: single-file fMP4 HLS pilot for top titles (native CC
  menu + generated-subtitle eligibility + per-segment buffering), hosted
  as archive.org derivatives, scenario-gated.

### Phase 3 — Sync and History that converge
- Migrate the hand-rolled 4-blob CloudKit sync to CKSyncEngine (tvOS 17+):
  per-item records in a custom zone, push-triggered fetch, change tokens.
  The current design structurally cannot converge (no push path exists for
  default-zone fixed records; whole-blob LWW loses concurrent edits).
- Data model per research: Progress:{archiveID} per-item LWW + OR-merged
  completed; PlayEvent:{device}:{ts} append-only union = the history.
- UX (the Trakt model, resolving the owner's Watched/History confusion):
  ONE History list (chronological play events); Watched becomes a derived
  BADGE on tiles + a Detail toggle — not a second content list; Continue
  Watching stays. One derivation direction, no disagreeing lists.
- Google Drive plane: publish the OAuth consent screen to Production when
  created (Testing status = 7-day token death).

### Phase 4 — User choice (the owner's picker idea, validated)
- Detail: long-press Play → Versions menu; labels `480p · H.264 · 575 MB —
  Archive derivative`; per-title persistence (the gap Plex users complain
  about). Unsafe-codec versions filtered per platform, never grayed.
- In-player transport bar: Version menu + Caption-source menu (Published
  file / Auto-generated / Off). infoViewActions "Choose Version…".
  contextualAction after stalls: "Switch to 480p version".
- All APIs tvOS 15+ (app floor 17) — verified availability.

## Sequencing and gates
Phase 0 is running. Phase 1 is the prerequisite for permanently fixing the
error/caption/AirPlay classes and is where the static hunt resolves.
Phases 2-4 build on it but the alass pipeline and CKSyncEngine migration
are independent of the proxy and can proceed in parallel. Every phase
ships through the external-observation suite + the 10 Mbps throttled gate
(Decision 076) on Release builds.

## Owner decision points
1. Green-light the LocalMediaServer architecture (Phase 1).
2. History UX: one History list + Watched-as-badge (matches "there should
   only be one" intent while keeping the state visible).
3. Repair-and-rehost uploads under the owner's archive.org account
   (Phase 0 later rung).
4. alass/ffsubsync adoption in the pipeline (new tools, replacing the
   bespoke source-level judge).

## Start times: measured, and why the obvious fix was not shipped (2026-08-18)

Decision 077 promised "films should start within 30 seconds". Measured for the
first time across eight popular titles on the Apple TV
(`tools/measure_start_times.sh`, setupPlayer -> itemReady):

    TheNakedWitch  1.3s   yojimbo  5.8s   his_girl_friday  6.8s   suddenly  9.6s
    reefer_madness 21.0s  grapes_of_wrath 40.3s
    Voyage...PrehistoricWomen and JungleBook: no frame in 80s

Five of eight inside the promise, one over, two not starting.

**It is node weather, not slow films.** Yojimbo took 5.8s here after failing to
produce a frame twice within 75s an hour earlier, when its storage node
measured 32.7s to first byte against 0.7s for a healthy film on the same
network in the same minute. `firstByteTimeout` is 30s, so the probe sat through
the whole thing and retried, often onto the same node.

**A hedged first-byte probe was built, gated, measured and REVERTED.** Racing
every known node and taking the first answer is attractive because it has no
threshold to tune — and a threshold is what regressed twice (Decision 076
deleted a slow-chunk watchdog at 5.6 Mbps for killing normal wifi, then at
0.2 Mbps for killing legitimate slow starts). It passed both gates: byte
identical to origin under concurrent interleaved reads, and playing in real
time through the 10 Mbps throttled server. But the device numbers came back
nominally WORSE (his_girl_friday 6.8 -> 22.4s, yojimbo 5.8 -> 21.9s, reefer
madness 21.0 -> no frame), and that cannot be attributed to the change either.

**The methodological finding is the durable one.** Both runs were SEQUENTIAL
BLOCKS an hour apart, and the variable under test — archive.org node health —
varies on exactly that timescale. Comparing block A to block B measures the
hour, not the change. An honest A/B here has to INTERLEAVE the arms (alternate
per title, or per trial) so weather is shared between them, which is a stronger
requirement than Decision 075's "repeated trials per arm" and is what any
future attempt at this needs.

Nothing shipped. The measurement instrument and this record did.
