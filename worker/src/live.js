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
  for (const key of Object.keys(ch.days).sort()) {
    const day = ch.days[key];
    let t = day.start;
    for (const [id, secs] of day.slots) {
      const end = t + secs;
      if (now < end) {
        const p = file.programs[id];
        if (!p) return null;
        return { id, title: p[0], url: p[2], offset: Math.max(0, now - t), ends: end };
      }
      t = end + file.gap;
    }
  }
  return null;
}

export async function handleLive(url) {
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
  // Seconds under ten are the opening credits; the whole file is better
  // than a rewritten one for so little.
  const target = p.offset >= 10 ? `${p.url}?start=${Math.floor(p.offset)}` : p.url;
  return new Response(null, { status: 302, headers: { ...headers, Location: target } });
}
