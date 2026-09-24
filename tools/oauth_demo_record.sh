#!/bin/bash
# Record the OAuth verification demo video Google asked for (2026-09-22).
#
# WHY THIS IS A SCRIPT AND NOT A NOTE. The first demo video was recorded by
# hand, and Google rejected it for reasons that were all knowable in advance:
# it showed sign-in but not what the scope is FOR, it never showed the change
# landing in the YouTube account, and the consent screen had collapsed the
# scope into "Archive Watch already has some access" because that account had
# granted it before. Each of those is a step somebody has to remember at the
# moment of recording, when they are also driving the app. So they are steps
# in a file instead.
#
# Google's stated criteria, from the rejection mail, each mapped to a beat:
#
#   "demonstrate the full operational functionality of every requested scope"
#       -> beats 5-12: create, bind, go live, thumbnail, viewers, chat read + the
#          host-pressed post, end. Not just sign-in.
#   "show the changes triggered in the app reflected in the user's account"
#       -> beat 10: YouTube Studio's own Live tab, with the broadcast in it.
#   "the consent screen must be displayed with all requested scopes fully
#    expanded and readable"
#       -> STEP 0 below, which is the one that cannot be fixed in the edit.
#   "the scopes requested must exactly match the scopes submitted"
#       -> asserted mechanically before recording starts, from the source.
#
# THIS SCRIPT RECORDS THE SCREEN. It does not drive the app: a demo video of a
# harness driving the product is not a demo of the product. It gives you the
# beats, times them, and captures.
#
#   bash tools/oauth_demo_record.sh            # check everything, then record
#   bash tools/oauth_demo_record.sh --check    # checks only, record nothing
set -u
cd "$(dirname "$0")/.."

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

OUT="${OUT:-$HOME/Desktop/ArchiveWatch-OAuth-demo-$(date +%Y%m%d-%H%M).mov}"
fail=0

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }

say "1. The scope the app actually requests"
# From the SOURCE, because "the scopes requested by your app must exactly match
# the scopes configured in the Console" is a claim about the binary, and the
# only place that is true is the array the authorize URL is built from.
SRC=ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift
REQUESTED=$(grep -oE 'https://www\.googleapis\.com/auth/[a-z.]+' "$SRC" | sort -u)
echo "$REQUESTED" | sed 's/^/       /'
COUNT=$(echo "$REQUESTED" | grep -c .)
if [ "$COUNT" = "1" ] && [ "$REQUESTED" = "https://www.googleapis.com/auth/youtube" ]; then
  ok "exactly one Google scope, and it is the one submitted for verification"
else
  bad "the app requests $COUNT Google scope(s) — the Console submission names one."
  bad "Either narrow the app or add them to the Console; a mismatch is a rejection."
fi

say "2. Has Archive Watch's access been REVOKED on the demo account?"
cat <<'TXT'
       THIS IS THE STEP THAT FAILED LAST TIME AND CANNOT BE FIXED IN THE EDIT.
       Google requires the consent screen to show the scope in words. If the
       account has already granted it, Google collapses it to "Archive Watch
       already has some access" and the sentence never appears.

       myaccount.google.com/permissions CANNOT do this for a Brand Account
       (measured 2026-09-22: the grant survives every removal there). The
       token is the only handle, and the Studio's Sign out revokes it:
         1. sign in once in the Studio to the channel you will film
            (choose the Brand Account), off camera
         2. press Sign out: it calls oauth2.googleapis.com/revoke, which
            drops the whole grant, including other devices' tokens
         3. the next sign-in prints "Manage your YouTube account" in words

       Use benwilkoff@gmail.com — the channels approved for live streaming
       (Learning is Change, Archive Watch) are on that account.
TXT
if [ "$CHECK_ONLY" = "0" ]; then
  read -r -p "       Signed in and out once (Sign out revokes)? [y/N] " a
  case "$a" in [yY]*) ok "revoked — the consent screen will print the scope";;
    *) bad "sign in + Sign out first, or the consent screen collapses again"; esac
fi

say "3. A film that is rights-KEEP and has a soundtrack"
cat <<'TXT'
       Safety Last! (1923) — archive id safety-last-final_202506 — is the one
       used for every measurement in this feature. It is pre-1930, so the
       rights line renders, and it CARRIES AUDIO, which matters because a
       silent transfer makes every level meter read as a fault on camera.
TXT
ok "use Safety Last! unless you have a reason not to"

say "4. The beats, in order"
cat <<'TXT'
       Narrate as you go; let each screen sit still for two seconds. The
       Studio changed a lot on 2026-09-22 — this list is against the build
       you have now (four columns: Inputs, Mixer, On screen, Output).

        1. Archive Watch on Home. Say what it is: public-domain films from the
           Internet Archive, free, no accounts.
        2. Open Safety Last! (1923). Note the rights line on the page — only
           pre-1930 titles can be broadcast.
        3. Press Play, then Watch Together Studio (Shift-Cmd-L).
           The FILM pane and the STREAM pane sit side by side.
        4. OUTPUT column, Platform: YouTube. Press "Sign in".
           - Apple: "Archive Watch Wants to Use accounts.google.com"
           - THE ACCOUNT CHOOSER: DO NOT FILM IT. Pause recording, choose,
             resume. Google needs the CONSENT screen, not the chooser.
           - Google's unverified-app screen: SHOW IT. Google expects it.
             Advanced -> "Go to Archive Watch (unsafe)".
           - THE CONSENT SCREEN. Hold four seconds. The YouTube permission
             must be legible IN WORDS. If it says "already has some access",
             STOP — step 2 of this script was not done.
           - Continue.
        5. The OUTPUT column now names the CHANNEL you signed in to. Say that
           this is the read half of the scope and why the app needs it: a host
           must see which channel they are about to broadcast to.
        6. Type a Stream title. Leave Privacy on Unlisted.
        7. Press "Start preview" first if you want to show the rehearsal —
           worth 10 seconds, because it shows the app checking itself before
           it touches the account. Note that the chat column is ABSENT here:
           nothing is going out, so there is no audience.
        8. Press "Go Live". The STREAM header turns to "● LIVE 0:04 · N Mbps"
           and the OUTPUT column becomes "Live on YouTube, as <channel>" with
           the audience link. This is liveStreams.insert +
           liveBroadcasts.insert + bind (YouTube auto-starts it) — the write half.
        9. Show the program: the film, your camera tile, the lower third.
           About ten seconds in the app sets the broadcast's THUMBNAIL to a
           still of this picture (thumbnails.set) — beat 11 shows it arrived.
       10. THE AUDIENCE. Open the audience link on a phone and let it play:
           the AUDIENCE header reads "1 watching" (videos.list,
           liveStreamingDetails). Then press "Share the film in chat" and show
           the line — the film's title and its Internet Archive link — arriving
           in the broadcast's own chat on the phone (liveChatMessages.insert),
           and in the AUDIENCE pane (the read-chat half). Say it only ever
           posts when the host presses it.
       11. THE SOURCE ACCOUNT. Switch to studio.youtube.com, Content -> Live,
           and show the broadcast you just created: your title, Unlisted, "Live
           now", and the program still as its thumbnail. Google asked for this
           in as many words; the first video lacked it.
       12. Press "End the broadcast" in the app. Back in YouTube Studio,
           refresh: "Streamed" — transition to complete. Say that a show that
           never reaches live is DELETED instead, so nothing is left in
           Upcoming — the app cleans up after itself, which is the strongest
           argument that it uses the scope narrowly.
       13. Close on the Studio at rest.

       DO NOT FILM: the account chooser, notifications, any other window.
TXT

say "5. What NOT to have on screen"
for app in "Mail" "Messages" "Slack" "Notes"; do
  if pgrep -x "$app" >/dev/null 2>&1; then
    bad "$app is running — quit it before recording"
  else
    ok "$app is not running"
  fi
done

if [ "$fail" != "0" ]; then
  say "Not ready. Fix the items above."
  exit 1
fi

if [ "$CHECK_ONLY" = "1" ]; then
  say "Checks only — nothing recorded."
  exit 0
fi

say "6. Recording"
cat <<TXT
       Writing to: $OUT
       screencapture -v records the WHOLE screen, which is what a reviewer
       needs (they must see the browser and the app in one take). That is why
       step 5 exists: on this machine the usual rule is window-only capture,
       and a full-screen recording is a deliberate exception made once the
       screen has been cleared.

       Press CONTROL-C in this terminal to stop recording.
TXT
read -r -p "       Ready? [y/N] " a
case "$a" in [yY]*) ;; *) echo "       canceled"; exit 0;; esac
echo "       recording in 3..."; sleep 1; echo "       2..."; sleep 1; echo "       1..."; sleep 1
screencapture -v "$OUT"
say "Saved: $OUT"
echo "       Check it before sending: the consent screen must print the scope"
echo "       in words, and the broadcast must appear in YouTube Studio."
