# Research: resilient streaming architecture (2026-08-17)

The load-bearing report of the research program. Condensed; sources at end.

## Ranked recommendation
1. **Localhost reverse proxy fronting the existing ResilientStreamLoader
   engine.** AVPlayer plays http://127.0.0.1:PORT/v/<token>/<id>.mp4; the
   proxy serves it by porting the loader's guts (8MB streamed chunks,
   resume-from-exact-byte, node pin/failover, 2MB block cache) behind normal
   HTTP. The asset is then PLAIN to AVFoundation: every disqualification we
   measured (AirPlay TSI, generated-captions-never-offered D067,
   AVAssetReader refusal D054) keys on the custom scheme+delegate, not on
   where bytes come from. Industry-validated: KTVHTTPCache (canonical,
   production at scale), Alibaba Taobao Movie (public writeup), StyleShare,
   Firefox-iOS shipped local servers; Apple forum guidance calls an
   on-device reverse proxy "the only valid alternative" to the loader.
2. Status quo (loader + per-capability swaps): the path MATRIX is the
   disease; every new OS media feature disqualifies the loader again.
3. Selective CMAF HLS for top titles on an archive.org item: later
   supplement only (catalog-wide repackaging = tens of TB, no free host;
   nobody serious repackages archive.org).
4. Custom engines (VLCKit/mpv/KSPlayer): REJECTED — Plex/Infuse left
   AVFoundation for codec breadth we don't need, and pay with degraded
   AirPlay + zero system-caption integration.

## Implementation non-negotiables
- Hand-rolled NWListener loopback server (Apple-frameworks-only rule) or
  vendored FlyingFox (MIT, Swift concurrency, tvOS 13+; actively maintained;
  GCDWebServer is archived).
- EXACT range semantics: 206 + correct Content-Range/Content-Length;
  200+length for rangeless; HEAD; Content-Type video/mp4; Accept-Ranges;
  identity encoding, never chunked/gzip. (D075: wrong Range semantics
  present as "media damaged", not network errors.)
- STREAM bodies as bytes arrive (D031 lesson maps 1:1).
- AVFoundation opens 2-4 concurrent sockets, odd/overlapping ranges; abrupt
  disconnects on seeks = cancellation, not error.
- Loopback bind + per-launch random path token + ephemeral port (never
  persist proxy URLs — Firefox's port-change bug class).
- tvOS lifecycle: start lazily on first play, keep for process lifetime.
- ATS: NSAllowsLocalNetworking = YES (doesn't weaken remote ATS).
- Point the SCOUT at the proxy too: one origin connection pool — the scout
  stops competing with playback at the TCP level.
- Optional Infuse-style upgrade: disk-backed cache in the proxy (greedy
  background fill) = Infuse's weather/decode decoupling without its costs.

## AirPlay
AirPlay Video is a URL HANDOFF (receiver fetches the URL itself):
- 127.0.0.1 can't AirPlay → keep the D051 swap (no worse than today).
- LAN-bind variant (http://<device-lan-ip>:port) = receiver fetches THROUGH
  our proxy → resilient AirPlay (what D051's raw swap gives up). Plausible,
  unverified — A/B later. (TSI thread on record: AirPlay worked when a
  loader redirected to a web server — the proxy systematizes that.)

## Two claims requiring device verification BEFORE committing
1. Generated captions emit through a loopback-proxied progressive MP4 on
   tvOS 27 (one shape per process; assert emitted TEXT — D067 discipline).
2. LAN-bound proxy URL external-plays over AirPlay.

## Other findings
- No public custom-URLSession injection for AVFoundation; the header-fields
  asset key remains undocumented/rejection-risky. AVAssetDownloadTask is
  HLS-only. preferredPeakBitRate is HLS-only. AVPlayer's progressive
  flush-on-reset behavior unchanged tvOS 17→27 — Apple's transport
  investment is entirely HLS.
- Infuse's real trick = greedy disk cache (up to ~half the file), custom
  engine; its AirPlay is its weak spot BECAUSE of the custom engine.
- The testability win: proxy vs origin is curl-byte-diffable over a full
  film — convicts or exonerates the loader in the audio-static hunt.

## Key sources
KTVHTTPCache · alibabacloud.com/blog/596862 · StyleShare
HLSCachingReverseProxyServer · AVPlayer-HTTP-Headers-Example · FlyingFox ·
GCDWebServer (archived; backgrounding contract) · Firefox bug 1201592 ·
nto.github.io/AirPlay.html · Apple forums 28101/693478/20421/722441/770949 ·
WWDC26-256 · Swiftfin players.md · Plex mpv engine writeup · Infuse cache
threads (firecore 60449/40510) · NowSecure ATS guide
