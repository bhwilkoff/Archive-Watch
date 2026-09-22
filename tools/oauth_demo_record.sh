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
#       -> beats 5-9: create, bind, go live, chat, end. Not just sign-in.
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

       Before recording, on the account you will use:
         1. open https://myaccount.google.com/permissions
         2. find Archive Watch, Remove access, confirm
         3. confirm it is gone from the list

       Use benwilkoff@gmail.com — the channels approved for live streaming
       (Learning is Change, Archive Watch) are on that account.
TXT
if [ "$CHECK_ONLY" = "0" ]; then
  read -r -p "       Has access been revoked for this account? [y/N] " a
  case "$a" in [yY]*) ok "revoked — the consent screen will print the scope";;
    *) bad "revoke first, or the video is rejected for the same reason again"; esac
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
       Narrate as you go; Google reviews these with sound off as often as not,
       so let each screen sit still for two seconds.

        1. Archive Watch open on the Home screen. Say what the app is:
           public-domain films from the Internet Archive, free, no accounts.
        2. Open Safety Last! and press Play. Let the film run a beat.
        3. Open Watch Together Studio (Broadcast menu, or Shift-Cmd-S).
           Show FILM and STREAM side by side.
        4. In OUTPUT, platform YouTube, press Sign in.
           - Apple's "Archive Watch Wants to Use accounts.google.com"
           - the account chooser: DO NOT FILM IT. It lists family addresses.
             Pause the recording, choose, resume. (Google does not require
             the chooser; it requires the CONSENT screen.)
           - Google's unverified-app screen: SHOW IT. Google expects it.
             Advanced -> Go to Archive Watch (unsafe).
           - THE CONSENT SCREEN. Hold it for four seconds. The line
             "See, edit, and permanently delete your YouTube videos, ratings,
             comments and captions" must be legible. If it instead says
             "already has some access", STOP — step 2 was not done.
           - Continue.
        5. Back in the Studio: the row now names the CHANNEL you signed in to.
           This is the read half of the scope, and it is why the app needs it:
           a host must see which channel they are about to broadcast to.
        6. Show the readiness check: the Studio asks YouTube whether live
           streaming is enabled before it lets you press Go Live.
        7. Type a stream title. Set privacy to Unlisted. Press Go Live.
           The status goes to ON AIR. This is liveStreams.insert +
           liveBroadcasts.insert + bind + transition — the write half.
        8. Show the programme: the film, your camera tile, the lower third.
        9. From a phone or a second browser, post a message in the broadcast's
           live chat, and show it appearing over the programme. That is the
           read-chat half of the scope.
           CAVEAT, KNOWN BEFORE YOU START: this is the ONE beat never proved
           end to end. The reader is wired (macOS arms the liveChatID at
           go-live, polls at YouTube's own interval, and the renderer draws
           the column) and §8.36 asserts the id reaches the engine, but no
           real message has ever been seen on a real programme. If nothing
           appears within ~30 s, DO NOT abandon the take: carry on to beat 10
           and cut beat 9 in the edit. The video is sufficient without it;
           beats 5-8 and 10-11 already cover read and write.
       10. THE SOURCE ACCOUNT. Switch to studio.youtube.com in a browser,
           open Content -> Live, and show the broadcast you just created
           sitting there with the title you typed. Google asked for this in
           as many words; the last video did not have it.
       11. Press End the broadcast in the app. Return to YouTube Studio,
           refresh, and show the broadcast is no longer live. That is
           liveBroadcasts.transition to complete — the app cleaning up after
           itself, which is the best argument that it uses the scope narrowly.
       12. Close on the Studio at rest.

       DO NOT FILM: the account chooser, your notification centre, any other
       window. Quit Mail, Messages and Slack first.
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
case "$a" in [yY]*) ;; *) echo "       cancelled"; exit 0;; esac
echo "       recording in 3..."; sleep 1; echo "       2..."; sleep 1; echo "       1..."; sleep 1
screencapture -v "$OUT"
say "Saved: $OUT"
echo "       Check it before sending: the consent screen must print the scope"
echo "       in words, and the broadcast must appear in YouTube Studio."
