// §8.32 — the WEB room client (SHAREPLAY §11).
//
// This is the FOURTH implementation of one rule — Swift (§8.28), the Worker's
// JavaScript (§8.29), Kotlin (`StudioRoomTest`), and now the browser — and
// four chances to disagree about what a heard "oh" means. The input table
// below is the same one all of them assert, on purpose and by hand.
//
// It also re-asserts §8.27's arithmetic in JavaScript, because a port is not
// a proof: `expectedPosition` forgetting to ask whether the film is PAUSED
// returns a plausible number that is wrong, and nothing else here would catch
// it.
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const T = require("../js/together.js");

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
}
const near = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;

console.log("=== §8.32 web room client ===");

// ---- the shared table
for (const [input, want, why] of [
  ["ca11", "CA11", "lower case"],
  ["CA 11", "CA11", "spaces ignored"],
  ["CA-11", "CA11", "dashes ignored"],
  ["CAL1", "CA11", "a heard ell"],
  ["CAI1", "CA11", "a heard eye"],
  ["CALI", "CA11", "both at once"],
  ["CODE", "C0DE", "a heard oh"],
  ["C0DE", "C0DE", "a real zero"],
  ["ABCD", "ABCD", "clean"],
]) check(`${why}: "${input}" -> ${want}`, T.normalizeCode(input) === want,
        String(T.normalizeCode(input)));
check("ALL SPELLINGS REACH ONE ROOM",
  new Set(["CALI", "CAL1", "CAI1", "CA11", "ca11"].map(T.normalizeCode)).size === 1);
for (const bad of ["AB", "ABCDE", "AB!E", "ABUE", "", null, 7])
  check(`refused: ${JSON.stringify(bad)}`, T.normalizeCode(bad) === null);
check("CONTROL: a well-formed code is accepted", T.normalizeCode("XYZ9") === "XYZ9");

// ---- the route, and the id shape that breaks the obvious split
const film = "ptp_the-love-nest_buster-keaton_blu-ray_h264_1080p_430833";
const r = T.parseRoute(`CA11-${film}`);
check("a route parses", r && r.code === "CA11", JSON.stringify(r));
check("AN ARCHIVE ID FULL OF DASHES SURVIVES", r && r.filmID === film, r && r.filmID);
check("a heard code in a LINK still resolves",
  T.parseRoute(`cali-${film}`)?.code === "CA11");
check("a route with no film is refused", T.parseRoute("CA11") === null);

// ---- the arithmetic
const playing = { filmID: "x", position: 100, atServerTime: 1000, rate: 1, paused: false };
const paused  = { filmID: "x", position: 100, atServerTime: 1000, rate: 1, paused: true };
check("a playing film advances", near(T.expectedPosition(playing, 1030), 130));
check("A PAUSED FILM DOES NOT ADVANCE", near(T.expectedPosition(paused, 1030), 100),
      String(T.expectedPosition(paused, 1030)));
check("a clock that went backwards does not rewind the film",
      near(T.expectedPosition(playing, 990), 100));

const c = (local, lp = false, now = 1030) => T.correction(local, lp, playing, now);
check("in step, nothing happens", c(130.05).kind === "none");
check("behind speeds up", c(129).kind === "nudge" && c(129).rate === T.NUDGE_FAST);
check("ahead slows down", c(131).kind === "nudge" && c(131).rate === T.NUDGE_SLOW);
check("CONTROL: behind and ahead differ", c(129).rate !== c(131).rate);
check("far off seeks", c(120).kind === "seek" && near(c(120).to, 130));
check("a host's pause is applied at once",
      T.correction(130, false, paused, 1030).kind === "setPaused");
check("a paused film is never seeked for drift",
      T.correction(10, true, paused, 1030).kind === "none");

// ---- the clock: the fastest sample, and why
// Asymmetric delays, because under SYMMETRIC delay Cristian's algorithm is
// exact at any RTT and the control cannot show anything (§8.27 learned this
// the hard way, from a fixture that could not fail).
const fast = T.sampleOffset(0, 5.010, 0.020);
const slowA = T.sampleOffset(1, 6.700, 1.800);
const slowB = T.sampleOffset(2, 7.800, 3.000);
check("the fast sample is accurate within its bound",
      Math.abs(fast.offset - 5) <= fast.error, `${fast.offset.toFixed(4)} ±${fast.error.toFixed(4)}`);
const avg = (fast.offset + slowA.offset + slowB.offset) / 3;
check("CONTROL: averaging is materially worse",
      Math.abs(avg - 5) > Math.abs(fast.offset - 5) && Math.abs(avg - 5) > 0.1,
      `min-RTT off ${Math.abs(fast.offset - 5).toFixed(4)}, average off ${Math.abs(avg - 5).toFixed(4)}`);

check("a busy room polls fast", near(T.pollInterval(5), T.POLL_FAST));
check("a quiet room backs off", near(T.pollInterval(120), T.POLL_IDLE));

// ---- a guest's own pause or scrub is answered AT ONCE, ours are not
{
  class FakeVideo extends EventTarget {
    constructor() { super(); this.currentTime = 100; this.paused = false; this.playbackRate = 1; }
    pause() { this.paused = true; this.dispatchEvent(new Event("pause")); }
    play() { this.paused = false; return Promise.resolve(); }
  }
  const now = () => Date.now() / 1000;
  let polls = 0;
  let hostPaused = false;
  const client = {
    async poll() { polls++; return { filmID: "x", position: 100, atServerTime: now(), rate: 1, paused: hostPaused, generation: 1 }; },
    serverNow: now, nextPollDelay: () => 60, sayHere() {},
  };
  const settle = () => new Promise(r => setTimeout(r, 20));
  const video = new FakeVideo();
  let overrides = 0;
  const session = T.follow(video, client, null, () => { overrides++; });
  await settle();
  check("follow polls once on start", polls === 1, `polls=${polls}`);

  video.pause();                       // the GUEST presses pause
  await settle();
  check("a guest's pause is re-checked at once, not at the next poll", polls === 2, `polls=${polls}`);
  check("the guest is told who holds the film", overrides === 1, `overrides=${overrides}`);
  check("and the film is playing again", video.paused === false);

  video.dispatchEvent(new Event("seeking"));   // the guest drags the bar
  await settle();
  check("a guest's scrub is re-checked at once", polls === 3, `polls=${polls}`);

  // CONTROL: a pause the ROOM makes is not the guest's.
  hostPaused = true;
  await new Promise(r => setTimeout(r, 1600));   // past the own-event window
  const before = polls;
  video.dispatchEvent(new Event("seeking"));      // provoke a poll...
  await settle();                                 // ...which pauses the film itself
  check("control: the room's own pause does not count as the guest's",
        polls === before + 1 && overrides === 3 && video.paused === true,
        `polls ${before}->${polls}, overrides=${overrides}, paused=${video.paused}`);

  session.stop();
  video.pause();
  await settle();
  check("after stop, nothing is re-checked", polls === before + 1, `polls=${polls}`);
}

console.log(failures === 0 ? "=== §8.32 OK ===" : `=== §8.32 ${failures} FAILURES ===`);
process.exit(failures === 0 ? 0 : 1);
