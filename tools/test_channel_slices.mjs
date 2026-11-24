// The per-channel schedules (tools/build_channel_slices.py) answer exactly as
// the whole channel-schedule.json does, through the Worker's own code
// (worker/src/live.js, xtream.js), and the Worker falls back to the whole file.
//   node tools/test_channel_slices.mjs
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const repo = new URL("..", import.meta.url).pathname;
const { handleLive, onAir, schedule } = await import(join(repo, "worker/src/live.js"));
const { handleXtream } = await import(join(repo, "worker/src/xtream.js"));
let failures = 0;
const check = (l, ok, d = "") => { console.log(`${ok ? "PASS" : "FAIL"} ${l}${d ? `: ${d}` : ""}`); if (!ok) failures++; };

const out = mkdtempSync(join(tmpdir(), "aw-slices-"));
execFileSync("python3", [join(repo, "tools/build_channel_slices.py"), "--out", out]);
const whole = JSON.parse(readFileSync(join(repo, "channel-schedule.json")));
const files = readdirSync(join(out, "channel-schedule"));
check("one slice a channel", files.length === whole.channels.length && files.length > 0, `${files.length}`);

const streams = whole.channels.map((c, i) => ({ stream_id: i + 1, channel: c.id, epg_channel_id: c.id }));
let mode = "slices", asked = [];
globalThis.fetch = async (u) => {
  const p = new URL(u).pathname;
  asked.push(p);
  if (p === "/channel-schedule.json") return Response.json(whole);
  if (p.startsWith("/channel-schedule/")) {
    if (mode === "down") throw new Error("network");
    if (mode === "bad") return new Response("<html>");
    const f = p.split("/").pop();
    return mode === "slices" && files.includes(f) ? new Response(readFileSync(join(out, "channel-schedule", f))) : new Response("no", { status: 404 });
  }
  if (p === "/feeds/manifest.json") return Response.json({ build: "1" });
  if (p === "/feeds/xtream/live_streams.json") return Response.json(streams);
  return new Response("no", { status: 404 });
};

let compared = 0, differ = [];
for (const c of whole.channels) {
  const slice = await schedule(c.id);
  const days = Object.values(c.days);
  const from = Math.min(...days.map((d) => d.start)) - 3600;
  const to = Math.max(...days.map((d) => d.start + d.slots.reduce((n, s) => n + s[1] + whole.gap, 0))) + 3600;
  for (let t = from; t < to; t += 601) {
    compared++;
    if (JSON.stringify(onAir(slice, c.id, t)) !== JSON.stringify(onAir(whole, c.id, t))) differ.push(`${c.id}@${t}`);
  }
}
check("on air is the same from a slice and the whole file", differ.length === 0 && compared > 1000, `${compared} moments, ${differ.length} differ ${differ.slice(0, 3)}`);

// Inside the schedule, so /live has something to answer with whatever today is.
const day = Object.values(whole.channels[0].days)[1];
Date.now = () => (day.start + 4000) * 1000;
const live = async (path) => { asked = []; const r = await handleLive(new URL(`https://w${path}`), {}); return [r.status, r.headers.get("location")].join(" "); };
const epg = async (id) => (await handleXtream(new URL(`https://w/player_api.php?action=get_short_epg&stream_id=${id}`), {})).text();
const answers = {};
for (const m of ["slices", "missing", "down", "bad"]) {
  mode = m;
  answers[m] = [];
  for (const [i, c] of whole.channels.entries()) answers[m].push(await live(`/live/${c.id}.ts`), await epg(i + 1));
  if (m === "slices") check("a slice is read without the whole file", (await live(`/live/${whole.channels[0].id}`), !asked.includes("/channel-schedule.json")), asked.join(" "));
}
check("every channel answers 302", answers.slices.filter((_, i) => i % 2 === 0).every((a) => a.startsWith("302 https://")));
for (const m of ["missing", "down", "bad"]) check(`slices ${m}: the whole file gives the same answers`, JSON.stringify(answers[m]) === JSON.stringify(answers.slices));
mode = "slices";
check("an unknown channel is still 404", (await live("/live/no-such-channel")).startsWith("404"));
console.log(`${failures} failure(s)`);
process.exit(failures ? 1 : 0);
