/**
 * One more to today's anonymous tally for the feeds and the assistant
 * (`feeds_days`: day | kind | count). Owner, 2026-09-27: "are we going to keep
 * track of how many people are using the feeds/mcp on the Archive Watch Pulse
 * page?" The Worker already answers every one of these requests to provide the
 * feature (Decision 142's rule), so it counts them — and writes nothing else:
 * no address, no film, no username, no query. Kinds:
 *   signin   an IPTV player loading the Xtream source (a session, not a person)
 *   play     a film or episode started through the Xtream API
 *   channel  a channel tuned (the playlist's /live/<id> or Xtream's /live/)
 *   mcp      an assistant's tool call
 * A failure here never fails the request it counts.
 */
export async function tally(env, kind) {
  if (!env || !env.DB) return;
  try {
    await env.DB.prepare(
      "INSERT INTO feeds_days (day, kind, count) VALUES (?1, ?2, 1) " +
      "ON CONFLICT(day, kind) DO UPDATE SET count = count + 1"
    ).bind(new Date().toISOString().slice(0, 10), kind).run();
  } catch { /* a counter is not worth a failed request */ }
}
