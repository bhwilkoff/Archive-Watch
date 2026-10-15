# Roblox: the publishing and policy side, for Archive Watch

Researched 2026-10-15. These are primary Roblox pages (create.roblox.com, about.roblox.com, devforum.roblox.com staff posts) unless a source is marked secondary. Claims I could not confirm on a primary page are marked **UNVERIFIED**. Two help-center pages (en.help.roblox.com) returned HTTP 403 to the fetcher, so their content comes from search snippets and is marked where it matters.

---

## 0. Headline findings (read these first)

1. **Showing a feature film on Roblox is very expensive, and it is limited by how video works on the platform, not by policy.** Video plays only from **uploaded assets**. You cannot stream an external URL such as archive.org. Each upload costs **2,000 Robux**, can be at most **5 minutes** long and **3.75 GB**, and the uploader must be **13+ and ID-verified**. At most **two videos can play at once**. A 90-minute film is about 18 uploads, or about 36,000 Robux. An upload that moderation rejects is still charged (user reports). https://create.roblox.com/docs/ui/video-frames
2. **You cannot tell players "also on archivewatch.org" inside the experience.** The Community Standards say: "You may not link to, share, or display URLs of any external websites or services except by using the Social Links feature … Any other efforts to direct users off of Roblox to an external website or service are prohibited." In January 2026 Roblox also said in-experience social links are gone (`PolicyService:GetExternalLinkReference` is being sunset), and creators may only say something like "Links on our game's page". https://about.roblox.com/community-standards · https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
3. **There is a hidden conflict with store thumbnails.** Thumbnail and video-thumbnail rules forbid "External content: real-life footage of people or places, or other content outside the game" and "music with lyrics" or narration. A store thumbnail made of raw film stills could be rejected. The thumbnail should show the **Roblox theater space** with film on its screens. This last point is my inference: the rules don't address in-game screens showing film. https://create.roblox.com/docs/production/promotion/thumbnails
4. **Publishing is free, but reaching under-16 players is not automatic.** Releasing to age-checked 16+ users needs only an age-checked owner account. Reaching **Roblox Kids (5–8) and Select (9–15)** needs ID verification, two-factor authentication (2FA), a refundable **1,000 Robux per-game fee** (or a Plus or Premium subscription held for 2+ months), a Minimal, Mild or Moderate rating, and an **evaluation of 250 unique plays from "highly engaged" players in 60 days**. https://create.roblox.com/docs/production/publishing/kids-and-select
5. **The catalog's content profile points to a Moderate label (9+) or a 16+ "Content May Vary" release.** 1930s gunplay is "realistic-looking, non-graphic" violence (Moderate). Any heavy realistic blood would make it Restricted (18+). Propaganda and racist cartoons collide with the Discrimination, Extremism and Sensitive Issues rules. That catalog needs a far narrower **Roblox-specific allowlist** than the apps use.

---

## 1. Publishing process

### Ownership: personal account or Community (formerly "Group")
- Roblox renamed Groups to **Communities** (announced at RDC 2024, rolled out 2025). APIs and docs still say "group" in places. https://devforum.roblox.com/t/documentation-terminology-update-group-should-be-community-%F0%9F%A4%AE%F0%9F%90%81/3926078 (secondary: https://beebom.com/roblox-introduces-party-features-communities-rdc-2024/)
- Publishing doesn't require Community ownership. If a Community owns the experience, members' rights to edit, playtest and publish come from their **role permissions**. https://create.roblox.com/docs/production/publishing/publishing-experiences-and-places
- Community ownership is the right shape for an organization: the experience outlives any one person's account, and roles can be shared. The catch is that verification follows **people**, not the Community. For Creator Rewards on a Community-owned game, "a member with permission to configure group revenue" must be ID-verified. https://create.roblox.com/docs/creator-rewards The Kids and Select fee could only be paid by "the owner or group owner" as of May 2026. https://devforum.roblox.com/t/alternate-publishing-requirements-for-roblox-kids-and-select/4630944
- Team Create (collaborative editing in Studio) has required an age check since March 2026. https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101

### Steps (current Creator Hub doc)
1. **Publish (private):** in Studio, File > Publish, then fill in the icon, thumbnail, name, genre and description. The game gets a UniverseID and starts **private**, playable only by people with Edit or Playtest access and up to 10 invited early testers.
2. **Release (public):** File > Publish > Continue. Answer the **first question of the Maturity & Compliance Questionnaire** (age-restricted content: yes or no).
   - **No** gives the label **"Content May Vary"**, and the game releases to **age-checked 16+ users and Trusted Friends only**.
   - **Yes** requires the full questionnaire, and the resulting label decides the audience.
3. Optional: complete account verification and the Kids and Select path to reach under-16 players.

Requirements for the 16+ release: "an account that is in good standing and at least 2 days old" and "Complete an age check through facial age estimation or government ID." The release limit is "up to 5 games per day that have never been released before." https://create.roblox.com/docs/production/publishing/publishing-experiences-and-places

### The older "unverified creators are restricted" rule
- Roblox's older announcement (2024 coverage) said **unrated experiences** would be restricted to their developers (secondary: https://www.aol.com/roblox-cracks-down-user-created-193452257.html). The current doc says: "If a game does not have content maturity information, Roblox automatically restricts the playability of the game on the platform for all players." https://create.roblox.com/docs/production/promotion/content-maturity
- The current model (2026) replaces this with **age-check gates on the creator**: an age check for a 16+ release, and full verification for all ages. Full verification means facial estimation if the creator is under 18, or **government ID if 18 or older**. I found no separate rule that says "unverified creators can't publish". In practice, an unverified creator cannot release anything public. (Source: the publishing page above.)
- One content-maturity page says the account must be at least 30 days old to generate labels. The publishing page says 2 days. **UNVERIFIED** which is current; probably 2 days on the newer page.

### Maturity labels and audiences (current)
| Label | What it allows (abridged quotes) | Who can see it |
|---|---|---|
| Minimal | "occasional mild violence and/or light unrealistic blood" | Kids (5–8), Select (9–15), 16+ |
| Mild | "repeated mild violence, heavy unrealistic blood, mild fear, mild crude humor" | Kids, Select, 16+ |
| Moderate | "moderate violence, light realistic blood, moderate fear, moderate crude humor, unplayable gambling" | Select (9–15), 16+ |
| Content May Vary | answered "No" to the first question only | age-checked 16+ only |
| Restricted | "strong violence, heavy realistic blood … romantic themes … strong language … alcohol" | **age-verified 18+ only**; unavailable in Korea, Saudi Arabia, Türkiye and other countries |

Source: https://create.roblox.com/docs/production/promotion/content-maturity

Descriptors that matter for a film archive:
- **Violence:** "if there is any moment that the consequence of violence is realistic," the content counts as moderate or strong. Prohibited outright: extreme violence and "glorification of war crimes or human rights violations."
- **Blood:** "Games with heavy, realistic blood are only available to age-verified players that are at least 18."
- **Alcohol, romantic themes and strong language** each require **18+**. Many 1930s and 1940s films show drinking and romance. Strictly read, any title with on-screen drinking pushes the game to Restricted (18+), which shrinks the audience badly. The doc doesn't address in-game **film** content as opposed to gameplay, so this reading is **UNVERIFIED**, but it is the conservative one.
- **Sensitive issues** (a "primary theme" that is a polarized social, political or religious issue): 16+ only, and not recommended unless the player is age-verified.
- **Media question:** the questionnaire asks whether the game has "continuous-loading or autoplay feeds" or lets users view captured content (e.g. via SurfaceGui or VideoFrame). A cinema playing films in a loop will likely answer **yes** to autoplay feeds.
- **"You must not add any age-restricted content to your game before receiving this label."** If an update changes any answer, you must resubmit.

### Moderation instead of app review
- There is **no pre-release human review** for a 16+ release. Content is moderated at several layers:
  1. **Every uploaded asset** (images, icons, thumbnails, audio, **video**) is moderated before others can see it. "Videos that don't meet these requirements are rejected." https://create.roblox.com/docs/ui/video-frames · https://create.roblox.com/docs/production/promotion/game-icons
  2. **The questionnaire** is self-declared but audited: "Roblox may review submissions." A discrepancy brings a private message and possible moderation, and repeated misreporting brings action against the game and the account. https://create.roblox.com/docs/production/promotion/content-maturity · https://create.roblox.com/docs/en-us/safety.md
  3. **The Kids and Select evaluation** is a trial period with 16+ users only, with hourly engagement analysis and a "safety review" by **Realtime Multimodal Moderation** of live gameplay. https://create.roblox.com/docs/production/publishing/kids-and-select
  4. **Reports** from players, and **text filtering**. "If Roblox finds your game doesn't apply text filtering, it may remove the game." https://create.roblox.com/docs/en-us/safety.md
  5. **Expedited review:** a 50,000 Robux refundable fee for timed launches. It speeds up the review but doesn't waive the standards.
- Appeals go to roblox.com/report-appeals or Support.

---

## 2. Policy risks specific to video

### How video works on Roblox (the binding constraint)
- `VideoFrame` plays an **uploaded asset ID** (`rbxassetid://`) on a ScreenGui, SurfaceGui or BillboardGui. The doc shows **no external or streaming URL support**. The examples use asset IDs only. That there is no URL playback is my inference from the API, **UNVERIFIED** as an explicit statement, but nothing in the docs suggests otherwise.
- Upload rules: "Each video upload costs 2,000 Robux"; "5 minutes or less in either .mp4 or .mov"; at most 4096×2160; "less than 3.75 GB"; "a maximum of 20 videos a day"; uploader must be "a 13+ ID verified user"; you need the Video Uploads beta enabled; "a maximum of two videos can play simultaneously"; you must hold the legal rights to the video. https://create.roblox.com/docs/ui/video-frames
- Older versions of the same doc (still served in some locales) say **30 seconds, 375 MB, 3 uploads per 30 days**. The English page now says 5 minutes and 20 a day. https://create.roblox.com/docs/en-us/ui/video-frames · https://devforum.roblox.com/t/2630621 (the 2023 beta launch)
- **Cost model for Archive Watch:** a 90-minute feature cut into 5-minute segments is about 18 uploads, roughly **36,000 Robux, which is about $360 or more at Robux retail prices** (**UNVERIFIED**). A cartoon or short subject fits in 1–2 uploads, so **shorts are realistic and features are not**.
- **Moderation risk on uploads:** a January 2026 DevForum report describes a 19-second video, apparently rejected for background music, being charged 2,000 Robux and then deleted with no explanation. https://devforum.roblox.com/t/copyright-video-autostrike/4238782 (user report; no staff reply). Automated matching may also flag public-domain films that rights holders have registered in content-ID systems. A restored or rescored copy of a public-domain film can carry a copyrighted soundtrack, the same risk the Watch Together rights notes already describe. **UNVERIFIED** for Roblox specifically.

### Copyright and DMCA on Roblox
- Rights holders file through **Rights Manager**: they must register and verify ownership, and can then submit removal requests for up to 250 creations each, which are approved or rejected. Accused creators see the requests under "Claims Against Me". https://create.roblox.com/docs/production/publishing/rights-manager
- Classic DMCA path: a notice to the Copyright Agent leads to removal. A counter-notice must state, under penalty of perjury, a good-faith belief that the removal was a mistake. "We generally restore the content within 14 business days," unless the claimant sues. Accounts that "repeatedly or egregiously infringe" are suspended or terminated. There is no published strike count. https://create.roblox.com/docs/production/publishing/dmca-guidelines
- IP guidelines overview: https://create.roblox.com/docs/production/publishing/ip-guidelines
- **Implication:** Archive Watch's evidence-based rights tiers (the guaranteed tier, Decisions 137, 151 and 157) should be the **only** source for Roblox uploads. The "presumed PD" and 1964–77 keep bands should be excluded, because a takedown here puts the creator account at risk, not just one title.

### Old films against the Community Standards (13+ / 16+ audience)
Quoted from https://about.roblox.com/community-standards:
- **Violent content:** prohibits "Realistic or real-world depictions of extreme gore, graphic violence, or death" and "Depicting or glorifying human, animal, or fictional creature abuse and torture." A newsreel of real war dead, or documentary footage of camps (e.g. *Death Mills*, 1945), would breach "real-world depictions of … death" no matter how valuable it is historically. **I found no educational or historical exception in the Standards.**
- **Real-World Sensitive Events:** prohibits content that "recreates or imitates real-world sensitive events; mocks the victims of such events" or "supports, glorifies, or promotes the perpetrators." That covers newsreels of mass violence and propaganda.
- **Terrorism and Violent Extremism:** prohibits content that "incites, condones, supports, glorifies, or promotes any terrorist or extremist organization or individual" and its "ideology, iconography." Nazi-state propaganda (Decision 149's set), or anything showing swastika iconography, is effectively off-limits. The flag Archive Watch uses (`noRecommend`) is not strong enough for Roblox. Those titles must be **excluded**.
- **Harassment and Discrimination:** prohibits "mocking … individuals or groups on the basis of" race, ethnicity, religion and other categories. Racist cartoons (blackface gags, wartime caricatures of Japanese people, the "Censored Eleven" class) would breach this. These need to be **excluded**, not contextualized. Roblox's Standards give no "historical context card" route.
- **Political content:** prohibits "the discussion or depiction of content pertaining to political figures and entities," defined as current or recent officials. Old newsreels of 1930s politicians are probably outside "current or recent", but this is **UNVERIFIED**.
- **Profanity:** "it's not ok to swear in any language, text, images, or uploaded audio" outside Restricted games.
- **Recommendation:** a Roblox catalog should be a small allowlist built from **silent comedy, animation without caricature, nature and travel films, early cinema (Méliès, Lumière), and industrial or ephemeral films**. Build it with the existing propaganda and URAA flags plus a new "Roblox-safe" gate. War newsreels, crime and horror with realistic blood, and anything showing alcohol prominently should be left out, unless the game takes the Restricted 18+ path, which most of Roblox's audience can't reach.

### External links ("also on archivewatch.org")
- The Community Standards (Security) say: "You may not link to, share, or display URLs of any external websites or services except by using the Social Links feature on the Game, Group, or User detail pages … Any other efforts to direct users off of Roblox to an external website or service are prohibited." https://about.roblox.com/community-standards
- January 2026: "Creators can no longer share social media links in-game." `PolicyService:GetExternalLinkReference` "is being sunset and will return an empty list". Creators may still write "Links on our game's page." https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
- Social Links (detail page only): up to 3 links, one per platform type. They are visible only to age-checked users (16+ originally, **13+ from 2026-02-23**), and only if the owner or an admin is age-checked. The help article says links "are not permitted to be shared directly within Experiences." https://en.help.roblox.com/hc/articles/360000910966 (403 to the fetcher; quotes from the search snippet)
- **Allowed link platforms:** historically YouTube, Facebook, Discord, X/Twitter, Twitch and Guilded. **A personal or organization website is not on the list** in any source I found. Secondary: https://www.snopes.com/news/2023/01/10/roblox-self-harm-dares-game-facebook/. The current platform list is **UNVERIFIED** because the help article was blocked.
- **Practical answer:** inside the experience, say **nothing** about archivewatch.org: no URL, no partial URL, no "search Archive Watch on the App Store". The experience **description** is also moderated, and a bare URL there is likely removed (**UNVERIFIED**). The legitimate bridge is a **YouTube or Discord social link** on the detail page, visible to age-checked 13+ users, which can point onward. Even naming the brand as an off-platform app may count as "efforts to direct users off of Roblox". Treat it as prohibited.

### Data and privacy (COPPA; talking to our own server)
- **HttpService exists and works from game servers.** It must be enabled ("Allow HTTP Requests" in Experience Settings > Security). It is HTTPS only, ports 80 and 443 (no other port below 1024, and not 1194). The limit is "500 HTTP requests per minute" per game server for non-Open-Cloud calls. Request headers are limited ("Only the x-api-key and content-type headers are allowed", and x-api-key must be a Secret). That header rule is described for Open Cloud; whether it applies to every request is **UNVERIFIED**. https://create.roblox.com/docs/cloud-services/http-service
- In practice HttpService runs **server-side only**. The doc implies this through its "each Roblox game server" limits but doesn't say so outright (**UNVERIFIED** as stated policy; long-standing engine behavior).
- **What may be sent:** I found no Roblox page that explicitly allows or forbids sending `UserId` to an external server. Roblox's privacy policy says creators already receive "username, display name, user ID, game metrics … and IP-derived regional location" (secondary analysis: https://conductatlas.com/platform/roblox/roblox-privacy-and-cookie-policy/creator-data-sharing-username-user-id-transaction-details-and-regional-location/). The Community Standards bar sharing or requesting personal information, and say "Developers are prohibited from creating personalized activity profiles of users" (in the advertising context). https://about.roblox.com/community-standards
- **Recommendation for Archive Watch:** send **nothing user-identifying** off-platform. If the experience fetches a catalog or schedule from archivewatch.org's Worker, make the request **anonymous** (the place ID or job ID at most), and keep per-user state such as watch history in Roblox **DataStores**, which stay on Roblox. That meets the project's "no accounts, no tracking" ethos and avoids taking on erasure duties. Roblox sends developers right-to-erasure requests, which they must act on in DataStores (**UNVERIFIED**: I recall a DevForum process but did not fetch a primary page).
- **COPPA:** Roblox is the operator that collects children's data. An experience that collects no personal information and sends none off-platform adds no COPPA exposure of its own (**UNVERIFIED** as a legal conclusion; this is the conservative reading).
- **Text the players write** (titles they search, chat, room names) must go through Roblox's text filtering, and player-to-player text must go through **TextChatService**. https://create.roblox.com/docs/en-us/safety.md

---

## 3. Social features policy

- **Text chat:** since January 2026, "All text-based player-to-player communication is required to go through TextChatService," including custom chat systems. If a user hasn't completed an age check, "the user's chat will not appear." Use `TextChannel:DisplaySystemMessage` for announcements. A **Text Chat matchmaking signal** exists, and Custom Matchmaking can weight it to put players who can talk to each other in the same server. https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
- **Voice chat:** players must be **13+ and age-checked**, in supported regions. Ages 9–12 get none, and ages 13–15 have voice off by default unless a parent enables it. https://about.roblox.com/safety-by-age Developer-side voice requirements: I found no primary doc in this pass (**UNVERIFIED** detail). Roblox said non-text communication guidance would come later.
- **Party:** groups of up to 6 friends who join the same server and move between experiences together. Anyone can start a Party, but **Party chat is 13+**. Voice support was announced as "coming months" in December 2024 (current status **UNVERIFIED**). Developers can "teleport members of the same Party to a private lobby." https://about.roblox.com/newsroom/2024/12/join-the-party-on-roblox The engine exposes `Player.PartyId` and `SocialService:GetPlayersByPartyId()`, which the teleport guide cites for moving groups together. https://create.roblox.com/docs/projects/teleport
- **Reserved servers:** this is the "watch-together room" primitive. `TeleportOptions.ShouldReserveServer = true` creates a reserved server, and `TeleportOptions.ReservedServerAccessCode` sends players to an existing one. `TeleportService:ReserveServerAsync(placeId)` returns a code you can save in a DataStore. `TeleportToPrivateServer` and `TeleportPartyAsync` are deprecated in favor of `TeleportAsync`. https://create.roblox.com/docs/projects/teleport · https://create.roblox.com/docs/reference/engine/classes/TeleportService
  - **Private servers** (the paid, player-owned VIP servers) are a different product, set in Creator Hub. They can be made free. Policy details were not fetched (**UNVERIFIED**).
- **Invites:** `SocialService:PromptGameInvite(player, ExperienceInviteOptions)` takes options whose properties are `PromptMessage`, `InviteUser`, `InviteMessageId` and `LaunchData`. The reference page gives no descriptions. `LaunchData` lets an invite carry a payload, which could be a film ID or room code. Call it after `CanSendGameInviteAsync`. **Calls:** `PromptPhoneBook`, `CanSendCallInviteAsync`, and `OnCallInviteInvoked`, which returns a `ReservedServerAccessCode` and `PlaceId`. https://create.roblox.com/docs/reference/engine/classes/SocialService · https://create.roblox.com/docs/reference/engine/classes/ExperienceInviteOptions
- **Friends joining:** invites and "Join" from the friends list follow Roblox's own connection rules. **Trusted Connections** (13+) widen who can chat across age groups. https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
- **Social hangouts:** a game whose "primary activity is talking with others" is a social-hangout descriptor and is limited to **16+** (or 18+ with private spaces). A cinema whose primary activity is **watching** is arguably not a hangout. But if the design leans on chat, it could be classified as one (**UNVERIFIED**). Design the cinema around the film, with chat as secondary. https://create.roblox.com/docs/production/promotion/content-maturity

---

## 4. Costs

| Item | Cost | Source |
|---|---|---|
| Publishing a game (private or 16+ release) | **Free** | https://create.roblox.com/docs/production/publishing/publishing-experiences-and-places |
| Kids and Select (under-16) access | 1,000 Robux per game, **refundable** (90 days after eligibility, or 90 days after payment if never eligible; forfeited on a severe violation), **or** a Plus or Premium subscription held for 2+ consecutive months | https://create.roblox.com/docs/production/publishing/kids-and-select · https://devforum.roblox.com/t/alternate-publishing-requirements-for-roblox-kids-and-select/4630944 (posted 2026-05-11, updated 05-19 and 05-27) |
| Expedited review | 50,000 Robux, refundable after 90 days | same |
| Video upload | **2,000 Robux each** (≤5 minutes) | https://create.roblox.com/docs/ui/video-frames |
| Video **thumbnail** (store trailer) | Free, quota of 3 a month | https://create.roblox.com/docs/production/promotion/thumbnails |
| Image, icon and thumbnail uploads | Free (subject to moderation) | thumbnails and icons docs |
| Audio uploads | Not researched here (**UNVERIFIED**; historically some free per month) | — |

- Roblox Plus is reported at $4.99 a month (secondary, **UNVERIFIED**): https://texxr.com/1166939/roblox-requires-roblox-plus-to-publish-kids-games
- **Engagement-based payouts:** "Effective July 24, 2025, the Engagement-Based Payouts program is deprecated", replaced by **Creator Rewards**. https://create.roblox.com/docs/en-us/production/monetization/engagement-based-payouts.md
  - **Daily Engagement** pays 5 Robux per qualifying "Active Spender" per day: the game must be among the user's first 3 launched that day, played for 10+ minutes. "No additional enrollment is required." **Audience Expansion** pays a 35% share of a new or returning user's first $100 of purchases, and needs an ID-verified owner and 100+ average DAU. https://create.roblox.com/docs/creator-rewards (the $9.99-in-60-days definition of Active Spender comes from secondary coverage: https://www.mediapost.com/publications/article/406941/roblox-to-reward-creators-for-attracting-players.html)
  - **Avoid or accept?** Daily Engagement is automatic and costs players nothing. It is paid by Roblox for attention, not by players. A nonprofit-spirited project can simply leave the Robux unexchanged, or donate it. The doc doesn't say whether a creator can opt out (**UNVERIFIED**). Cashing out goes through DevEx and its terms. One tension: the reward pays for being among a child's **first three games of the day** and for 10+ minutes of play. That is an engagement incentive the project's learning-orientation principle should treat warily. It need not change the design, but it should never be used as a design goal.
- **Entirely free, no monetization:** nothing in the publishing docs requires a game pass, developer product or ads. Roblox-operated ads are opt-in, and third-party advertising has needed Advertising Integrations registration since 2026-05-04. https://about.roblox.com/community-standards A no-purchase, no-ads experience is fully allowed. The only "monetization" that happens without action is Creator Rewards.
- **A catch:** Kids and Select eligibility depends on "highly engaged players", meaning users who made a minimum Robux purchase **anywhere on Roblox** in the last 60 days. Players needn't spend in your game, and "free-to-play games count." But a free cinema must still attract 250 such players in 60 days to reach under-16 users. https://create.roblox.com/docs/production/publishing/kids-and-select

---

## 5. Discovery and listing assets

### How experiences are found
https://create.roblox.com/docs/discovery
- **Home: Recommended for You** is personalized in two stages, retrieval then ranking. The most important signals are "Play through rate, first play bounce rate, play days per user, and playtime per user". Important signals are "Intentional co-play days per user, qualified play sessions per user, spend days per user, and Robux spent per user." Signals are **averaged per user**, so small games are not penalized for size. Sponsored ads don't count toward organic ranking.
- Other Home sorts: Continue Playing, Friends, Sponsored, curated sorts including **"Standout Games … hand curated by Roblox"**, and Live Events.
- **Search** is now **semantic** in supported languages ("food games"), not just title matches. A clear title and description such as "classic cartoons cinema" matter.
- **Discover / Charts:** "top and trending sorts".
- **Game Details Page:** shows similar games (another recommendation surface), the Community, passes and events.
- **Notifications:** experience notifications are opt-in.
- **Note:** "spend days per user" and "Robux spent per user" are ranking signals, so a game with no monetization gives up those two. Co-play (watching together) and long playtime are signals a cinema can earn honestly.

### Listing assets
- **Icon:** square, "at least 512×512", one per locale, shown as small as about 150×150. Every icon is moderated. https://create.roblox.com/docs/production/promotion/game-icons
- **Thumbnails:** 16:9, "ideally 1920×1080", in .jpg, .gif, .png, .tga or .bmp. Up to **10 images or videos** per detail page. Personalization uses 2–5 thumbnails, each under 3 MB. Keep essential text away from the bottom edge, where player counts are drawn. https://create.roblox.com/docs/production/promotion/thumbnails
- **Video thumbnails (the trailer):** uploaded, free, **3 a month**. A video that breaks policy still counts against the quota. Videos are shown first on the detail page and can appear on Home, but not on Xbox, PlayStation or VR. They are "reviewed for accuracy to the actual game". Disallowed: misrepresented gameplay, enhanced visuals, **"External content: real-life footage of people or places, or other content outside the game"**, **spoken audio and music with lyrics**, and advertising or subjective claims ("Free!"). The page gives no length limit (**UNVERIFIED**).
  - **For Archive Watch:** capture the trailer **inside the Roblox theater** with a film on its screen. A montage of raw film clips is the most likely way to fail the external-footage rule. Even in-theater, a film with spoken dialogue may trip the "spoken audio" rule, so prefer silent films or instrumental scores for the trailer audio.
- Name, description and genre are set at publish and are text-moderated.

---

## 6. The age-check and facial age estimation rollout, and watch-together

Timeline:
- **Nov 2024:** under-13 limits on social spaces (secondary: https://techcrunch.com/2024/11/07/roblox-adds-new-safety-measures-to-ban-kids-under-13-from-social-spaces)
- **Dec 2025:** age checks required for chat in Australia, New Zealand and the Netherlands (secondary: https://gulfnews.com/technology/media/roblox-now-requires-age-checks-for-all-users-to-access-chat-worldwide-1.500401325)
- **2026-01-07:** Roblox announces that US users must age-check to chat, extending to all chat regions within about a week. https://www.nasdaq.com/press-release/roblox-requires-users-worldwide-age-check-access-chat-2026-01-07 (Business Wire press release)
- **2026-01-09:** the DevForum staff post "Age Check Requirement to Chat Now Live Globally". 2026-02-23: social links limited to age-checked 13+. March 2026: age checks required for Team Create. https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
- **May–June 2026:** Roblox Kids (5–8) and Select (9–15) account types, plus the new publishing requirements. Rollout began 2026-05-19 in New Zealand, the Netherlands, Australia and Indonesia, then went global in early June 2026. https://devforum.roblox.com/t/alternate-publishing-requirements-for-roblox-kids-and-select/4630944

How it works: Facial Age Estimation runs in the app using the camera, or the user verifies with ID. Users are placed in age groups: **under 9, 9–12, 13–15, 16–17, 18–20, 21+**. "Age-based chat is designed to prevent children younger than 16 from communicating with adults." Each group can chat with its own group and the groups directly above and below it. Under-9 needs parental consent. Age-checked users 13+ can use Trusted Connections to chat across groups. Roblox says the images are deleted after processing. Sources: the devforum post and press release above; https://about.roblox.com/safety-by-age

**Effect on a chat-based watch-together room:**
1. **Many guests will be silent.** Any player who hasn't age-checked "will not appear" in chat, and an under-13 player in Select has limited or parent-controlled chat. A watch-together design must work **without chat**: shared emotes, reactions, seat proximity, a "pause vote" button, preset Quick Words. Quick Words (pre-approved phrases) exist for Select users. https://about.roblox.com/safety-by-age
2. **Mixed-age rooms split.** A 12-year-old and an adult in the same theater can't chat with each other. Inviting a Party into a reserved server keeps friends together, but chat still follows age groups unless they are Trusted Connections.
3. **Matchmaking:** for public screenings, weight the Text Chat signal (Custom Matchmaking) so that people who can talk end up in the same server. https://devforum.roblox.com/t/age-check-requirement-to-chat-now-live-globally/4226101
4. **Voice in the cinema** is 13+ and age-checked only, off by default for 13–15, and none for 9–12. It is an optional extra, never the core.
5. **No "join by code" through external links.** Rooms are shared through `PromptGameInvite` with `LaunchData`, or through Party and Friends. A room code spoken over Archive Watch's own apps (the existing Watch Together Worker) would need HttpService and a typed code. Typing a code in is fine, but **advertising** the other apps inside Roblox to get people there is not.
6. **The trust-and-safety profile helps the project.** A cinema with filtered or optional chat and no external links matches the direction Roblox is pushing. It also matches the CLAUDE.md principle of inviting participation without making people passive. A "discussion after the film" prompt in TextChatService is one such participation feature (that framing is mine).

---

## Unverified or open items to settle before building
- Whether `VideoFrame` can play any non-uploaded source (assumed **no**).
- Whether film content shown on in-game screens is rated as game content for the questionnaire (alcohol, romance, realistic violence in a 1930s feature), and how strictly. Asking Roblox, or a DevForum search, would settle this.
- The current Social Links platform list (the help center blocked the fetcher), and whether a nonprofit website can ever be linked.
- Whether creators can opt out of Creator Rewards.
- Roblox's right-to-erasure process for DataStores (developers do receive requests; details not fetched).
- Whether the video-thumbnail length limit and the 5-minute VideoFrame limit stay current. The docs disagree by locale.
