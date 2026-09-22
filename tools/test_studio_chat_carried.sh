#!/bin/bash
# THE BROADCAST'S CHAT ID REACHES THE ENGINE — WATCH-TOGETHER §8.36.
#
# `liveBroadcasts.insert` returns a `liveChatId`. `YouTubeLive.prepare` read it
# into `StreamCredentials.liveChatID`. `YouTubeLive.chat(liveChatID:pageToken:)`
# was written, complete and correct, to poll it. And the programme's chat
# column stayed empty on every YouTube broadcast this app has ever made,
# because `StudioGoLive.destination()` returned a bare `URL?` — so the id was
# read and dropped inside one function, and no test could tell.
#
# That is Decision 133's defect in its purest form: a value proved where it is
# WRITTEN rather than where it LANDS. A unit test of the parser would have
# passed; a unit test of `prepare` would have passed. Only the chain fails.
#
# So this checks the CHAIN, at every link, on every platform that can go live.
# It cannot prove chat appears on screen — only a broadcast can — but it can
# prove that no link is missing, which is the one thing that was wrong.
set -u
cd "$(dirname "$0")/.."
fail=0

say() { # name, file, pattern
  if [ ! -f "$2" ]; then
    echo "  FAIL  $1 — $2 does not exist"; fail=1; return
  fi
  if grep -q "$3" "$2"; then
    echo "  PASS  $1 — $(basename "$2")"
  else
    echo "  FAIL  $1 — $(basename "$2") does not mention /$3/"
    fail=1
  fi
}

echo "Watch Together — a broadcast's chat id reaches the engine"
echo

S=ArchiveWatch/ArchiveWatch/Studio
say "the platform reads it"            "$S/StudioPlatforms.swift"      'liveChatID: chatID'
say "the resolver CARRIES it"          "$S/StudioGoLive.swift"         'liveChatID: creds.liveChatID'
say "the session can be armed with it" "$S/StudioSession.swift"        'func armYouTubeChat'
say "the session APPLIES it"           "$S/StudioSession.swift"        'attachYouTubeChat(liveChatID:'
say "the engine attaches a reader"     "$S/StudioEngine.swift"         'func attachYouTubeChat'
say "the engine's pump reads it"       "$S/StudioEngine.swift"         'youtubeChat'
say "and STOPS it with the show"       "$S/StudioEngine.swift"         'youtubeChat = nil'
say "the reader polls the platform"    "$S/StudioChatYouTube.swift"    'api.chat(liveChatID:'
say "and honours the server's interval" "$S/StudioChatYouTube.swift"   'page.pollAfterMS'

echo
echo "every go-live surface arms the chat id it was just handed"
# EVERY surface, because fixing one and not its siblings is the defect class
# §8.12 exists for and which has recurred four times in this feature.
for f in ArchiveWatch/ArchiveWatch/macOS/StudioWindow_macOS.swift \
         ArchiveWatch/ArchiveWatch/iOS/StudioPlayerContainer_iOS.swift \
         ArchiveWatch/ArchiveWatch/Views/DetailView.swift; do
  if ! grep -q "StudioGoLive.destination" "$f"; then
    echo "  FAIL  $(basename "$f") no longer resolves a destination — this list is stale"
    fail=1
  elif grep -q "armYouTubeChat" "$f"; then
    echo "  PASS  $(basename "$f")"
  else
    echo "  FAIL  $(basename "$f") resolves a destination and drops its chat id"
    fail=1
  fi
done

echo
# CONTROL — the check can fail. Without this the greps prove only that grep
# runs (Decision 120's rule, §8.12's, §8.35's).
if grep -q "aw_this_pattern_is_in_no_source" "$S/StudioGoLive.swift"; then
  echo "  FAIL  CONTROL — an absent pattern was reported present"
  fail=1
else
  echo "  PASS  CONTROL — an absent pattern is correctly reported absent"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "THE CHAT ID SURVIVES THE WHOLE CHAIN."
else
  echo "FAILED — a link drops it."
fi
exit "$fail"
