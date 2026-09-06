# The Social Program — Archive Watch

**Binding.** Every automated post traces to a rule here. This document is the
editorial policy; `tools/social_*.py` is only its implementation. When a post
feels wrong, fix this document first, then the code.

---

## 1. Why this exists, and the one rule that governs it

Archive Watch holds ~26,700 public-domain films that almost nobody knows are
free to watch. The catalog is not a content farm to be strip-mined for
engagement; it is a repertory cinema, and this program is its **marquee** — the
board outside the theatre that says what is showing tonight and why it is worth
your evening.

**The one rule: every word in a post is sourced. Nothing is invented.**

A post may contain only:

- facts the catalog measured (year, director, runtime, genre, colour, rating
  with its vote count),
- the film's own synopsis, as published,
- a real archive.org viewer's review, quoted verbatim and attributed to the
  handle that wrote it,
- the film's own tagline, as printed on its poster,
- our own plain sentence about where to watch it.

A post may never contain: a superlative we cannot source, a fabricated
"fact", a manufactured urgency ("only free for 24 hours" — it is public
domain, it is free forever), an invented quote, or a claim about a film
nobody here has watched. This is the same discipline the pipeline already
runs on: measure, then state. It is also the only honest way to promote an
archive — the films are the argument.

This mirrors CLAUDE.md's learning-orientation test. A post should leave a
reader knowing something true about a film they did not know existed. If a
post's only content is "watch this now", it fails and does not ship.

---

## 2. The four-question test, applied

| Question | How the program answers it |
|---|---|
| **Deepens understanding?** | Every post carries a real fact: the year, the director, who shot it, why it entered the public domain, what a viewer in 2019 made of it. The reader learns something about film history even if they never tap. |
| **Invites participation?** | The loudest voice in the post is another viewer's, quoted and credited. The catalog's reviews are a public conversation; the program joins it rather than talking over it. |
| **Supports agency?** | Links go to the film's own page, where the viewer chooses. No autoplay funnel, no "start your free trial", no account wall — there is no account. |
| **Clarity over cleverness?** | One film, one picture, one paragraph, one link. No threads engineered for the algorithm, no rage-bait framing of a 1940s picture. |

**Explicitly refused**, and the reasons:

- **Trend-chasing.** Posting a silent comedy against whatever is trending
  today makes the archive a costume. The films set the calendar.
- **Engagement bait.** "Which is better, comment below" harvests replies and
  teaches nobody anything.
- **AI-written copy.** Not because a model writes badly, but because a
  sentence with no source cannot be checked, and this project's whole method
  is that claims are checkable. The composer assembles sourced fragments; it
  does not generate prose.
- **Posting films we have not verified play.** Every candidate must pass the
  same playability and rights gates the apps use. Promoting a dead link is
  worse than posting nothing.
- **Volume for its own sake.** See §4.

---

## 3. The programme — what goes out, and when

A repertory cinema publishes a *programme*, not a feed. Each slot below is an
editorial format with its own source material and its own selection rule.

| Slot | Cadence | What it is | Source of the copy |
|---|---|---|---|
| **Now Showing** | daily | One film, its poster, one sourced paragraph, the link. The backbone. | synopsis + measured facts |
| **What a viewer said** | 2×/week | A film introduced by a real archive.org review, quoted and attributed. | `reviews[]` (verbatim) |
| **On this day** | when it fires | A film released on today's date, N years ago. Never invented — only fires on a real, dated match. | `releaseDate` + facts |
| **Public Domain Day** | 1 January | The year's new arrivals — the films that entered the public domain today. | the PD-day query the apps already run |
| **The double bill** | weekly | Two films that genuinely share something measured: a director, a year, a cinematographer. | catalog joins only |
| **From the vaults** | weekly | An ephemeral/industrial/newsreel item — the strange corners nobody browses to. | synopsis + collection |
| **One line** | weekly | A verbatim line of dialogue from the film's own subtitle track. | `captions[]` (the VTT itself) |

**Never more than one post per platform per day.** A second post in a day is
how a marquee becomes a billboard.

### 3b. A line from the film

The subtitle track is the only source that quotes the **work** rather than
anyone's opinion of it, which makes it the strongest hook the programme has
and the strictest to handle:

- **Verbatim, and whole.** A sentence is routinely split across three cues
  ("this tribunal of justice" / "hereby sentences you," / "the Crimson
  Executioner,"), so quoting one cue quotes a fragment. Cues are joined until
  a terminator.
- **Dialogue only.** Sound effects "(ominous music)", speaker labels
  "[Man Voiceover]" and music bars are not dialogue and break the sentence.
- **From the first 60%**, for the same reason the teaser takes the first act:
  a line from the last reel can give away an ending.
- **"A line from the film", never "the best line".** We cannot measure best,
  so we do not claim it. The choice is deterministic per film, not curated.

About 14% of the catalog publishes a subtitle track, which is plenty for a
weekly slot and not enough for a daily one.

### 3a. The teaser (video)

A clip is the most honest promotion there is: an actual scene, not a claim
about one. Four rules, each of which was a defect first:

1. **From the first two-thirds, never the ending.** The cut is taken around
   35% of the runtime. A teaser cannot spoil a film it never reaches.
2. **Never a title card.** The scene is found by running shot detection in a
   60-second window and then MEASURING MOTION — position alone is not enough.
   Hercules Unchained's credits run past four minutes and move (a ship sails
   behind them), so a naive "skip the first 60 s" rule cut the credit roll.
3. **Never reshape the picture** (Decision 097). A 4:3 film is fitted whole
   into 9:16 over a blurred fill of itself; baked-in letterboxing is detected
   and removed first, or the picture renders as a strip.
4. **It must work muted**, because that is how it will be seen: the title,
   year and address are burned into a lower third.
5. **It must be LEGIBLE on a phone in daylight.** Brightness is measured and
   gated (mean luma 42-225); the first Magic Sword cut was a dim cave that
   passed the motion test and read as a black rectangle in the feed. When a
   window fails, the next one is tried — 35%, 50%, 25%, 60% of the runtime —
   and a film with no legible, moving scene simply gets no teaser that day.

The shot index (`clips.sqlite`, Decision 042 — 944,954 detected shots across
32,573 films) is the FALLBACK, not the primary: it only analyses each film's
opening ~300 seconds, which for a feature is titles and setup. It is the
right source for a short or a cartoon, where 300 seconds is most of the film.

---

## 4. Cadence, and why it is deliberately slow

The platforms permit far more than we use: Threads allows 250 posts a day,
Bluesky has no practical ceiling. That is a limit, not a target.

**One post per platform per day, at one time per platform.** The reasons:

1. **The catalog is not the constraint.** With 13,500 professionally
   presented titles, one a day is a 37-year programme. There is no need to
   rush, and no excuse for reposting a film within a year.
2. **A daily marquee reads as a person; six posts a day reads as a bot**,
   and the accounts that read as bots are the accounts that get muted. The
   whole value of this program is that it does not feel automated.
3. **A failed day costs nothing.** If the run fails, tomorrow's post is the
   same quality. Nothing here is time-critical except the two dated slots.

Posting times default to when each platform's audience is actually awake, in
one timezone (America/Denver, the owner's). They are configuration, not
doctrine: `social/program.json`.

---

## 5. Where a post sends people

**The native apps first.** `https://archivewatch.org/item/<archiveID>` is the
canonical share URL for every platform, and it is doing more work than it
looks like:

- On **iOS** it is a Universal Link: with the app installed it opens the
  film's Detail page directly (verified on device, 2026-09-06).
- On **Android** it is a verified App Link into the same screen (verified on
  the Pixel 8a the same day).
- Everywhere else it is the web viewer, which plays the film in the browser.

So one URL is simultaneously the app deep link and the web fallback. **Never
post a bare archive.org link** — it sends a viewer to a page with no
programme around it, and it is the one link that cannot open the app.

---

## 6. Platform reality, measured (September 2026)

The order below is the order the owner should connect them in — easiest and
most valuable first.

| Platform | What it takes to connect | Review needed | Media |
|---|---|---|---|
| **Bluesky** | an app password, pasted | **none** | image ≤1 MB, ≤4; video ≤100 MB/3 min |
| **Threads** | Meta app + long-lived token | app review for production | image at a **public URL**; 250/day |
| **Instagram** | Business/Creator account, Meta app | `instagram_business_content_publish`, 2–4 weeks | public URL; Reels 9:16, 5–90 s |
| **Facebook Page** | Page access token, Meta app | `pages_manage_posts` + business verification | `/{page-id}/photos` |
| **YouTube** | Google Cloud project, OAuth refresh token | none for own channel | Shorts ≤60 s vertical |
| **TikTok** | developer app + **content posting audit** | audit, or posts are **private-only** | video |

Two consequences the design takes seriously:

- **Bluesky is the only platform that works the day you paste a credential.**
  It is therefore the reference implementation and the proving ground.
- **Meta fetches media from a public URL**, so generated cards must be
  published somewhere public before the post is made. They go to a GitHub
  Release (Decision 018's rule: generated artifacts never bloat git).

---

## 7. The ledger, and never repeating

`social/posted.json` records every post: the film, the slot, the platform,
the timestamp, and the URL the platform returned. It is the memory that makes
the programme a programme:

- **No film repeats within 365 days**, on any platform.
- **No review is quoted twice**, ever.
- A post that fails on one platform and succeeds on another is recorded per
  platform, so a retry does not double-post where it already landed.

The ledger is committed, small (one line per post), and is the only piece of
this system that must never be lost.

---

## 7a. Variety is a rule, not an accident

A ten-day rehearsal came out **8 of 10 feature films** — every card carrying
the same eyebrow. Each film was individually well chosen; the WEEK was one
note, which is the failure only a batch can show.

The cause was arithmetic, not editorial: features are the rows that carry
IMDb votes, so any popularity floor selects them. Two rules correct it:

- the vote floor is **lower for the kinds that rarely carry votes at all** (a
  1933 Fleischer cartoon has none), and
- a kind appearing **three or more times in the last six posts** sorts behind
  one that has not.

Both are soft. Fully rotating the kinds over-corrected the other way — a
rehearsal then produced just 2 features in 10 days, which undersells a
catalog whose main draw is movies. Measured over 14 days, the programme now
runs 5 features, 5 silents, 2 cartoons and 2 shorts across the 1900s to the
1950s. **Run `tools/social_rehearse.py` before changing any selection rule**;
the report warns when one kind or one decade takes more than 60% of a run.

---

## 8. The ship gate

Before any change to the program ships, all of these must hold:

1. Every sentence in a rendered post traces to a catalog field or a quoted
   review. Run `tools/social_select.py --explain` — it prints the source of
   every fragment.
2. The film passes the app's own gates: playable, rights-cleared, not adult,
   professional artwork.
3. The card renders legibly at thumbnail size (the size it is actually seen).
4. A platform with no credentials configured is skipped silently, never an
   error.
5. The ledger is updated only after the platform confirms the post.
