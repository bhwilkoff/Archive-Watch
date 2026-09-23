/**
 * Watch Together rooms — SHAREPLAY §11, the transport half.
 *
 * A room is ONE ROW. Everything clever lives in the clients (§11.1): the host
 * publishes a state record and every client extrapolates between records, so
 * this has nothing to compute and nothing to stream.
 *
 *     code | film_id | position | at_server_ms | rate | paused | generation | touched_ms
 *
 * WHY THIS IS NOT A WEBSOCKET. Durable Objects are the natural fit and are not
 * on Cloudflare's free plan, and $0 is a hard constraint for this project
 * (CLAUDE.md). Workers KV is free but eventually consistent for up to 60
 * seconds, which would mean a PAUSE taking a minute to reach a guest —
 * unusable for the one message that has to be instant. D1 is strongly
 * consistent, already bound to this Worker for the privacy counter, and free
 * at this volume: four guests for two hours is ~14,400 reads and ~270 writes
 * against millions and 100k a day.
 *
 * WHAT IS STORED ABOUT PEOPLE: no account, no id, no IP. A row says what the
 * film is doing, and the only way to see it is to know a code somebody read
 * aloud to you. The one exception, chosen by the owner on 2026-09-23 so a host
 * can see that their friends arrived: each joined device sends an anonymous
 * random token every 30 s (`room_presence`), and only the COUNT of tokens seen
 * in the last minute is ever read out. The token is made fresh per join and
 * tied to nothing; its rows are deleted with the room. Rooms are deleted when
 * a host ends them and swept when they go quiet, so the table does not become
 * a record of what anyone watched — the same rule the counter beside it keeps.
 */

/**
 * THE CODE IS PUBLIC; CONTROL IS NOT.
 *
 * Learned from Tidbits Trivia (the owner's other app), whose own screen says
 * it in one line: *"The PIN is on the host screen, not the projector — the
 * room code alone cannot drive the show."* A code meant to be read aloud
 * cannot also be the credential, or everyone who hears it can drive.
 *
 * Archive Watch had exactly that hole: the owner decided hosts alone control
 * the film (§11.6) and the transport enforced nothing, so any guest who knew
 * a code could pause somebody's live broadcast.
 *
 * Ours is a long random token rather than Tidbits' six digits, because no
 * human ever types it — only the host's own app holds it.
 */
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

/** Crockford Base32, matching `StudioRoom.swift` exactly. */
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 4;

/**
 * The same normalisation the apps do, and it MUST stay the same or a code read
 * aloud would reach a different room depending on which end typed it.
 * `tools/test_studio_room.swift` §8.28 is the Swift side of this contract.
 */
export function normalizeCode(typed) {
  if (typeof typed !== "string") return null;
  let out = "";
  for (const ch of typed.toUpperCase()) {
    if (ch === " " || ch === "-" || ch === "_") continue;
    if (ch === "I" || ch === "L") { out += "1"; continue; }
    if (ch === "O") { out += "0"; continue; }
    if (ch === "U") return null;
    if (!ALPHABET.includes(ch)) return null;
    out += ch;
  }
  return out.length === CODE_LENGTH ? out : null;
}

function newHostKey() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function newCode() {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += ALPHABET[b % ALPHABET.length];
  return out;
}

/** A room nobody has touched for this long is over. */
const STALE_MS = 6 * 60 * 60 * 1000;   // six hours — longer than any film
const PRESENT_MS = 60 * 1000;           // two missed 30 s pings and a device is gone

/**
 * THE HOURLY SWEEP. A stale room used to be deleted only when somebody asked
 * for that exact code again, so a room nobody revisited stayed in D1 forever
 * with its presence rows — and privacy.html said it was deleted after six
 * hours (audit A14, 2026-09-23). Now it is.
 */
export async function sweepRooms(env, now = Date.now()) {
  const stale = now - STALE_MS;
  await env.DB.prepare(
    "DELETE FROM room_presence WHERE seen_ms < ?1 OR code IN (SELECT code FROM rooms WHERE touched_ms < ?2) OR code NOT IN (SELECT code FROM rooms)"
  ).bind(now - PRESENT_MS, stale).run();
  const r = await env.DB.prepare("DELETE FROM rooms WHERE touched_ms < ?1").bind(stale).run();
  return r.meta?.changes ?? 0;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function rowToState(r, nowMs) {
  // `host_key` is deliberately NOT in this object. It is returned once, at
  // creation, to the creator — a read handing it back would undo the whole
  // point of having it.
  return {
    code: r.code,
    filmID: r.film_id,
    position: r.position,
    // SECONDS, because the clients work in seconds and a unit change at the
    // boundary is how a sync bug gets written.
    atServerTime: r.at_server_ms / 1000,
    rate: r.rate,
    paused: !!r.paused,
    generation: r.generation,
    // THE SERVER'S OWN CLOCK, in the same response as the state (§11.6). The
    // client measures the round trip around this one request, so the offset
    // estimate of §11.2 costs no extra traffic at all — the poll IS the clock
    // sync. Omitting this would double the request count for nothing.
    serverTime: nowMs / 1000,
  };
}

export async function handleTogether(url, request, env) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  const now = Date.now();

  // POST /together/new  { filmID, position, rate, paused }
  if (url.pathname === "/together/new" && request.method === "POST") {
    let body;
    try { body = await request.json(); } catch { return json({ error: "bad body" }, 400); }
    const filmID = String(body.filmID || "");
    if (!filmID) return json({ error: "filmID required" }, 400);

    // A CODE IS CHECKED AGAINST LIVE ROOMS BEFORE IT IS ISSUED. This is one of
    // the two things that make four characters safe rather than merely short
    // (§11.9): the risk is a guess landing on a LIVE room, so the live set is
    // what must stay small. Ten attempts is far more than enough at any volume
    // this app will see, and failing loudly beats handing out a duplicate.
    for (let attempt = 0; attempt < 10; attempt++) {
      const code = newCode();
      try {
        const hostKey = newHostKey();
        await env.DB.prepare(
          "INSERT INTO rooms (code, film_id, position, at_server_ms, rate, paused, generation, touched_ms, host_key) " +
          "VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1, ?4, ?7)"
        ).bind(code, filmID, Number(body.position) || 0, now,
               Number(body.rate) || 1, body.paused ? 1 : 0, hostKey).run();
        // The key is returned ONCE, to the creator, and never again — a GET
        // must never be able to hand it out, or the split it exists for is
        // undone by the first poll.
        return json({ code, hostKey, serverTime: now / 1000 });
      } catch (e) {
        // A UNIQUE violation means the code is taken — try another. Anything
        // else is a real failure and must not be retried into a loop.
        if (!String(e).includes("UNIQUE")) return json({ error: "could not create" }, 500);
      }
    }
    return json({ error: "no free code" }, 503);
  }

  // POST /together/<code>/here  { token }  — a joined device says it is here.
  // No host key: guests are exactly who sends this. Only a count is read out.
  const here = url.pathname.match(/^\/together\/([^/]+)\/here\/?$/);
  if (here && request.method === "POST") {
    const hcode = normalizeCode(decodeURIComponent(here[1]));
    if (!hcode) return json({ error: "bad code" }, 400);
    let body;
    try { body = await request.json(); } catch { return json({ error: "bad body" }, 400); }
    const token = String(body.token || "");
    if (!/^[A-Za-z0-9]{16,64}$/.test(token)) return json({ error: "bad token" }, 400);
    const room = await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(hcode).first();
    if (!room) return json({ error: "no such room" }, 404);
    await env.DB.prepare(
      "INSERT INTO room_presence (code, token, seen_ms) VALUES (?1, ?2, ?3) " +
      "ON CONFLICT(code, token) DO UPDATE SET seen_ms = ?3"
    ).bind(hcode, token, now).run();
    return json({ ok: true });
  }

  // POST /together/<code>  — the host publishes a new state
  // GET  /together/<code>  — anyone reads it
  const m = url.pathname.match(/^\/together\/([^/]+)\/?$/);
  if (!m) return json({ error: "not found" }, 404);
  const code = normalizeCode(decodeURIComponent(m[1]));
  if (!code) return json({ error: "bad code" }, 400);

  if (request.method === "GET") {
    const r = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?1").bind(code).first();
    if (!r) return json({ error: "no such room" }, 404);
    if (now - r.touched_ms > STALE_MS) {
      await env.DB.prepare("DELETE FROM rooms WHERE code = ?1").bind(code).run();
      await env.DB.prepare("DELETE FROM room_presence WHERE code = ?1").bind(code).run();
      return json({ error: "room ended" }, 410);
    }
    const p = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM room_presence WHERE code = ?1 AND seen_ms > ?2"
    ).bind(code, now - PRESENT_MS).first();
    return json({ ...rowToState(r, now), present: (p && p.n) || 0 });
  }

  if (request.method === "POST") {
    let body;
    try { body = await request.json(); } catch { return json({ error: "bad body" }, 400); }

    // ENDING IS A DELETE, not a flag. A room that lingers is a row saying what
    // somebody watched, and §11's whole storage posture is that no such record
    // outlives the watching.
    // EVERY WRITE NEEDS THE HOST KEY. A guest has the code — they were told
    // it out loud — and that is deliberately not enough to drive the show.
    const room = await env.DB.prepare("SELECT host_key FROM rooms WHERE code = ?1")
      .bind(code).first();
    if (!room) return json({ error: "no such room" }, 404);
    const offered = request.headers.get("x-aw-host-key") || body.hostKey || "";
    if (!room.host_key || offered !== room.host_key) {
      return json({ error: "only the host can change the film" }, 403);
    }

    if (body.end === true) {
      await env.DB.prepare("DELETE FROM rooms WHERE code = ?1").bind(code).run();
      await env.DB.prepare("DELETE FROM room_presence WHERE code = ?1").bind(code).run();
      return json({ ended: true });
    }

    // The generation is bumped HERE rather than sent by the client, so two
    // hosts cannot disagree about it and a client cannot freeze it by sending
    // the same number twice. Clients use it only to notice change (§11.6).
    const res = await env.DB.prepare(
      "UPDATE rooms SET film_id = ?2, position = ?3, at_server_ms = ?4, rate = ?5, " +
      "paused = ?6, generation = generation + 1, touched_ms = ?4 WHERE code = ?1"
    ).bind(code, String(body.filmID || ""), Number(body.position) || 0, now,
           Number(body.rate) || 1, body.paused ? 1 : 0).run();
    if (!res.meta || res.meta.changes === 0) return json({ error: "no such room" }, 404);
    const r = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?1").bind(code).first();
    return json(rowToState(r, now));
  }

  return json({ error: "method not allowed" }, 405);
}
