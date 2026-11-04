# Removal requests

How a request to remove something from Archive Watch is received, judged, recorded
and undone. Decision 175. Read this before changing any part of it.

**Status (2026-11-04)**: enforcement is live on `main`. The form, the private
case record and the file check are on branch `takedown-intake`, waiting on the
Worker deploy, which is the owner's: `tools/takedown_setup.sh`, then merge.

## The path

```
takedown.html form  ─┐
email to the agent  ─┼─> private case record (D1, worker/src/takedown.js)
Google notice       ─┘            │
                                  ▼  every 6 hours, or on dispatch
                       takedown-check.yml reads each named file
                                  │
              ┌───────────────────┴───────────────────┐
         remove                                     hold
   takedowns.json + spines                 a GitHub issue; the owner
   commit, publish-db                      replies `remove` or `keep`
```

A notice that arrives by email or from Google is entered by hand, with no
person's details unless they are needed:

```
python3 tools/takedown_cases.py open --source google --complete \
  --ref <Google reference id> --work "<claimed work>" --links <url>
```

## The rule (`takedown_check.verdict`)

| Situation | Outcome |
|---|---|
| We do not serve it | closed |
| Not a copyright notice (privacy, anything else) | held |
| A copyright notice missing a required element | held |
| Burned-in logo, or a soundtrack on a silent film | removed |
| The claim is only a word of a longer title | held |
| File read, nothing modern, public domain by age | held |
| Otherwise, a complete notice | removed |

A complete notice removes unless the evidence **contradicts** it. A file that
could not be read contradicts nothing, so it never holds a removal back. A run
removes at most five titles on its own; the rest are held, which bounds what a
false sworn form can do. A hold on a complete notice means we have not acted on
it, so it should not sit: that is the case worth a lawyer's eye.

The check runs for one request at a time. It is never a catalog scan.

## What can be removed

`shared/editorial/takedowns.json` takes three kinds of key (`tools/takedown_lib.py`):

| Key | Removes |
|---|---|
| `<item>` | the card, and every episode or file served from that item |
| `<item>@<token>` | one file of a whole-series item |
| `series:<slug>` | a show: card, spine and every episode |

Removal reaches the catalog, DB, search, share pages, sitemap, channels, feeds and
every app at the next publish. A viewer's own download on a phone stays until they
delete it. Two kinds of content are not in that list and go by hand: a poster or
image (`image_rejects.json`) and a subtitle file (`subtitle_denylist.json`). A
social post already published is removed on its platform.

To restore something, delete its line and republish; a stripped episode comes
back at the next tv-canonical rebuild, a stripped spine the same way.

## Privacy

The repository and its Actions logs are public. The rule is structural:

- `takedowns.json` holds a date and a case number. Never a person or company.
- A requester's details live in `takedown_cases` on D1 and nowhere else. No IP
  address is stored. The hourly sweep erases details three years after a case
  closes (the copyright limitation period) and keeps the outcome.
- The check's list route returns no personal column. Its log and issues print
  a case number, an archive id and a fixed sentence from `REASONS`, never a
  requester's words, including the name of the work.
- `python3 tools/takedown_cases.py show <case>` is the owner's read. Never run it
  in CI. The token is in `~/.config/archivewatch/takedown.env`.

## Answering a Google notice

Google's notice removes a page from Search; it does not ask us to do anything.
Read the file before deciding. If the claim looks wrong, ask the sender to
withdraw it first. A counter notice is a sworn statement that hands the sender
your name and address and accepts federal jurisdiction, and Google only "may"
reinstate, so it is the last resort, and worth a lawyer.

## The first case

2026-11-04, two notices from Blue Efficience. `Madame Dubarry` was an ARTE
broadcast of the 1919 film: removed, and the two clean silent copies stayed.
`Home Movie: 97390: Unidentified` is a family home movie in the Prelinger
collection, claimed as "UNIDENTIFIED": kept.
