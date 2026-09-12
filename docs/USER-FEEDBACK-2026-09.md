# What real users said — r/classicfilms, 2026-09-10

The first post to an audience that is not us: 44 comments from people who
installed the app the day Roku went live. This is the triage. Every row cites
the person who reported it and, where the owner replied in the thread, the
commitment that reply made — those replies are the spec.

Source: `r/classicfilms` — "Free streaming app for watching classic films".

**The headline is that nothing is fundamentally wrong.** The overwhelming
majority of the thread is people installing it and naming the film they
started. Roku in particular went perfectly: it was found by search, installed
in one step, and several people reported watching the same day. What follows
is the minority that did not work.

---

## Status at a glance — reconciled 2026-09-12

Every row below was checked against the code and the live store state, not
recalled. The store reading was challenged and then confirmed THREE ways:
`asc_release.py status`, Apple's PUBLIC iTunes lookup API (`version: 1.42.9`,
released 2026-09-11T23:49:09Z), and the raw ASC `appStoreVersions` list, where
1.42.9 is the newest READY_FOR_SALE on TV_OS, IOS and MAC_OS and 1.42.28 is
the only thing above it. Note 1.42.9 shipped THAT DAY — a release had just
landed, which is exactly why "live is 1.42.9" reads as wrong at a glance. The
fixes below were cut after it. **The distinction that matters is "fixed" versus "shipped to users":
the App Store is on 1.42.9, and 1.42.28 has been WAITING_FOR_REVIEW** — so
several fixes exist and no user has them yet.

| # | Issue | Engineering | In users' hands? |
|---|---|---|---|
| P0 | Won't launch, tvOS 26.3 | Candidate fix in **1.42.14** (NowPlayingWarmup — the watchdog kill that reads as a crash) | **No** — live is 1.42.9. Also never verified against 26.3 |
| P1 | Slow on 2nd-gen Apple TV | Fixed and measured in **1.42.13** (ninety invisible procedural posters) | **No** — live is 1.42.9 |
| P2 | Fire TV unavailable | Fixed (Decision 115 minSdk, 38 → 91 devices), submitted | Waiting on Amazon; owner to post in-thread when live |
| P3 | No genre sort | **CLOSED** — iOS/macOS 1.42.8, Android 1.42.47 | iOS/macOS **yes** (1.42.8 ≤ live 1.42.9). Android **no** |
| P4 | Only the low-quality copy | Deliberately scoped as research, not a fix | n/a |
| P5 | Plays 5 minutes then stops | **ANSWERED and fixed** — Decision 118, **1.42.45** | **No** — not even in the in-review 1.42.28 |
| P6 | Samsung TV | In flight, Decision 112 (US-only, Public Seller) | Not submitted |
| P7 | Letterboxd / JustWatch | Blocked externally — needs approval by email, requested | n/a |
| P8 | "Do you actually vet the films?" | **DONE** — the public vetting page is live (HTTP 200 at /vetting/) and built on every deploy | **Yes** |
| P9 | iOS 26 floor | Deliberate; revisit only with data | n/a |

**The single most useful action is not engineering.** Six of these are fixed in
the repo and blocked behind one App Store review. P0 and P1 are the two
loudest complaints in the thread and both have had fixes for days.

## P0 — Archive Watch will not launch on Apple TV, tvOS 26.3

> **Status 2026-09-12: candidate fix shipped to the repo in 1.42.14, NOT live.**
> `NowPlayingWarmup` warms `MPRemoteCommandCenter` off the main thread, because
> AVKit's `_becomeNowPlaying` `dispatch_once` on the scene-update path is a
> FRONTBOARD watchdog kill (`0x8BADF00D`) that presents exactly as "blinks and
> doesn't open". It is a CANDIDATE: nobody has reproduced this on 26.3, no crash
> log has been read, and the store is still serving 1.42.9. Do not tell the
> reporter it is fixed until a 26.3 device or a crash organizer entry says so.

**u/Fit_Explorer_2566**, Apple TV 4K 2nd gen, tvOS 26.3: the app "blinks and
doesn't open". Unchanged after a device restart, and after delete and
reinstall. **Owner: "Thank you so much for the specific evidence. I'm on it.
Should be fixed soon!"**

This is the worst class of bug in the thread — not a degraded experience, a
zero. Measured today against the newly paired hardware:

| Hardware | tvOS | Build | Result |
|---|---|---|---|
| Apple TV 4K **2nd gen** (Fireplace) | 27.0 | 1017 | **launches**, catalog 26,149 items |
| Apple TV 4K 3rd gen (Movie Room) | **26.6** | 1017 | **launches**, catalog 26,345 items |
| Apple TV 4K 2nd gen (reporter) | **26.3** | 1017 | **blinks and dies** |

**Build 1017 IS 1.42.5 — the exact binary on the App Store.** So this is not a
stale-build artifact.

**The report is believed.** The table above is not an attempt to cast doubt on
it; it is an attempt to narrow it. Two suspects are eliminated — the
2nd-generation hardware and tvOS 26 as a family — which leaves tvOS **26.3
specifically**, somewhere below 26.6. A bug that needs a particular point
release to appear is a normal bug, not an unlikely one.

Nobody on this bench runs 26.3, and the owner has been on the beta for a
while, so **every device we test on is ahead of every device our users have.**
That gap is the finding underneath the finding, and it applies to far more
than this one bug: we cannot see what most users see.

**Next steps, in order.** Read the App Store Connect crash organizer for
1.42.5 on tvOS 26.3 — a real stack beats any hypothesis. Note that 1.42.5
carries exactly one app change, Decision 106's fMP4/HLS remux, which is gated
to 27+ at runtime but is the only new code in the shipped binary. Ask the
reporter for the exact tvOS build. If no crash log appears, the cheapest
decisive move is a 26.3 device on the bench.

## P1 — The Apple TV app is slow on 2nd-generation hardware

> **Status 2026-09-12: fixed in 1.42.13, NOT live.** Measured on the 2nd-gen
> unit: Home scrolled at 24-27fps with 60-67% long frames while a 3rd gen held
> 52-58fps on the same build. Cause was ~90 `ProceduralPoster` cards kept alive
> behind posters that had already loaded and covered them. The store is on
> 1.42.9, so the reporter still has the slow build.

**u/hondo77777**, Apple TV 4K 2nd gen: "very, very s l o w", while liking the
interface otherwise. **Owner: "Clearly needs some optimization. Look for the
update early next week."**

Independently corroborated by the owner's own observation that scrolling is
slower on the older generation and fast on 3rd gen. This is now directly
measurable for the first time: the 2nd-gen unit is on the bench and the app
runs on it. Profile the launch path and the Home shelf scroll there, not on a
3rd gen, and treat the 2nd gen as the floor the app must clear.

## P2 — Fire TV: still unavailable, and this is the loudest complaint

> **Status 2026-09-12: no engineering remains.** Waiting on Amazon, and on the
> owner's promise to post in the thread the day it lands.

Four separate people, and the most persistent thread in the whole post:
**u/rseery** (three follow-ups, the last today: still incompatible after a
restart, and after trying the Silk browser), **u/CatalinaBigPaws** (twice,
could not find it at all, settled for Roku), **u/Tiny_Marionberry_839** (a red
X against a Fire Cube).

Root cause is known and fixed: Decision 115's minSdk floor, which hid the app
from every Fire OS 7 device. The corrected build reached 38 → 91 supported
devices and is submitted. **Owner: Amazon guarantees approval by the 15th, and
promised to reply in the thread when it goes live.**

**No engineering remains.** What remains is the promise: post back in the
thread the day it lands. Three people asked to be told, and one explicitly
offered to test.

## P3 — No way to sort a genre by year (iPhone / iPad) — **CLOSED 2026-09-12**

Shipped on every platform whose filtered grid lacked it: iOS and macOS in
1.42.8, Android in 1.42.47. `CatalogDB.Sort` / `BrowseSort` already carried
`.newest` and `.oldest` and both `browse()` implementations already took a sort,
so this was a missing CONTROL, never missing data — on all three. Android's
`SortMenu` is now shared between Browse and the filtered grid rather than
copied, so the two cannot drift.

The owner's reply in the thread ("I'll add it for iOS too in the next update")
is now true of the whole fleet.

### The original finding

**u/Severe_Citron6975**, on iPad: "Would be nice to have sort features like by
year browsing through film noir." **Owner: "I have that working on Apple TV
and a couple of the other platforms. I'll add it for iOS too in the next
update."**

Confirmed in code, and the specific gap is narrower than the reply assumed.
The main iOS Browse screen already offers Popular / Top Rated / A–Z / Newest /
Oldest. But tapping a genre tile pushes `FilteredGridView`
(`iOS/DiscoverSections_iOS.swift`), and **that view has no sort control at
all** — its toolbar shows only a title count. "Browsing through film noir" is
exactly that screen. The shared `CatalogDB.Sort` already has `.newest` and
`.oldest`, and `store.browse` already takes a sort, so this is a UI gap, not a
data one.

Worth fixing on every platform's filtered grid at once rather than iOS alone.

## P4 — Only the low-quality derivative is offered

**u/baxterfishsticks**, who had built something similar: on a Yojimbo upload
the iOS app offers only the 600 MB 480p `.mp4` derivative, not the 8 GB 1080p
original `.m4v`. Their suggestion is libvlc (VLCKit) for broad codec support.
**Owner engaged at length** and asked for their workflow; the reply notes that
Roku and most Google TV sticks cannot transcode, and floated enabling it for
downloads rather than streaming.

This is the most interesting feature request in the thread and the one most
likely to differentiate the app. It is also the one that most needs research
before code: a third-party player engine cuts against the project's
native-frameworks rule, and Decisions 021/031/034/072/077 are all built on
AVFoundation. The downloads-only idea is the promising seam, because Decision
099 already puts a real file on disk where codec support is the only question.

Scope it as research, not a fix.

## P5 — A film played, then reported unavailable (Poland) — **ANSWERED 2026-09-11**

**The cause is the captioned asset shape, and it was measured.** A film WITH a
published subtitle track played through an HLS wrapper that declares the whole
MP4 as ONE segment — and a segment is AVFoundation's atomic buffering unit, so
`preferredForwardBufferDuration = 300` is ignored and the entire film is pulled
into memory. `tools/test_captioned_buffer_growth.swift` plays both shapes of
this exact film, one per process:

    wrapper (iOS/macOS captioned)   4,195s buffered vs 300s asked (14x)
                                    1,368 MB footprint, still climbing at 90s
    resilient loader (tvOS)           193s buffered vs 300s asked
                                       55 MB footprint, flat

A phone's media pipeline is jetsammed long before a 129-minute feature ends,
and ~5 minutes is where a mobile link reaches that ceiling. Not geography, and
not bandwidth: the node sustains 28.5 MB/s here and held a 1.7 GB single
connection for 60 seconds without a cut.

Decision 070 measured this on Apple TV in August and fixed tvOS. The memory
note that recorded scoping iOS and macOS out said in as many words that
"low-RAM iPhones plausibly have the same bomb". They do. Both captioned
branches carried it, not just ours — iOS 27 was handed the PUBLISHED master
directly so the system could offer a generated track, and that playlist is the
same single segment (`#EXT-X-TARGETDURATION:7740`, one EXTINF). So did the
on-device-subtitles path, which writes the identical shape one directory over.

**Fixed**: a captioned film now streams through ResilientStreamLoader like every
other one and draws its published cues in the caption overlay. Decision 118.

The investigation below is left as written, including the hypothesis this
replaces — the buffer-drain theory was reasonable and wrong, and the reason it
was wrong is worth keeping: a 300-second buffer drains in exactly 300 seconds
only when throughput is ZERO, so "exactly five minutes" was never evidence of a
slow link.

---

### The investigation (superseded)


**u/CombinationLonely719**: *The Grapes of Wrath* starts, then says
unavailable; wonders if it is geographic. **Owner: "I'm on it"**, and asked
them to try the web build to isolate geo-blocking.

They answered: **a phone, and it plays for about five minutes and then
stops.** That detail settles it, and it is not geography.

**What was ruled out, by measurement.** The item is not access-restricted. The
file is the full 129.7 minutes, not truncated. It is faststart, so the index is
not at the far end. It needs only **2.25 Mbps**, and this connection pulled
**114 Mbps** from its node. Nothing about the media or the network explains a
five-minute ceiling.

**CORRECTION, 2026-09-11 — the premise below is WRONG for this film.**
I claimed Grapes of Wrath has no subtitle track, having read index 7 of the
WEB detail shard and found it null. The apps do not read that file. They read
`catalog.sqlite`, whose `subtitleHLS` for this item is
`https://archivewatch.org/subs/the-grapes-of-wrath-1940/master.m3u8` — a real
published track. Measured on the 2nd-generation Apple TV with
`AW_CAPTION_TRACE=1`: **"file subtitles loaded: 1192 cues, showing=true"**,
with the caption engine stopped and the trace reporting no speech models on
that chip. A null in one data plane says nothing about the other, and the
plane to check is the one the client actually reads.

So this film takes the CAPTIONED branch on iOS, not the plain one, and the
paragraph below does not explain what that viewer hit. **P5 is re-opened.**
The reconnect fix shipped in 1.42.9 stands on its own merits — one retry per
film was genuinely wrong — but it is no longer known to be this viewer's bug.

The rest of this section remains accurate for the ~84% of the catalogue that
genuinely carries no track, and is kept for that reason.

**What the plain path does.** archive.org has exactly ONE copy of this film —
a 2.19 GB original with no derivative at all. And on iOS and macOS, a film
with no published subtitle track plays on the **plain archive.org URL**,
deliberately:

    } else if let url = videoURL,
              SystemCaptions.prefersDirectPlayback(hasPublishedSubtitles: false) {
        pItem = AVPlayerItem(url: url)          // no resilient loader
        context.coordinator.fallbackVideoURL = url

That is a bare `AVPlayerItem` with none of Decisions 021 / 031 / 034 — no node
pinning, no byte-exact resume across a connection reset, no failover. It was
traded away so the system could offer generated captions on a film that carries
none. **Roughly 84% of the catalog has no subtitle track**, so this is the
normal path on a phone, not an edge case.

tvOS already refused this exact trade. Decision 096 declined the system-captions
pivot in part because "the plain path re-imports the Decision-021 disease the
owner personally watched — idle resets flushing the buffer, mid-film player
rebuilds." That reasoning was applied to tvOS and **never carried to iOS or
macOS**, which still run it.

**CORRECTION — the safety net DOES cover a hard failure.** An earlier reading
of this claimed it did not; that was wrong, and the wrong version is left here
struck through rather than quietly deleted. `watchForUnplayable`'s early return
on `.failed` is correct: it defers to a SECOND observer, armed a few lines
above whenever a fallback exists, which swaps to the resilient loader and
resumes at the current position. The plain branch does set
`fallbackVideoURL`, so it is armed.

What that observer gives is exactly ONE swap — `didFallback` guards it. So the
real sequence a viewer sees is: play on the plain URL, first failure swaps
silently to the resilient loader, second failure reports "unavailable". They
watched a film get two chances and lose both.

**So the live question is why the resilient loader also fails**, and the
likeliest answer is the one thing no loader can fix. The only copy is 2.25
Mbps sustained, iOS banks a 300-second buffer, and ~5 minutes is exactly one
buffer draining. That fits the report more tightly than a reset does: it
explains the specific figure, why it correlates with distance from the node,
and why reconnecting does not help. **If the viewer's sustained throughput
from a Canadian node is below 2.25 Mbps, no amount of resilience makes the
link faster.**

That is unproven, and it is the next thing to measure rather than assume.

**If it holds, the fix is not in the player at all** — it is the same axis as
P4. A film whose only copy is too fat for a viewer's connection needs a
smaller copy (archive.org made none for this item), or an honest message
naming bandwidth instead of a removed file, or an offer to download it and
watch later, which Decision 099 already built. The current message blames the
source for a condition the source may not have.

## P6 — Samsung TV

> **Status 2026-09-12: in flight, not submitted.** Decision 112 — US-only on
> Public Seller; certificate backed up; the `.wgt` builds.

**u/jablodg** asked. **Owner: "That's the next platform I'm working on…
probably out for release late next week."** Already in flight per Decision
112; US-only on Public Seller.

## P7 — Letterboxd / JustWatch integration

> **Status 2026-09-12: blocked externally.** Nothing to schedule.

**u/oxfordsplice** suggested it; they use Letterboxd and believe it sources
from JustWatch. **Owner** looked it up in-thread and found integration
requires individual approval by email, and has requested it. Blocked
externally. No work to schedule.

## P8 — "Do you actually vet the films?"

> **Status 2026-09-12: DONE and verified live.** `tools/build_vetting_page.py`
> runs in `deploy-pages.yml` and https://archivewatch.org/vetting/ answers 200.

**u/Acetylene** asked the sharpest question in the thread: whether this is a
curated library or another interface over whatever archive.org tagged as a
film, citing mislabelled items, poor quality and trailers in similar apps, and
saying that without human vetting it is hard to get excited.

This is a credibility issue rather than a bug, and the honest answer is strong:
the rights audit, the match verifier, the trailer detector and the playability
verifier are all real and all measured. The owner answered well, including the
admission that roughly 100 titles mislabelled as pre-1930 were found that very
day, and pointed at the public curation tool.

**The work this implies is presentational.** Someone evaluating the app cannot
see any of that machinery. A short, public account of how titles are vetted —
and what is deliberately excluded — would convert the project's biggest
invisible investment into the thing that distinguishes it from the apps
Acetylene is tired of.

## P9 — The OS floor excludes people

> **Status 2026-09-12: deliberate, unchanged.** Revisit only with data on how
> many people it turns away.

**u/Fit_Explorer_2566**: "iOS 26 required. I'll wait for iOS 27." The App
Store listing confirms a minimum of 26.0. This is a deliberate choice, but it
is worth knowing that it is visible to users and reads as a barrier. Revisit
only with data on how many people it actually turns away.

---

## What the thread says that is not a bug

Worth recording, because it is evidence about what the app is for.

- **Roku was the success story.** Found by search, installed easily, watched
  the same day, by several different people. The platform that took longest to
  ship is the one that landed best.
- **An educator** (u/SnowblindAlbino, a history professor) values the web build
  specifically for classroom streaming and for sharing with students on
  whatever hardware they have. The owner, a former teacher, offered to build
  for educators. That is a real, underserved audience the app already serves by
  accident.
- **People name the film they started with**, unprompted: *My Name Is Julia
  Ross*, *The Cabinet of Dr. Caligari*, *Lorna Doone*, *A Trip to the Moon*.
  The app icon got its own compliment. Discovery is working.

---

## The iOS 26 floor — measured 2026-09-11

> *"iOS 26 required. I'll wait for iOS 27. I won't have to wait too long."*
> — u/Fit_Explorer_2566

A user told us plainly that the deployment target keeps them out. It is worth
taking literally: `IPHONEOS_DEPLOYMENT_TARGET` and `TVOS_DEPLOYMENT_TARGET` are
both **26.0**, while CLAUDE.md still describes the minimum as "tvOS 17+". The
floor is drift, not a decision anyone recorded.

**What it would cost to lower it, measured rather than guessed.** Built the iOS
target at `IPHONEOS_DEPLOYMENT_TARGET=18.0` and counted what broke: **40 errors
in 3 source files**, all of them one of two features.

| Requires iOS 26 | Files | What it is |
|---|---|---|
| `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory` | `Services/AutoCaptions.swift`, `Services/LiveCaptions.swift` | the on-device live-caption engine (Decisions 058 / 068) |
| `AVVideoComposition.Configuration`, `init(applyingFiltersTo:applier:)`, `AVCIImageFilteringResult` | `Services/ClipExporter.swift`, `iOS/ClipStudioView_iOS.swift` | the Configuration-based video-composition API adopted 2026-06-16 |

**Nothing structural is in that list.** Browse, search, playback, the resilient
loader, the library, sync, offline downloads, Detail, Channels — none of it
needs 26. The floor is held up by two optional features.

**So it is an availability-gating job, not a rewrite.** Live captions gate to
26+ and fall back to published subtitles, which is exactly what Android and the
web already do. Clip Studio either gates to 26+, or restores the pre-26
composition API behind `if #available` — the code was migrated FROM it in June,
so that path is recoverable from git rather than inventable.

**NOT DONE, and deliberately.** How far down to reach is a product decision with
a real cost (two features become conditional, and every future change to them
has to hold both paths). This entry is the measurement so the decision can be
made on numbers instead of impressions.
