# Radio catalog — decisions

Append-only, lead-with-WHY (the Archive Watch format). This pipeline will move to
the radio app's own repository when it is created; these entries move with it.

## 001 — Unclaimed broadcasts are kept and removed on request; nothing is kept on a paid licence
*Date: 2026-10-17*

A pre-1972 radio recording with no claim a reader can open — no Copyright Office
schedule, no named claimant with a source, no take-down, no renewed script or
adapted film, not post-1972, not of non-US origin — is `keep_unclaimed`: shown,
and hidden the moment a claim appears. No recording is kept on a SoundExchange
statutory licence or any other paid licence.

**Why**: the owner, 2026-10-17: *"I like the idea of moving to a 'take down
request' model for this, but a licensed model at $1000 per year is definitely not
in keeping with our regular process."* Federal law protects nearly every pre-1972
recording until 2067 (17 U.S.C. §1401), so "public domain by age" frees almost no
radio drama; but §1401(f)(5) denies statutory damages and fees to an owner who
filed no schedule, and §1401(f)(3) applies the DMCA safe harbor — the reason
archive.org and RadioEchoes run on notice and takedown
(`docs/research/radio/02-rights.md` §12).

**How to apply**: never label `keep_unclaimed` "public domain" in any client —
its rights line says no claim is known and that it is removed on request
(Archive Watch Decision 153's lesson). A take-down goes in
`editorial/takedowns.json` and takes effect at the next build. Every new claim
source becomes a hide bucket that runs BEFORE the rescues, with a test and a
control. Register a DMCA agent before launch.

## 002 — An uploader's licence tag neither admits nor hides a recording
*Date: 2026-10-17*

The archive.org `licenseurl` on an OTR item is recorded as provenance and plays
no part in the rights state. OTRR's CC BY-NC-ND sets are kept like any unclaimed
recording, and OTRR is credited (the licence's attribution term; the app is
noncommercial and makes no derivative copy — loudness gain is applied at
playback).

**Why**: measured 2026-10-17, ~1,000 OTR items carry CC BY-NC-ND/ND tags and
~1,490 PD marks on 1940s network broadcasts that uploaders could not own
(02-rights §8). As a rescue they are an uploader's word (Archive Watch Decision
140); as a hide they would remove OTRR's sets, the best-dated copies in the
corpus, on a claim over the compilation that the app already honors. This
departs from 02-rights §10's proposed `rec_uploader_cannot_license` hide, which
was written before Decision 001.
