/**
 * Removal requests (docs/TAKEDOWNS.md, Decision 175).
 *
 * The form on takedown.html posts here. A requester's name and contact details
 * are stored in this private table and nowhere else: the repository is public,
 * and so are its Actions logs, so the check reads a case through a token and
 * writes back only what it found about the file. No IP address is stored; the
 * rate limit is counted by Cloudflare for the window only.
 */

const RETAIN_MS = 3 * 365 * 24 * 3600 * 1000;   // the copyright limitation period
const STATUSES = ["open", "held", "approved", "removed", "declined", "closed"];
const CLOSED = ["removed", "declined", "closed"];
const SOURCES = ["form", "email", "google"];
const MAX = { links: 4000, work: 1000, reason: 4000, name: 200, org: 200,
              email: 254, phone: 40, address: 500, signature: 200,
              external_ref: 200, note: 2000 };
// Crockford Base32, the alphabet of a Watch Together code: nothing misread.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", ...headers } });
}

function newRef() {
  const b = crypto.getRandomValues(new Uint8Array(8));
  return "TD-" + Array.from(b, (x) => ALPHABET[x % 32]).join("");
}

function field(body, key) {
  const v = typeof body[key] === "string" ? body[key].trim() : "";
  return v.slice(0, MAX[key]);
}

/** Every element a notice needs, or the name of the first one missing. */
export function missing(c) {
  if (!c.links) return "links";
  if (!c.name) return "name";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.email)) return "email";
  if (c.kind === "other") return c.reason ? null : "reason";
  if (!c.work) return "work";
  if (!c.address) return "address";
  if (!c.phone) return "phone";
  if (!c.goodFaith) return "goodFaith";
  if (!c.accurate) return "accurate";
  if (!c.signature) return "signature";
  return null;
}

function read(body) {
  const c = {};
  for (const k of Object.keys(MAX)) c[k] = field(body, k);
  c.kind = body.kind === "other" ? "other" : "copyright";
  c.goodFaith = body.goodFaith === true;
  c.accurate = body.accurate === true;
  return c;
}

async function insert(env, c, source, complete) {
  const ref = newRef();
  await env.DB.prepare(
    `INSERT INTO takedown_cases (ref, created_ms, status, kind, complete, source,
       external_ref, links, work, reason, name, org, email, phone, address, signature)
     VALUES (?1, ?2, 'open', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)`
  ).bind(ref, Date.now(), c.kind, complete ? 1 : 0, source, c.external_ref || null,
         c.links, c.work || null, c.reason || null, c.name || null, c.org || null,
         c.email || null, c.phone || null, c.address || null, c.signature || null).run();
  return ref;
}

async function authorized(request, env) {
  const given = (request.headers.get("Authorization") || "").replace(/^Bearer /, "");
  if (!env.TAKEDOWN_TOKEN || given.length !== env.TAKEDOWN_TOKEN.length) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(env.TAKEDOWN_TOKEN);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function handleTakedown(url, request, env, cors) {
  // The public door: the form, and nothing else.
  if (url.pathname === "/takedown") {
    if (request.method !== "POST") return json({ error: "method" }, 405, cors);
    if (env.TAKEDOWN_LIMITER) {
      const key = request.headers.get("cf-connecting-ip") || "unknown";
      const { success } = await env.TAKEDOWN_LIMITER.limit({ key });
      if (!success) return json({ error: "busy" }, 429, cors);
    }
    let body;
    try { body = await request.json(); } catch { return json({ error: "body" }, 400, cors); }
    // A field no person can see. A filled one is a script, answered as if it
    // worked so it learns nothing.
    if (body.website) return json({ ref: newRef() }, 200, cors);
    const c = read(body);
    const gap = missing(c);
    if (gap) return json({ error: "missing", field: gap }, 400, cors);
    const ref = await insert(env, c, "form", c.kind === "copyright");
    return json({ ref }, 200, cors);
  }

  // Everything below is the owner's tools and the check, by token.
  if (!(await authorized(request, env))) return json({ error: "forbidden" }, 403, cors);

  if (url.pathname === "/takedown/cases" && request.method === "POST") {
    // A notice that arrived some other way: Google, or email to the agent.
    let body;
    try { body = await request.json(); } catch { return json({ error: "body" }, 400, cors); }
    const c = read(body);
    if (!c.links) return json({ error: "missing", field: "links" }, 400, cors);
    const source = SOURCES.includes(body.source) ? body.source : "email";
    return json({ ref: await insert(env, c, source, body.complete === true) }, 200, cors);
  }

  if (url.pathname === "/takedown/cases" && request.method === "GET") {
    // The check's view: what it needs to judge a file, and no person.
    const status = (url.searchParams.get("status") || "open,approved,held").split(",")
      .filter((s) => STATUSES.includes(s));
    const marks = status.map((_, i) => `?${i + 1}`).join(",");
    const { results } = await env.DB.prepare(
      `SELECT ref, created_ms, status, kind, complete, source, links, work, verdict
       FROM takedown_cases WHERE status IN (${marks}) ORDER BY created_ms LIMIT 50`
    ).bind(...status).run();
    return json({ cases: results }, 200, cors);
  }

  const m = url.pathname.match(/^\/takedown\/cases\/(TD-[0-9A-Z]{8})$/);
  if (m && request.method === "GET") {
    const row = await env.DB.prepare("SELECT * FROM takedown_cases WHERE ref = ?1")
      .bind(m[1]).first();
    return row ? json(row, 200, cors) : json({ error: "unknown" }, 404, cors);
  }
  if (m && request.method === "POST") {
    let body;
    try { body = await request.json(); } catch { return json({ error: "body" }, 400, cors); }
    if (!STATUSES.includes(body.status)) return json({ error: "status" }, 400, cors);
    const closed = CLOSED.includes(body.status) ? Date.now() : null;
    const r = await env.DB.prepare(
      `UPDATE takedown_cases SET status = ?2, closed_ms = ?3,
         verdict = COALESCE(?4, verdict), note = COALESCE(?5, note) WHERE ref = ?1`
    ).bind(m[1], body.status, closed,
           body.verdict ? JSON.stringify(body.verdict).slice(0, 8000) : null,
           field(body, "note") || null).run();
    return r.meta.changes ? json({ ok: true }, 200, cors) : json({ error: "unknown" }, 404, cors);
  }
  return json({ error: "route" }, 404, cors);
}

/** The retention promise in privacy.html. */
export async function sweepTakedowns(env, now = Date.now()) {
  await env.DB.prepare(
    `UPDATE takedown_cases SET name = NULL, org = NULL, email = NULL, phone = NULL,
       address = NULL, signature = NULL, reason = NULL, work = NULL
     WHERE closed_ms IS NOT NULL AND closed_ms < ?1 AND email IS NOT NULL`
  ).bind(now - RETAIN_MS).run();
}
