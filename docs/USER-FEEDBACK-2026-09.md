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

## P0 — Archive Watch will not launch on Apple TV, tvOS 26.3

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

**u/hondo77777**, Apple TV 4K 2nd gen: "very, very s l o w", while liking the
interface otherwise. **Owner: "Clearly needs some optimization. Look for the
update early next week."**

Independently corroborated by the owner's own observation that scrolling is
slower on the older generation and fast on 3rd gen. This is now directly
measurable for the first time: the 2nd-gen unit is on the bench and the app
runs on it. Profile the launch path and the Home shelf scroll there, not on a
3rd gen, and treat the 2nd gen as the floor the app must clear.

## P2 — Fire TV: still unavailable, and this is the loudest complaint

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

## P3 — No way to sort a genre by year (iPhone / iPad)

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

## P5 — A film played, then reported unavailable (Poland)

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

**u/jablodg** asked. **Owner: "That's the next platform I'm working on…
probably out for release late next week."** Already in flight per Decision
112; US-only on Public Seller.

## P7 — Letterboxd / JustWatch integration

**u/oxfordsplice** suggested it; they use Letterboxd and believe it sources
from JustWatch. **Owner** looked it up in-thread and found integration
requires individual approval by email, and has requested it. Blocked
externally. No work to schedule.

## P8 — "Do you actually vet the films?"

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
