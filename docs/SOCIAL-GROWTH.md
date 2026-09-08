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

## 2. Cadence  — DECIDED, NOT YET BUILT

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

Posting time moves from 16:10 UTC to **~15:00 UTC (9am Denver / 11am ET)**,
inside the Tue–Thu 9–12 window for the US audience, with the second Bluesky
post in the early evening.

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

**The design:** use the subtitle index the same way the supercuts do, but for
one film — find a strong line of dialogue in the first act, cut the clip to
that line's timing, burn the line on screen, and make it the caption hook. The
word-level index already exists (484,848 word timings) and
`tools/fix_subtitle_sync.py` proves the alignment is trustworthy.

Also to fix: the clip currently has no audio ducking, no fade in/out, and the
title card competes with the burned line for the same lower third.

---

## 4. Engagement measurement  — DESIGNED, NOT YET BUILT

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

**The honest caveat to record now:** with 3 posts and 5 likes total, nothing
will be statistically meaningful for weeks. The instrument comes first; the
conclusions wait until there is something to conclude from. Reading trends
out of single-digit counts is how a programme talks itself into nonsense.

---

## 5. Status

- [x] Research — per-platform practice and cadence (this document)
- [x] Per-platform hashtag policy — Instagram 5 (hard limit), Mastodon 5
      (its only discovery route; previously got ZERO), Bluesky/Threads 2,
      YouTube 3, most-specific tags bought first
- [ ] Caption SEO shaping per platform (hook-first on Bluesky, question on Threads)
- [ ] Per-platform cadence + move the posting window to 15:00 UTC
- [x] `tools/social_line.py` — picks the quotable line (the teaser's spine)
- [ ] Cut the clip to that line, burn it on screen, use it as the caption hook

**Line quality is the limit, not the picker.** These VTTs are largely
machine-transcribed from 1930s optical audio, so survivors can still be
nonsense — House on Haunted Hill yields "He/she will have eaten, drink and
ghosts." No syntactic rule catches that. Two honest mitigations, in order:
prefer films whose subtitles are HUMAN (`captions` provenance in the shard,
not ASR), and fall back to the shot-based teaser when no line clears the bar,
which is already the behaviour when a film has no subtitles at all.
- [ ] `social_metrics.py` + `social/metrics.json` + weekly report
- [ ] Selector reads measured performance
