// §8.30 — the room transport, against a RUNNING Worker (SHAREPLAY §11.11).
//
// §8.29 asserts the code normalisation in isolation. This drives the actual
// HTTP routes against `wrangler dev` with a real D1 behind them, because a
// route that parses is not a route that works — Decision 130's rule, applied
// to the one piece of this feature that is not Swift.
//
//   BASE=http://127.0.0.1:8799 node tools/test_together_live.mjs
const BASE = process.env.BASE || "http://127.0.0.1:8799";

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
}
const j = async (r) => { try { return await r.json(); } catch { return null; } };

console.log("=== §8.30 room transport, live ===");
const FILM = "ptp_the-love-nest_buster-keaton_blu-ray_h264_1080p_430833";

// ---- create
const created = await j(await fetch(`${BASE}/together/new`, {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ filmID: FILM, position: 12.5, rate: 1, paused: false }),
}));
check("a room is created and hands back a code", !!created?.code, JSON.stringify(created));
const code = created?.code;
const hostKey = created?.hostKey;
check("creation hands back a HOST KEY, not just a code", typeof hostKey === "string" && hostKey.length >= 32,
      hostKey ? `${hostKey.length} chars` : "none");
check("the code is four characters", code?.length === 4, code);
check("creation returns the server's own clock", typeof created?.serverTime === "number",
      String(created?.serverTime));
if (!code) { console.log("=== §8.30 cannot continue ==="); process.exit(1); }

// ---- read
const got = await j(await fetch(`${BASE}/together/${code}`));
check("the room reads back", got?.code === code, JSON.stringify(got));
check("the film id survives, dashes and all", got?.filmID === FILM, got?.filmID);
check("the position survives", got?.position === 12.5, String(got?.position));
// THE ONE THAT MAKES THE POLL FREE: the state and the clock arrive together,
// so §11.2's offset estimate costs no second request.
check("THE GET CARRIES serverTime, so the poll IS the clock sync",
      typeof got?.serverTime === "number" && got.serverTime > 1e9, String(got?.serverTime));
check("atServerTime is in SECONDS, not milliseconds",
      got?.atServerTime > 1e9 && got.atServerTime < 1e11, String(got?.atServerTime));

// ---- a mistyped code reaches the SAME room
const heard = await j(await fetch(`${BASE}/together/${code.replace(/1/g, "I").replace(/0/g, "O")}`));
check("a code typed the way it was HEARD reaches the same room",
      heard?.code === code, JSON.stringify(heard));

// ---- update, and the server owns the generation
const g0 = got.generation;
const upd = await j(await fetch(`${BASE}/together/${code}`, {
  method: "POST", headers: { "content-type": "application/json", "x-aw-host-key": hostKey },
  body: JSON.stringify({ filmID: FILM, position: 99, rate: 1, paused: true, generation: 12345 }),
}));
check("a host publishes a new state", upd?.position === 99, JSON.stringify(upd));
check("pause survives the round trip", upd?.paused === true, String(upd?.paused));
check("THE SERVER owns the generation — a client cannot set it",
      upd?.generation === g0 + 1, `${g0} -> ${upd?.generation} (client sent 12345)`);

// CONTROL: a second write must move it again, or "the server owns it" could
// be satisfied by a constant.
const upd2 = await j(await fetch(`${BASE}/together/${code}`, {
  method: "POST", headers: { "content-type": "application/json", "x-aw-host-key": hostKey },
  body: JSON.stringify({ filmID: FILM, position: 100 }),
}));
check("CONTROL: a further write advances the generation again",
      upd2?.generation === g0 + 2, `${upd?.generation} -> ${upd2?.generation}`);

// ---- A GUEST WITH ONLY THE CODE CANNOT DRIVE THE SHOW.
// Tidbits Trivia's own screen: "the room code alone cannot drive the show."
// The code is read aloud, so it cannot also be the credential.
const hijack = await fetch(`${BASE}/together/${code}`, {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ filmID: FILM, position: 0, paused: true }),
});
check("A GUEST WITH THE CODE AND NO KEY IS REFUSED", hijack.status === 403,
      `HTTP ${hijack.status}`);
const wrongKey = await fetch(`${BASE}/together/${code}`, {
  method: "POST", headers: { "content-type": "application/json", "x-aw-host-key": "nope" },
  body: JSON.stringify({ filmID: FILM, position: 0 }),
});
check("and a WRONG key is refused", wrongKey.status === 403, `HTTP ${wrongKey.status}`);
// and the refusal actually protected the room
const after = await j(await fetch(`${BASE}/together/${code}`));
check("the room was NOT changed by the attempt", after?.position === 100,
      String(after?.position));
// A READ must never hand the key out, or the split is undone by the first poll.
check("a GET never carries the host key", after?.hostKey === undefined,
      JSON.stringify(Object.keys(after || {})));

// ---- unknown and malformed
check("an unknown room is 404",
      (await fetch(`${BASE}/together/ZZZZ`)).status === 404);
check("a malformed code is 400",
      (await fetch(`${BASE}/together/AB`)).status === 400);
check("creating without a film is refused",
      (await fetch(`${BASE}/together/new`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({}) })).status === 400);

// ---- ending DELETES, because a room that lingers is a record of what
// somebody watched.
const ended = await j(await fetch(`${BASE}/together/${code}`, {
  method: "POST", headers: { "content-type": "application/json", "x-aw-host-key": hostKey },
  body: JSON.stringify({ end: true }),
}));
check("ending a room reports it ended", ended?.ended === true, JSON.stringify(ended));
check("AND THE ROOM IS GONE, not merely flagged",
      (await fetch(`${BASE}/together/${code}`)).status === 404);

// ---- two rooms do not collide
const a = await j(await fetch(`${BASE}/together/new`, {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ filmID: "a" }) }));
const b = await j(await fetch(`${BASE}/together/new`, {
  method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ filmID: "b" }) }));
check("two rooms get different codes", a?.code !== b?.code, `${a?.code} vs ${b?.code}`);
check("and each holds its own film",
      (await j(await fetch(`${BASE}/together/${a.code}`)))?.filmID === "a" &&
      (await j(await fetch(`${BASE}/together/${b.code}`)))?.filmID === "b");
for (const r of [a, b]) {
  await fetch(`${BASE}/together/${r.code}`, {
    method: "POST", headers: { "content-type": "application/json", "x-aw-host-key": r.hostKey },
    body: JSON.stringify({ end: true }) });
}

console.log(failures === 0 ? "=== §8.30 OK ===" : `=== §8.30 ${failures} FAILURES ===`);
process.exit(failures === 0 ? 0 : 1);
