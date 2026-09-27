/**
 * /live/<channel> — a channel as a link any IPTV player can open.
 *
 * Owner, 2026-09-27: "you should be able to combine the playlist and the live
 * tv into a single playlist that can be read for both." A static site cannot
 * serve a live stream, but it does not have to: channel-schedule.json already
 * says what is on every channel at every second (Decision 144), and archive.org
 * serves any MP4 from a given second (`?start=<s>` returns a shorter, playable
 * file — measured 2026-09-27: The General, 6,405 s, at ?start=600 is 5,805 s
 * and its first frame is the reference frame at 600 s, 37 dB). So a channel is
 * a 302 to the program airing now, at the second it has reached. When that
 * film ends the player asks again, and is sent to the next one.
 *
 * Reads only the published schedule; stores nothing, logs nothing.
 */

import { tally } from "./tally.js";

const SITE = "https://archivewatch.org";
const SCHEDULE_TTL = 600;

export async function schedule() {
  const r = await fetch(`${SITE}/channel-schedule.json`,
    { cf: { cacheTtl: SCHEDULE_TTL, cacheEverything: true } });
  if (!r.ok) throw new Error(`schedule ${r.status}`);
  return r.json();
}

/** The program on `channel` at `now` (epoch seconds): the one airing, or the
 *  next one if `now` falls in the gap between two. */
export function onAir(file, channelId, now) {
  const ch = file.channels.find((c) => c.id === channelId);
  if (!ch) return null;
  let found = null;
  for (const key of Object.keys(ch.days).sort()) {
    const day = ch.days[key];
    let t = day.start;
    for (const [id, secs] of day.slots) {
      const end = t + secs;
      if (found) {
        const p = file.programs[id];
        found.next = p ? { id, title: p[0], url: p[2] } : null;
        return found;
      }
      if (now < end) {
        const p = file.programs[id];
        if (!p) return null;
        const offset = Math.max(0, now - t);
        // The slot can outlast the film: days published before 2026-09-27
        // gave a film of two minutes or less a 90-minute slot. What is left
        // is measured against the FILM's length, never the slot's.
        const length = p[1] && p[1] > 0 ? Math.min(secs, p[1]) : secs;
        found = { id, title: p[0], url: p[2], offset, ends: end, length,
                  remaining: Math.max(0, t + length - Math.max(now, t)), next: null };
      }
      t = end + file.gap;
    }
  }
  return found;
}

// Joining a film this close to its end hands the player a scrap: archive.org
// answers ?start=100 on a 104 s film with 4 s and 39 KB, which may hold no
// whole picture (measured 2026-09-27; the owner's Documentary channel "wouldn't
// play" on Egyptian Fakir with Dancing Monkey). Inside the last minute, or the
// last quarter of a short film, the channel starts the NEXT program instead.
const TAIL = 60;

export function joinURL(p) {
  if (p.remaining < Math.max(TAIL, p.length / 4) && p.next) {
    return p.next.url;
  }
  return p.offset >= 10 ? `${p.url}?start=${Math.floor(p.offset)}` : p.url;
}

export async function handleLive(url, env) {
  const m = url.pathname.match(/^\/live\/([a-z0-9-]+?)(?:\.(?:mp4|ts|m3u8))?\/?$/);
  const headers = { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" };
  if (!m) return new Response("Unknown channel\n", { status: 404, headers });
  let file;
  try {
    file = await schedule();
  } catch {
    return new Response("The channel guide could not be loaded.\n", { status: 503, headers });
  }
  const now = Math.floor(Date.now() / 1000);
  const p = onAir(file, m[1], now);
  if (!p) return new Response("Unknown channel\n", { status: 404, headers });
  await tally(env, "channel");
  return new Response(null, { status: 302, headers: { ...headers, Location: joinURL(p) } });
}
