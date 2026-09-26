/**
 * /mcp — a Model Context Protocol endpoint so an assistant can find films in
 * Archive Watch and hand back links that play (ORPHANED-FILMS #4).
 *
 * Owner rule: it is documented on one website page (/feeds/) and appears in
 * no app. It answers only from files the site already publishes — the
 * catalog index cut into small shards by tools/build_mcp_data.py, and the
 * detail shards the web viewer reads — so it can say nothing the apps would
 * not show, and every word it returns is catalog data with its source named.
 *
 * Nothing is stored or counted: no D1 write, no log line, no query kept.
 * Stateless Streamable HTTP (JSON responses, no session id).
 */

const SITE = "https://archivewatch.org";
const PROTOCOL = "2025-06-18";
const STOP = new Set(["the", "a", "an", "of", "and", "in", "on", "to", "de", "la", "le", "el"]);
const KIND = {
  "feature-film": "Feature film", "silent-film": "Silent film", "short-film": "Short film",
  animation: "Animated film", "tv-special": "Television special", newsreel: "Newsreel",
  documentary: "Documentary", ephemeral: "Ephemeral film", "home-movie": "Home movie",
  "tv-series": "Television series", commercial: "Commercial",
};
const SYNOPSIS_SOURCE = {
  tmdb: "TMDb", omdb: "OMDb", wikipedia: "Wikipedia", tvmaze: "TVmaze",
};

const TOOLS = [
  {
    name: "search_films",
    description: "Search Archive Watch's public-domain film catalog by words in a title or a director's name. Returns films with their year, kind, length and a link that plays them.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Words from the title or director, e.g. \"nosferatu\" or \"keaton general\"" },
        max_minutes: { type: "integer", description: "Only films this long or shorter" },
        from_year: { type: "integer" },
        to_year: { type: "integer" },
      },
      required: ["query"],
    },
  },
  {
    name: "get_film",
    description: "Everything Archive Watch knows about one film: synopsis with its source, cast, genres, archive.org reviewers' own words, and links.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "The film's id, as search_films returns it" } },
      required: ["id"],
    },
  },
  {
    name: "more_like_this",
    description: "Films Archive Watch ranks as related to this one, by shared series, director, cast, writer or subject.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string" } },
      required: ["id"],
    },
  },
];

export function words(text) {
  return (text || "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .match(/[a-z0-9]+/g)?.filter((w) => w.length >= 2 && !STOP.has(w)) || [];
}

export function fnvShard(id) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(id)) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return (h & 0xff).toString(16).padStart(2, "0");
}

async function getJSON(path, memo) {
  if (!memo.has(path)) {
    memo.set(path, fetch(`${SITE}/${path}`, { cf: { cacheTtl: 3600, cacheEverything: true } })
      .then((r) => (r.ok ? r.json() : {})).catch(() => ({})));
  }
  return memo.get(path);
}

async function filmRow(id, memo) {
  const shard = await getJSON(`mcp/films/${fnvShard(id)}.json`, memo);
  const r = shard[id];
  if (!r) return null;
  const [title, year, type, minutes, director] = r;
  return {
    id, title, year: year || null, kind: KIND[type] || "Film", minutes: minutes || null,
    director: director || null, link: `${SITE}/item/${encodeURIComponent(id)}/`,
  };
}

export async function searchFilms(args, memo) {
  const qs = [...new Set(words(args.query))].slice(0, 5);
  if (!qs.length) return { films: [], note: "No searchable words in the query." };
  let hits = null;
  const votes = new Map();
  for (const q of qs) {
    const shard = await getJSON(`mcp/words/${q.slice(0, 3)}.json`, memo);
    const found = new Set();
    // The LAST word, if three letters or more, is matched as a prefix, so a
    // half-typed word still finds.
    const prefix = q === qs[qs.length - 1] && q.length >= 3;
    const keys = prefix ? Object.keys(shard).filter((w) => w.startsWith(q)) : [q];
    for (const w of keys) for (const [id, v] of shard[w] || []) { found.add(id); votes.set(id, v); }
    hits = hits ? new Set([...hits].filter((id) => found.has(id))) : found;
    if (!hits.size) break;
  }
  const ranked = [...hits].sort((a, b) => (votes.get(b) || 0) - (votes.get(a) || 0));
  const out = [];
  for (const id of ranked) {
    if (out.length >= 10) break;
    const f = await filmRow(id, memo);
    if (!f) continue;
    if (args.max_minutes && !(f.minutes && f.minutes <= args.max_minutes)) continue;
    if (args.from_year && !(f.year && f.year >= args.from_year)) continue;
    if (args.to_year && !(f.year && f.year <= args.to_year)) continue;
    out.push(f);
  }
  return { films: out, matched: hits.size };
}

async function detail(id, memo) {
  const shard = await getJSON(`details/${fnvShard(id)}.json`, memo);
  return shard[id] || null;
}

export async function getFilm(args, memo) {
  const f = await filmRow(String(args.id || ""), memo);
  if (!f) return { error: "Not in Archive Watch." };
  const d = await detail(f.id, memo);
  if (d) {
    const x = d[9] || {};
    if (d[1]) {
      f.synopsis = d[1];
      f.synopsis_source = SYNOPSIS_SOURCE[(x.ss || "").toLowerCase()]
        || "the uploader's description on archive.org";
    }
    f.cast = (d[3] || []).slice(0, 8).map((c) => (Array.isArray(c) ? c[0] : c));
    f.genres = d[4] || [];
    if (x.w) f.writer = x.w;
    if (x.fr) f.series = x.fr;
    const reviews = (d[8]?.rv || []).slice(0, 2).map(([stars, title, body, reviewer, date]) =>
      ({ stars, title, text: body, reviewer, date, source: "archive.org review" }));
    if (reviews.length) f.reviews = reviews;
    if (d[7]?.length) f.subtitles = d[7].map((c) => c[1]);
  }
  f.archive_org = `https://archive.org/details/${encodeURIComponent(f.id)}`;
  return f;
}

export async function moreLikeThis(args, memo) {
  const id = String(args.id || "");
  const d = await detail(id, memo);
  if (!d) return { error: "Not in Archive Watch." };
  const films = [];
  for (const rid of (d[10] || []).slice(0, 10)) {
    const f = await filmRow(rid, memo);
    if (f) films.push(f);
  }
  return { films };
}

const HANDLERS = { search_films: searchFilms, get_film: getFilm, more_like_this: moreLikeThis };

function rpc(id, result) {
  return { jsonrpc: "2.0", id, result };
}
function rpcError(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

async function answer(msg) {
  if (!msg || msg.jsonrpc !== "2.0" || typeof msg.method !== "string") {
    return rpcError(msg?.id ?? null, -32600, "Invalid request");
  }
  if (msg.id === undefined) return null; // a notification: nothing to say
  switch (msg.method) {
    case "initialize":
      return rpc(msg.id, {
        protocolVersion: PROTOCOL,
        capabilities: { tools: {} },
        serverInfo: { name: "archive-watch", version: "1.0.0" },
        instructions: "Find public-domain films in Archive Watch. Give people the film's link; it plays in the browser and in the Archive Watch apps.",
      });
    case "ping":
      return rpc(msg.id, {});
    case "tools/list":
      return rpc(msg.id, { tools: TOOLS });
    case "tools/call": {
      const h = HANDLERS[msg.params?.name];
      if (!h) return rpcError(msg.id, -32602, `Unknown tool: ${msg.params?.name}`);
      const result = await h(msg.params.arguments || {}, new Map());
      return rpc(msg.id, {
        content: [{ type: "text", text: JSON.stringify(result) }],
        structuredContent: result,
        isError: Boolean(result.error),
      });
    }
    default:
      return rpcError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
}

const HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Protocol-Version",
};

export async function handleMCP(request) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: HEADERS });
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { ...HEADERS, Allow: "POST" } });
  }
  let body;
  try { body = await request.json(); } catch {
    return new Response(JSON.stringify(rpcError(null, -32700, "Parse error")), { status: 400, headers: HEADERS });
  }
  const batch = Array.isArray(body);
  const replies = (await Promise.all((batch ? body : [body]).map(answer))).filter(Boolean);
  if (!replies.length) return new Response(null, { status: 202, headers: HEADERS });
  return new Response(JSON.stringify(batch ? replies : replies[0]), { headers: HEADERS });
}
