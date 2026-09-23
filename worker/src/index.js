/**
 * archivewatch-pulse — a page-view counter that collects nothing about anyone.
 *
 * archivewatch.org had no usage data at all: GitHub Pages keeps no logs we can
 * read, so there was nothing to recover after the fact. Every way of measuring
 * it changes what privacy.html promises, and the owner chose the version that
 * changes it least — a counter we own, with no third party in the path.
 *
 * WHAT IS STORED, and this is the entire schema:
 *
 *     day (YYYY-MM-DD) | path | count
 *
 * WHAT IS NOT STORED, deliberately and permanently: the IP address, any
 * cookie, any session or visitor id, the user agent, the referrer, the
 * country, the time of day. Nothing here can be joined to a person, to
 * another row, or to a second visit — including by us. A row saying
 * `2026-09-09 | /item/metropolis | 12` is the finest grain that exists.
 *
 * That is a real cost: no referrers, no countries, no returning-visitor rate,
 * no funnel. It buys the sentence in privacy.html being true.
 *
 * The path is normalised to a SHAPE, not a URL, so a film id never becomes a
 * row of its own — otherwise the table would slowly become a record of what
 * individual people watched, which is the thing we said we would not keep.
 */

import { handleTogether, sweepRooms } from "./together.js";

const ALLOW = "https://archivewatch.org";

// A path becomes one of a small fixed set. Anything unrecognised is "/other",
// never the raw path: an unbounded key space is how a counter turns into a log.
function shape(raw) {
  // A page LOAD, as opposed to an in-app route change. Its own key so the two
  // can never be summed: a visit that walks six surfaces is one visit and
  // seven route views, and reporting the second as the first inflates the
  // audience by however much people browse.
  if (raw === "(visit)") return "(visit)";
  let p;
  try {
    p = new URL(raw, ALLOW).pathname.toLowerCase();
  } catch {
    return "/other";
  }
  if (p === "" || p === "/" || p === "/index.html") return "/";
  if (p.startsWith("/item/")) return "/item";
  if (p.startsWith("/series/")) return "/series";
  if (p.startsWith("/curate")) return "/curate";
  if (p.startsWith("/pulse")) return "/pulse";
  // The viewer's own surfaces, which arrive as hash routes. Without these every
  // one of them collapsed into "/other" and the breakdown said nothing.
  for (const view of ["/browse", "/search", "/library", "/channels", "/surprise",
                      "/collections", "/collection", "/cartoons", "/playlist",
                      "/about"]) {
    if (p === view || p.startsWith(view + "/")) return view;
  }
  for (const known of ["/privacy", "/terms", "/support", "/feed.xml", "/feed.json"]) {
    if (p.startsWith(known)) return known;
  }
  return "/other";
}

/* An archive id out of a route, or nothing. Deliberately narrow:
 *   * ONLY /item/<id> and /series/<id> — never /list/, which carries a
 *     viewer's whole playlist in its URL and is already dropped in the browser
 *     before it ever reaches us.
 *   * the id is length-capped and character-filtered, so a crafted route
 *     cannot write arbitrary rows.
 *   * `k=play` marks a film that actually started playing; anything else is
 *     the detail page merely being opened.
 * NOTE the case: shape() lowercases because a SURFACE is case-insensitive, but
 * an archive id is NOT — `MacleansToot` and `macleanstoot` are two different
 * items — so this reads the path unlowered. */
function titleOf(raw, k) {
  let p;
  try { p = new URL(raw, ALLOW).pathname; } catch { return null; }
  const m = /^\/(item|series)\/([A-Za-z0-9._@:+-]{1,120})\/?$/.exec(p);
  if (!m) return null;
  // Three kinds, kept apart because they answer different questions: `open` is
  // a detail page (interest), `play` is a film someone chose to watch
  // (audience), `ambient` is a muted Party Play lineup (present, but nobody
  // picked it). Summing them would answer none of the three.
  const kind = k === "play" ? "play" : k === "ambient" ? "ambient" : "open";
  return { id: (m[1] === "series" ? "series:" : "") + m[2], kind };
}

const cors = {
  "Access-Control-Allow-Origin": ALLOW,
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(sweepRooms(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);

    // Watch Together rooms (SHAREPLAY §11). Same Worker, same D1 — the
    // sync transport needs no infrastructure of its own, which is most of
    // why it fits the $0 constraint at all. BEFORE the global preflight:
    // that one allows only archivewatch.org, so a web-TV package (origin
    // null) could never POST "I'm here" (audit A14).
    if (url.pathname.startsWith("/together")) {
      return handleTogether(url, request, env);
    }

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    // The beacon. Answers 204 with no body: nothing is set, nothing returned,
    // and a failure here must never be visible to a reader of the site.
    if (url.pathname === "/beacon" && request.method === "POST") {
      const day = new Date().toISOString().slice(0, 10);
      const raw = url.searchParams.get("p") || "/";
      const path = shape(raw);
      try {
        await env.DB.prepare(
          "INSERT INTO views (day, path, count) VALUES (?1, ?2, 1) " +
          "ON CONFLICT(day, path) DO UPDATE SET count = count + 1"
        ).bind(day, path).run();
      } catch {
        // A counter is not worth an error page.
      }
      // WHICH TITLE, in its OWN table. The `views` table above is untouched
      // and still holds exactly what privacy.html describes; this is a second
      // aggregate at the same grain — day, thing, count — and nothing else.
      //
      // It is the same shape of row as `/browse | 412`, about a FILM rather
      // than a surface. Still no IP, no cookie, no session or visitor id, no
      // user agent, no referrer, no country, no time of day — so a row here
      // cannot be joined to a person, to another row, or to a second visit,
      // including by us.
      //
      // `kind` keeps OPENED apart from PLAYED, because they are different
      // measurements and summing them would answer neither question: a detail
      // page opened is interest, a film played is an audience.
      const t = titleOf(raw, url.searchParams.get("k"));
      if (t) {
        try {
          await env.DB.prepare(
            "INSERT INTO titles (day, id, kind, count) VALUES (?1, ?2, ?3, 1) " +
            "ON CONFLICT(day, id, kind) DO UPDATE SET count = count + 1"
          ).bind(day, t.id, t.kind).run();
        } catch { /* same rule: a counter is not worth an error page */ }
      }
      return new Response(null, { status: 204, headers: cors });
    }

    // The read side for titles. Public like /views: counts of PUBLIC films on
    // a public site, with nothing in them about anybody.
    if (url.pathname === "/titles") {
      const days = Math.min(400, Math.max(1, Number(url.searchParams.get("days") || 28)));
      const since = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
      try {
        const { results } = await env.DB.prepare(
          "SELECT day, id, kind, count FROM titles WHERE day >= ?1 ORDER BY day, id"
        ).bind(since).all();
        return Response.json({ since, rows: results || [] },
                             { headers: { ...cors, "Cache-Control": "public, max-age=300" } });
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500, headers: cors });
      }
    }

    // The read side, for the dashboard. Public on purpose: these numbers are
    // aggregate counts of a public site, and there is nothing here to protect.
    if (url.pathname === "/views") {
      const days = Math.min(400, Math.max(1, Number(url.searchParams.get("days") || 60)));
      const since = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
      try {
        const { results } = await env.DB.prepare(
          "SELECT day, path, count FROM views WHERE day >= ?1 ORDER BY day, path"
        ).bind(since).all();
        return Response.json({ since, rows: results || [] },
                             { headers: { ...cors, "Cache-Control": "public, max-age=300" } });
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500, headers: cors });
      }
    }

    /* ── Vendor drop box ───────────────────────────────────────────────────
     *
     * Roku has no analytics API and will not have one: its dashboards are
     * Looker, and the only automated route out is a SCHEDULED DELIVERY to
     * email, a webhook, S3 or SFTP. S3 needs real AWS (Looker's form has no
     * custom-endpoint field, so R2 cannot stand in) and this is a $0
     * platform, so the webhook is the route — and the endpoint is this
     * Worker, which already exists.
     *
     * THE BODY IS STORED RAW AND PARSED OFFLINE. Looker's webhook payload
     * shape is not documented anywhere reachable, so this commits to nothing
     * about it: whatever arrives is kept verbatim with its content type, and
     * the first real delivery is what teaches us the format. An ingest that
     * guesses a schema fails silently on the one delivery that matters.
     *
     * This holds NO user data and sits in no viewer's path — it is a store's
     * own aggregate report about our app, which is why it does not touch what
     * privacy.html promises or the no-backend rule (Decision 028).
     */
    if (url.pathname.startsWith("/ingest/") && request.method === "POST") {
      if (!env.INGEST_TOKEN || url.searchParams.get("t") !== env.INGEST_TOKEN) {
        // 404, not 403: an unauthenticated prober learns nothing about what
        // lives here.
        return new Response("not found", { status: 404 });
      }
      const vendor = url.pathname.slice("/ingest/".length).toLowerCase()
                        .replace(/[^a-z0-9_-]/g, "").slice(0, 32) || "unknown";
      const body = await request.text();
      // D1 caps a row near 1 MB. A delivery that does not fit is recorded as a
      // REFUSAL rather than truncated: half a report read as a whole one is
      // the kind of quiet wrong number this whole dashboard exists to avoid.
      const tooBig = body.length > 900000;
      try {
        await env.DB.prepare(
          "INSERT INTO drops (vendor, received, content_type, bytes, body) " +
          "VALUES (?1, ?2, ?3, ?4, ?5)"
        ).bind(vendor, new Date().toISOString(),
               request.headers.get("content-type") || "",
               body.length,
               tooBig ? "" : body).run();
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500 });
      }
      return Response.json({ stored: !tooBig, bytes: body.length,
                             refused: tooBig ? "over 900000 bytes" : null });
    }

    // The collector reads pending drops, then acks them. Token-gated in both
    // directions: unlike /views, a vendor report is not ours to publish.
    if (url.pathname === "/drops") {
      if (!env.INGEST_TOKEN || url.searchParams.get("t") !== env.INGEST_TOKEN) {
        return new Response("not found", { status: 404 });
      }
      if (request.method === "POST") {                   // ack = delete
        const id = Number(url.searchParams.get("id") || 0);
        if (!id) return Response.json({ error: "id required" }, { status: 400 });
        await env.DB.prepare("DELETE FROM drops WHERE id = ?1").bind(id).run();
        return Response.json({ deleted: id });
      }
      const vendor = url.searchParams.get("vendor") || "";
      const q = vendor
        ? env.DB.prepare("SELECT * FROM drops WHERE vendor = ?1 ORDER BY id LIMIT 20").bind(vendor)
        : env.DB.prepare("SELECT * FROM drops ORDER BY id LIMIT 20");
      try {
        const { results } = await q.all();
        return Response.json({ rows: results || [] });
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500 });
      }
    }

    return new Response("archivewatch-pulse: /beacon, /views, /titles, /ingest/<vendor>, /drops", {
      status: 200, headers: { ...cors, "Content-Type": "text/plain" },
    });
  },
};
