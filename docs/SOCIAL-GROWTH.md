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

### What a post SPENDS its space on

Owner, on a Bluesky post: *"The post is almost meaningless and a lot of it is
just meta-data about the movie."* It read:

> "That really IS Arabic for spinach. 5 stars to Kneitel and…"
> — HeatherFerreira, archive.org
>
> Private Eye Popeye (1954) · Animation · 6 min · dir. Seymour Kneitel
>
> Published in 1954, in the public domain in the United States.

The funny half of a real sentence was destroyed to make room for "Animation ·
6 min", because the trimmer took from the BODY and never from the facts —
exactly the wrong priority. Rebuilt around three rules:

1. **The film's name and the link are RESERVED** before anything competes for
   the space. A post that quotes a viewer beautifully and never says which
   film they watched has failed at the only two jobs it definitely has — and
   that is what a naive "add while it fits" pass produced (asserted by test,
   negative-controlled).
2. **Parts are added in a per-platform order while they fit**, and the one
   left out is the least valuable, never the most. `facts` (kind, runtime,
   director) appears only where space is not scarce — and leads on YouTube,
   where the description is read by search.
3. **A quotation is cut at a SENTENCE end**, never mid-clause, and a review's
   attribution is part of the unit: only the quote inside it is shortened,
   because SOCIAL-PROGRAM allows a viewer's words only "quoted verbatim and
   attributed to the handle that wrote it".

**The selector was ranking reviews by length, MAXIMISED** — it deliberately
chose the longest one, which on 300 characters can only be truncated. It now
prefers, in order: a review carrying a **star rating**, one that starts like a
sentence, one whose **first sentence** fits (that is what a trim keeps), then
the longest that fits whole.

Preferring short bodies immediately surfaced a different junk population, and
two live examples went straight into `test_review_filter.py`: *"Hey, I am
searching desperately for a copy of the film... Best,"* and *"We'd like
permission to use a clip of this movie on our television programme."* The
second passed every existing pattern because they expected "would" rather than
"we'd", and "email ME" rather than "e-mailed YOU" — so the filter now matches
the SUBJECT (`permission`, `rights to use`, `looking for a copy`) rather than
one phrasing of it, and a body that signs off (`Best,` `Thanks,`) is a letter,
not a review. The star preference is the structural half of the same fix:
people who write to an uploader leave no rating.

The result, same film, same day:

> "Before watching this film, I had not realised film-making was so advanced
> by 1918."
> — terracesider, archive.org
>
> Tarzan of the Apes (1918)

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
5. Everything burned lives in the **upper band**. Reels, Shorts and TikTok
   draw their own chrome over the video — account name, caption and action
   rail across the bottom, a header across the top — and the owner watched a
   Reel with the platform's account line printed straight through our title.
   `TOP_SAFE`/`BOTTOM_SAFE` (250 / 480 on a 1080×1920 frame, the union of the
   published Reels and TikTok creative specs) bound it, and the test asserts
   no drawn element crosses either.
6. **Every** teaser keeps its audio — not only the line-led ones. A silent
   Short does not read as restraint, it reads as broken, and one went up that
   way. Normalised — a quotable line nobody can hear is a
   with `loudnorm=I=-16:TP=-1.5:LRA=11` (archive.org transfers run from
   whisper to clipping, and a feed autoplays them beside professionally
   mastered video) and faded 0.6s in / 0.9s out. `-map 0:a?` so a film with a
   genuinely silent transfer still renders.
7. A sidecar `<clip>.json` names the line, and `adopt_clip_quote` REPLACES the
   caption's own randomly chosen line with it, so what the viewer hears, what
   is on the picture and what is in the caption are the same words. Two
   different lines from one film read as a template filled twice.

**The line must be HEARD before it is burned (2026-09-08).** Owner, on a
teaser whose caption was not the dialogue: *"You need to actually check the
audio for the words before committing to putting the captions on screen."*

`tools/social_hear.py` cuts the cue's window out of the film's audio over
HTTP, transcribes it, and scores how many of the cue's CONTENT words are
actually heard. `social_clip` tries up to three candidate lines and burns none
of them unless one clears 0.5.

The threshold is measured, not chosen. Across three films:

| film | cue vs its own audio |
|---|---|
| Impact (1949) | **1.0, 1.0, 1.0, 0.625** — a correctly timed track |
| His Girl Friday (1940) | 0.0 × 4 |
| The Vampire Bat (1933) | 0.0 × 4 |
| The Werewolf of Washington (1973) | 0.0 × 8 |

The gap between a right pairing and a wrong one is the whole range, so 0.5 is
not a tuning parameter and must not be lowered to rescue more lines.

Two things this turned up that are bigger than the teaser. **The Werewolf of
Washington is published with *An American Werewolf in London*'s subtitles** —
its cues say "East Proctor" and "dueling scars" while the audio says
"everybody in Washington". And **His Girl Friday and The Vampire Bat, both
recorded in the log as corrected at source, still score 0.0**, so that
correction did not reach what Pages serves. Those tracks are being handed to
viewers in every app, which matters more than a caption on a Reel.

VAD is not enough for this, which is why `sync_subtitles_audio.py`'s ffsubsync
could not be reused: it detects that somebody is talking, and "somebody is
talking" is exactly what a wrong caption sits on top of. Decision 039b
abandoned Whisper for GENERATING captions because it hallucinates; verifying
is the opposite problem, because a hallucinated transcript simply fails to
match and the teaser falls back to a shot cut.

"Could not check" is kept distinct from "checked and failed" — no audio, no
recogniser, or too few content words all return `None`, and `None` never
burns. Otherwise the gate would disappear silently the day a dependency went
missing.

### The frame is banded, not layered

Owner: *"we shouldn't overlay the captions text on the square video, but
rather we should put it above or below to not block the content."*

Title band 250–510, film box 530–1160, quote band 1180–1440. The film is
fitted INSIDE its box at its own aspect (`force_original_aspect_ratio=
decrease` bounds both dimensions), so a 4:3 film sits a little narrower than
the frame and nothing is ever cropped or covered. With no quote the picture
takes the room back (530–1440).

Full width was tried first and cannot work: a 4:3 film fitted to 1080 wide is
810 tall, leaving 75 px under it inside the safe area — a third of one line of
type.

A shot-led teaser is 18s with no burned quote — but it now carries sound
like every other one. It is the
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
- [ ] Selector reads measured performance (waits for MIN_N; §4)

---

## 6. Verified live, 2026-09-08

Every platform has now carried a real post, checked by reading it back off the
platform's own API rather than trusting the run's report:

| platform | post | verified |
|---|---|---|
| Mastodon | The Golden Fish (1959) | status live, video attached with alt text, paragraphs as composed |
| YouTube | same | oEmbed resolves — "The Golden Fish (1959) — free to watch", Archive Watch channel |
| Threads | same | container published, media id returned |
| Instagram | same (Reel) | container published, media id returned |
| Bluesky | The Lion Tamer (1934) | post live with the CARD, alt text, and the quote leading — the new shape, in production |
| Facebook | — | no credentials; the cadence gate also has it off today |

**Two defects the live run found, both fixed in the same session:**

1. **Bluesky refuses video from an account whose email is unconfirmed** —
   `HTTP 401 unconfirmed_email` — and the whole platform was being skipped for
   it, when the same post as an image goes out fine. The upload now falls back
   to the card. **OWNER ACTION: confirm the email on the Bluesky account and
   Bluesky starts carrying the teaser instead of the card.** Nothing else is
   blocked on it.
2. **A published Instagram media id is not its shortcode**, so the ledger held
   `instagram.com/p/<id>` — a URL shaped like a permalink that goes nowhere,
   in the ledger AND in the public feed. `meta_permalink` now asks the API,
   and `social_metrics` corrects any row already written when it samples it.

### Taking a post down (2026-09-08)

Four teasers went out silent before the audio rule was universal. `--apply` on
`tools/social_delete.py` removed what it could and named the rest exactly:

| platform | delete over the API |
|---|---|
| Bluesky | ✅ `com.atproto.repo.deleteRecord` |
| Mastodon | ✅ `DELETE /api/v1/statuses/:id` |
| Threads | ❌ `HTTP 500 {"code":10,"message":"Application does not have permission for this action"}` — the app has no delete permission |
| Instagram | ❌ the Content Publishing API creates and publishes; there is no delete |
| YouTube | ❌ `403` — `videos.delete` needs `youtube.force-ssl`, and this project mints the narrower `youtube.upload` on purpose |

So three of five are a manual step, and the tool says where to click rather
than reporting a failure to re-investigate tomorrow. `--forget` then drops
those ledger rows, because a row left behind retires its film for a year for
a post nobody can see.

**A Mastodon attachment types itself.** The silent upload came back as
`gifv`; the one with sound came back as `video`. That is a free check on
whether a teaser really carried audio, from a public API with no token.

**Checked and found NOT to be a defect:** a Bluesky post reading
`"Glad this is available.Hot Dog! ..."`. That is the reviewer's own typing,
fetched from archive.org and confirmed character-for-character. Quoting it
verbatim is the rule; "fixing" a source's words would break it.
