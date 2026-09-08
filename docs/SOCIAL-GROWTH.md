# Growing the accounts — per-platform posting, cadence, video, measurement

Companion to `docs/SOCIAL-PROGRAM.md` (what we post and why) and
`docs/SOCIAL-SETUP.md` (how the credentials work). This file is about
**reaching people**: shaping each post to its platform, choosing a cadence,
raising the video bar, and measuring what actually resonates.

Opened 2026-09-08 at the owner's request. Status of each workstream is marked
so a session picking this up knows what is done and what is next.

---

## 0. Where we started (measured, 2026-09-08)

`compose()` builds essentially the SAME post for all five platforms and
differs only by character limit. There are no per-platform hashtags, no alt
text, and no platform-native shaping. The programme posts once a day, always
at 16:10 UTC, and the format is whatever media the day produced.

The account has three existing posts, all Reels, all made by hand in the
macOS Creation Studio:

| caption | likes |
|---|---|
| `What can say... "I Love You." #supercut #oldmovies #publicdomain` | 2 |
| `And I think to myself, "What a wonderful world."` | 3 |
| `Have you ever felt "left behind"? #ArchiveWatch #PublicDomain #OldMovies #supercut` | 0 |

**The form is the lesson.** Each is built on a QUOTED PHRASE, stitched from
many films that all say it. The phrase is the hook, the caption, and the spine
of the edit. That is what the subtitle/word index makes possible, and it is a
much stronger idea than "a shot with motion in it", which is what the
automated teaser currently produces.

---

## 1. Per-platform post design  — RESEARCHED, NOT YET BUILT

Sources: Buffer's 2026 engagement study (52M posts), Later (6M posts),
Sked/Manychat/Sociali on the hashtag change, Kontentino on frequency.

**Instagram**
- **Hard 5-hashtag limit since December 2025.** More are ignored or hurt. Use
  3–5, in the CAPTION — placement in a first comment is algorithmically
  identical but the caption is indexed immediately, and Instagram now processes
  caption + alt text + hashtags as one package.
- Instagram indexes the **words in the caption, the alt text, and what is
  spoken and shown in a Reel**. So a caption written for a human searching
  ("1939 Bela Lugosi horror, free to watch") outperforms a hashtag wall.
- Alt text is a discovery signal, not just accessibility. We already write it.

**Bluesky**
- 300 characters, chronological feed, no algorithmic reach to court.
- 2–3 hashtags at most; a clean hook beats a tag wall.
- **Replies carry a measured ~5% engagement lift** — the platform rewards
  actually talking back, which is a posture, not a feature.

**Mastodon**
- Hashtags are the ONLY discovery mechanism — there is no algorithm and no
  recommendation feed. They matter MORE here than anywhere else, and 3–5 well
  chosen tags is normal rather than spammy.
- Alt text is culturally expected; posting media without it is genuinely
  frowned upon. We already always attach it.
- The character limit is per-instance and we already ask the server (500 is
  only the default; infosec.exchange answers 11,000).

**Threads**
- Conversational register; rewards a question or an opinion over an
  announcement.

**YouTube Shorts**
- Title and description are search text. The film's real facts (year,
  director, "public domain") are the query people actually type.

**Design rule that follows:** one `compose()` per platform, not one composer
with five limits. Same facts, native shape.

---

## 2. Cadence  — SHIPPED

The measured picture:

| | finding |
|---|---|
| Instagram | 3–4/wk is the floor for growth; **6–9/wk ≈ 3.7× the follower growth** of 1–2/wk; 10+/wk ≈ 5.5× |
| Threads | moving from 1/wk to **2–5/wk** gives a strong lift in views per post |
| Bluesky | chronological — volume is tolerated, recency is everything |
| all | **Tue–Thu, 9am–12pm** in the audience's timezone is the strongest general window |
| all | the **first hour decides**: 50 engaged followers beat 500 passive ones |

So "daily" is not one decision — it is five. **Per-platform cadence**, which is
the same native-design principle applied to scheduling:

| platform | posts/week | why |
|---|---|---|
| Instagram | 7 (1/day) | inside the 6–9 band where growth compounds |
| Bluesky | 14 (2/day) | chronological; a second post costs nothing and doubles the chance of being in-feed |
| Mastodon | 7 (1/day) | chronological, but the culture punishes volume |
| Threads | 4 | the measured sweet spot is 2–5 |
| YouTube | 7 (1/day) | Shorts have no feed fatigue |

Posting time moves from 16:10 UTC to **15:00 UTC (9am Denver / 11am ET)**,
inside the Tue–Thu 9–12 window for the US audience, with the second Bluesky
post at **23:00 UTC (5pm Denver)**.

**How it is built.** `CADENCE` in `tools/social_post.py` maps each platform to
the weekdays it posts on, and the unattended run skips a platform that is not
scheduled today, saying so. An explicit `--only` **overrides the calendar** —
that is the operator naming the platforms they mean, and the gate exists to
shape the run nobody is watching. The evening cron is distinguished by
`github.event.schedule` and passes `--only bluesky`; by then the ledger holds
the morning's film, so the selector cannot choose it again and the second post
is a different film.

Threads takes Tue/Wed/Thu (the three strongest weekdays) plus Sat; Facebook
takes Mon/Wed/Fri/Sun, spaced rather than clustered. `test_platform_shape.py`
asserts each band and — the guard that matters most — that **every platform
the poster can reach has a cadence entry**, because one added without it would
silently post every day, which is the undifferentiated scheduling this table
exists to end.

### Caption shape

The material is identical everywhere — SOCIAL-PROGRAM's one rule holds and no
platform gets a sentence invented for it. What changes is the **order**, which
is a real difference: in a feed that shows the first line and hides the rest,
the first line IS the post.

| platform | leads with | why |
|---|---|---|
| Bluesky | the quoted line | 300 characters, chronological, hook-driven |
| Instagram | the quoted line | the caption collapses after ~1 line |
| Threads | the quoted line | same collapse |
| Mastodon | the title + facts | descriptive culture; readers arrive by hashtag, not by scroll |
| YouTube | the link | the description is read by search, and ~150 characters show before "more" |
| Facebook | the title + facts | the link preview is doing the work |

Two details that are worth their code. **Instagram gets the bare domain**, not
the deep link: Instagram does not linkify captions, so a 60-character URL
nobody can tap is 60 characters of noise. And when the quote leads, the `—
Title` credit under it is **dropped**, because the facts line follows
immediately and already carries the title — crediting it twice cost a Bluesky
post 29 of its 300 characters to say the same thing again (258 → 229 on the
worked example).

**What was designed and then REFUSED: a question prompt on Threads.** The
research says end with a question; SOCIAL-PROGRAM §"never" says engagement
bait is out, and a question we write is a sentence with no source. The honest
version already exists and costs nothing: `pick_line` PREFERS an interrogative
line, so when the film asks a question, the post ends up asking it — in the
film's own words.

---

## 3. Video  — THE BIGGEST GAP

The owner: *"video posts should happen at least once a day... I'd like for new
posts to have polish just like those videos (even if we are only highlighting
one movie instead of many)."*

What `social_clip.py` already does well: cuts on a REAL shot boundary from
`clips.sqlite` (944,954 detected boundaries), draws only from the first act so
it cannot spoil an ending, skips titles and idents before 60s, rejects
blown-out or static shots by measuring luma and motion, runs `cropdetect` to
strip baked-in letterboxing, and NEVER reshapes the picture — a 4:3 film is
fitted whole over a blurred fill of itself (Decision 097).

What it lacks, against the reference Reels: **a spine**. It picks a shot that
moves. The hand-made videos pick a LINE, and the line is the whole idea.

**SHIPPED.** `tools/social_line.py` picks the line; `social_clip.py` builds
the cut around it; `social_post.adopt_clip_quote` makes the caption quote the
same words. The chain, in order:

1. `fetch_vtt` asks `/subs/<id>/en.vtt`. ~16% of the catalog answers; a 404 is
   the ordinary case and costs one printed line, never a failure.
2. `pick_line` takes the most quotable line of the first act — question, then
   exclamation, then statement; nearest eight words within a class. Every
   rejection rule (sound cues, two speakers, ALL CAPS, a trailing ellipsis, a
   lowercase opening that is the tail of the previous cue) came from a line
   the picker actually chose from a real published VTT.
3. `line_segment` cuts from `LEAD` (2.2s) before the line to `TAIL` (3.4s)
   after it, floor 11s, ceiling 22s — long enough to read three burned lines,
   inside every platform's ceiling. It probes two frames for luma and hands
   back to the shot-led cut if the line plays over black.
4. `build_filter` burns the line in Fraunces italic, centred, boxed at 50%
   black, just above the lower third, fading in on the beat it is spoken. The
   text is read from a FILE (`textfile=`), never inlined: drawtext's escaping
   cannot be trusted with a sentence somebody else wrote, and one stray colon
   would take the whole render down.
5. The clip **keeps its audio** — a quotable line nobody can hear is a
   caption, not a teaser — normalised with `loudnorm=I=-16:TP=-1.5:LRA=11`
   (archive.org transfers run from whisper to clipping, and a feed autoplays
   them beside professionally mastered video) and faded 0.6s in / 0.9s out.
   `-map 0:a?` so a film with no audio track still renders.
6. A sidecar `<clip>.json` names the line, and `adopt_clip_quote` REPLACES the
   caption's own randomly chosen line with it, so what the viewer hears, what
   is on the picture and what is in the caption are the same words. Two
   different lines from one film read as a template filled twice.

A shot-led teaser is unchanged: silent, 18s, no burned quote. It is the
fallback for a film with no subtitles, a line too long to burn (>3 lines at 24
columns), or a line that plays over a black frame.

**Verified on the glass**, not asserted: *The Werewolf of Washington* (1973)
cut to *"We've known Debbie, what, since the eighth grade?"* — 1080×1920, 11s,
AAC audio at -18.7 dB RMS, quote absent at t=0.5s and fully faded in by t=3s,
letterbox stripped (`crop=306:240:10:0`), the picture never reshaped.
`tools/test_clip_line.py` is 28/28 and was checked to FAIL (6 cases) against
the shot-only build.

**The remaining limit is the SUBTITLES, not the picker.** Where the published
track is machine transcription the lines themselves are poor — *House on
Haunted Hill* offers *"He/she will have eaten, drink and ghosts."* — and no
selector can rescue a sentence that was never said. Mitigations, in order:
prefer human tracks when the catalog records which is which, and fall back to
the shot-led teaser rather than burn nonsense on screen.

---

## 4. Engagement measurement  — SHIPPED (the instrument; the conclusions wait)

Posting blind is the current state. The design:

- `tools/social_metrics.py` reads every ledger row's permalink back through
  each platform's own API — Instagram `like_count`/`comments_count`/insights,
  Threads insights, Bluesky `likeCount`/`repostCount`/`replyCount`, Mastodon
  `favourites_count`/`reblogs_count`, YouTube `statistics.viewCount`.
- Results append to `social/metrics.json`, keyed by permalink, sampled at
  24h and 7d so early and settled numbers are both visible.
- A weekly report ranks by SLOT, by FORMAT (reel vs card), by hashtag set and
  by hour, so the question "what is resonating" has an answer with numbers.
- The selector then reads it: formats and slots that measurably do better get
  weighted up. That is the adjustment loop, and it must be *evidence in,
  weighting out* — never a hand-tuned guess dressed up as data.

**Built as `tools/social_metrics.py`**, run from the same daily workflow
(`--apply --report`) after the day's post, so it measures the EARLIER posts
and any corrected permalink rides out in the same ledger commit.

- Bluesky and Mastodon are read with **no token at all** — both are public
  APIs. Bluesky's handle is resolved to a DID first, because an `at://` URI
  addresses the repository and a handle can change while a DID cannot.
- Threads and Instagram use their own insights endpoints; YouTube reuses the
  poster's OAuth refresh token, since this channel has no public API key.
- Each post is sampled **once per window**, at thresholds of 20h and 144h. The
  thresholds sit BELOW the windows they name on purpose: a daily cron running
  at the same clock time arrives a few minutes early, and a "24h" reading
  taken at 48h is not the thing it claims to be.
- `--report` groups by platform, slot and **format** — which required adding
  `format` to the ledger, because the whole point of measuring is to learn
  whether a moving picture beats a card, and that cannot be asked of a ledger
  that did not record which went out.

**The honest caveat, now enforced in code:** `--report` refuses to rank a
bucket holding fewer than 10 posts and says so. With a handful of posts and
single-digit likes, any ranking is noise wearing a table's clothes, and
reading trends out of that is how a programme talks itself into nonsense. The
instrument runs; the conclusions wait.

---

## 5. Status

- [x] Research — per-platform practice and cadence (this document)
- [x] Per-platform hashtag policy — Instagram 5 (hard limit), Mastodon 5
      (its only discovery route; previously got ZERO), Bluesky/Threads 2,
      YouTube 3, most-specific tags bought first
- [x] Caption shape per platform — the quote leads on Bluesky/Instagram/
      Threads, the title leads on Mastodon, the link leads on YouTube,
      Instagram carries the bare domain
- [x] Per-platform cadence + the posting window moved to 15:00 UTC,
      plus a 23:00 UTC Bluesky-only second post
- [x] `tools/social_line.py` — picks the quotable line (the teaser's spine)
- [x] Cut the clip to that line, burn it on screen, keep the audio, and
      make the caption quote the same words (`adopt_clip_quote`)

**Line quality is the limit, not the picker.** These VTTs are largely
machine-transcribed from 1930s optical audio, so survivors can still be
nonsense — House on Haunted Hill yields "He/she will have eaten, drink and
ghosts." No syntactic rule catches that. Two honest mitigations, in order:
prefer films whose subtitles are HUMAN (`captions` provenance in the shard,
not ASR), and fall back to the shot-based teaser when no line clears the bar,
which is already the behaviour when a film has no subtitles at all.
- [x] `social_metrics.py` + `social/metrics.json` + the report, wired
      into the daily workflow
- [ ] Selector reads measured performance
