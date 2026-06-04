# App Store listing copy — Archive Watch (tvOS)

Paste-ready metadata for App Store Connect. Character limits noted; all
drafts are within them. Tone matches the product: a repertory cinema, not a
streaming funnel.

## Required URLs (now live on GitHub Pages)
- **Privacy Policy URL:** https://bhwilkoff.github.io/Archive-Watch/privacy.html
- **Support URL:** https://bhwilkoff.github.io/Archive-Watch/support.html
- **Marketing URL (optional):** https://bhwilkoff.github.io/Archive-Watch/

## Name (≤30)
`Archive Watch`

## Subtitle (≤30)
`A cinematheque for Apple TV`

## Promotional Text (≤170, editable anytime without review)
`Thousands of public-domain films, classic TV, silent cinema, and newsreels —
presented with the care of a great repertory house. Free. No ads. No account.`

## Keywords (≤100, comma-separated, no spaces after commas)
`public domain,classic movies,silent film,old tv,cinema,documentary,free movies,retro,film noir,archive`

## Description (≤4000)
```
Archive Watch turns the Internet Archive's vast public-domain moving-image
collection into a cinematheque you can wander from your couch — feature films,
classic television, newsreels, silent cinema, animation, and the strange,
wonderful world of ephemeral and industrial film.

Every title is presented with the dignity it deserves: real posters, cast,
synopses, and genres, so a 1920s silent and a 1950s sci-fi B-movie look as
considered as anything on a modern streaming service.

A REPERTORY HOUSE, NOT A FEED
- Hand-curated shelves alongside the most-watched titles from the Archive
- Browse by decade, genre, and collection
- Classic TV with proper series, seasons, and episodes
- Surprise Me, for when you'd rather be delighted than decide

BUILT FOR THE LIVING ROOM
- Native Apple TV experience with full-screen, focus-driven browsing
- Resume right where you left off
- Search with the Siri Remote or your voice
- Favorites and playlists in your Library
- 24-hour channels and background play for ambient viewing

FREE, AND RESPECTFUL OF YOU
- No subscription, no in-app purchases, no ads
- No account required to watch
- No tracking and no analytics — nothing about you is collected
- Optional Sign in with Apple syncs your favorites and progress across your
  household's Apple TVs using your own iCloud

All content is sourced from the public domain via the Internet Archive.
Metadata and artwork come from TMDb, Wikidata, Wikimedia Commons, and the
Library of Congress. This product uses the TMDb API but is not endorsed or
certified by TMDb.

If you'd rather wander a well-stocked repertory cinema than doomscroll a
recommendation feed, Archive Watch is for you.
```

## Category
- Primary: **Entertainment**
- Secondary (optional): Education

## Price
- **Free** (Decision 010). No IAP, no subscription.

## Age rating
Answer the questionnaire honestly. Archive Watch presents general historical /
public-domain film. With the default mature-content filter ON, the expected
rating is around **12+** (infrequent/mild mature themes possible in archival
content; "Unrestricted Web Access" = No, since browsing is confined to the
curated catalog). Adjust if the questionnaire's specifics differ.

## App Privacy (data collection questionnaire)
**Answer: Data Not Collected.**
- Archive Watch has no developer backend and no analytics; we never receive any
  user data.
- The submitted build ships with iCloud sync gated OFF
  (`CloudSync.entitlementConfigured = false`), so nothing is synced yet.
- When sync is enabled, Favorites/playlists/progress live in the user's **own
  iCloud private database**, which the developer cannot access — Apple does not
  require disclosing private-database data the developer can't read.
- Sign in with Apple's name/email stay in the user's iCloud and are never sent
  to a developer server.
- If review ever asks: declare only the Apple **User ID** as used for
  app functionality, **not linked** to the user's identity by us and **not used
  for tracking**.

## Export compliance
Already auto-answered in-binary: `ITSAppUsesNonExemptEncryption = false`
(HTTPS/TLS + Apple frameworks only = exempt). No per-upload prompt.

## Screenshots (still owner-action)
Apple TV: 3840×2160 or 1920×1080. Capture Home (hero + shelves), a Detail page,
the Player, Browse/Collections, and Library. From a real Apple TV or the
tvOS 26 simulator (`xcrun simctl io booted screenshot`).
