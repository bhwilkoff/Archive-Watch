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

const cors = {
  "Access-Control-Allow-Origin": ALLOW,
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    // The beacon. Answers 204 with no body: nothing is set, nothing returned,
    // and a failure here must never be visible to a reader of the site.
    if (url.pathname === "/beacon" && request.method === "POST") {
      const day = new Date().toISOString().slice(0, 10);
      const path = shape(url.searchParams.get("p") || "/");
      try {
        await env.DB.prepare(
          "INSERT INTO views (day, path, count) VALUES (?1, ?2, 1) " +
          "ON CONFLICT(day, path) DO UPDATE SET count = count + 1"
        ).bind(day, path).run();
      } catch {
        // A counter is not worth an error page.
      }
      return new Response(null, { status: 204, headers: cors });
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

    return new Response("archivewatch-pulse: /beacon, /views", {
      status: 200, headers: { ...cors, "Content-Type": "text/plain" },
    });
  },
};
