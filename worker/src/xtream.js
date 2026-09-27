/**
 * The Xtream API, for IPTV players (UHF, TiviMate, IPTV Smarters).
 *
 * Owner, 2026-09-27: "I noticed the information about the films isn't coming
 * through on the playlist." An M3U can carry a title, a poster and a group and
 * nothing more; the players that show a Movies section with plot, cast,
 * director, rating and backdrop read it from this API (docs/research/
 * IPTV-FEEDS.md). Everything answered here is a file the pipeline published in
 * /feeds/xtream/ (tools/build_film_feeds.py); playback is a redirect to the
 * film's own file on archive.org, and a channel joins its film at the second
 * the one clock has reached (live.js).
 *
 * Any username and password are accepted: there are no accounts, and the
 * fields exist only because the protocol has them. Nothing is stored or logged.
 */

import { joinURL, onAir, schedule } from "./live.js";

const SITE = "https://archivewatch.org";
const FEEDS = `${SITE}/feeds/xtream`;
const SHARDS = 256;
const TTL = 3600;

const json = (body) => new Response(JSON.stringify(body), {
  headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*",
             "Cache-Control": "public, max-age=600" },
});
const redirect = (to) => new Response(null, {
  status: 302, headers: { Location: to, "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" },
});

// Whole lists are passed through as they are: parsing a 6 MB list would spend
// the free Worker's CPU allowance on one request.
async function pass(name) {
  const r = await fetch(`${FEEDS}/${name}`, { cf: { cacheTtl: TTL, cacheEverything: true } });
  if (!r.ok) throw new Error(`${name} ${r.status}`);
  return new Response(r.body, {
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*",
               "Cache-Control": "public, max-age=600" },
  });
}

async function feed(name) {
  const r = await fetch(`${FEEDS}/${name}`, { cf: { cacheTtl: TTL, cacheEverything: true } });
  if (!r.ok) throw new Error(`${name} ${r.status}`);
  return r.json();
}

async function vodInfo(id) {
  const n = Number(id);
  if (!Number.isInteger(n)) return null;
  const shard = await feed(`info/${n % SHARDS}.json`);
  return shard[String(n)] || null;
}

async function episodeURL(id) {
  const n = Number(id);
  if (!Number.isInteger(n)) return null;
  const shard = await feed(`episodes/${n % SHARDS}.json`);
  return shard[String(n)] || null;
}

async function liveTarget(streamId) {
  const channels = await feed("live_streams.json");
  const ch = channels.find((c) => String(c.stream_id) === String(streamId));
  if (!ch) return null;
  const p = onAir(await schedule(), ch.channel, Math.floor(Date.now() / 1000));
  return p ? joinURL(p) : null;
}

const b64 = (s) => btoa(unescape(encodeURIComponent(s || "")));
const clock = (t) => new Date(t * 1000).toISOString().replace("T", " ").slice(0, 19);

async function shortEpg(streamId, limit) {
  const channels = await feed("live_streams.json");
  const ch = channels.find((c) => String(c.stream_id) === String(streamId));
  if (!ch) return { epg_listings: [] };
  const file = await schedule();
  const c = file.channels.find((x) => x.id === ch.channel);
  const now = Math.floor(Date.now() / 1000);
  const out = [];
  for (const key of Object.keys(c.days).sort()) {
    let t = c.days[key].start;
    for (const [id, secs] of c.days[key].slots) {
      const end = t + secs;
      const p = file.programs[id];
      if (end > now && p && out.length < limit) {
        out.push({
          id: `${ch.channel}-${t}`, epg_id: ch.epg_channel_id, title: b64(p[0]), lang: "en",
          start: clock(t), end: clock(end), description: "", channel_id: ch.epg_channel_id,
          start_timestamp: String(t), stop_timestamp: String(end),
          now_playing: t <= now && now < end ? 1 : 0, has_archive: 0,
        });
      }
      t = end + file.gap;
    }
  }
  return { epg_listings: out };
}

function account(url) {
  const username = url.searchParams.get("username") || "archivewatch";
  const password = url.searchParams.get("password") || "archivewatch";
  const now = Math.floor(Date.now() / 1000);
  return {
    user_info: {
      username, password, message: "Archive Watch — public-domain films from the Internet Archive",
      auth: 1, status: "Active", exp_date: null, is_trial: "0", active_cons: "0",
      created_at: "1790467200", max_connections: "1000", allowed_output_formats: ["ts", "m3u8"],
    },
    server_info: {
      url: url.hostname, port: "443", https_port: "443", server_protocol: "https",
      rtmp_port: "0", timezone: "UTC", timestamp_now: now, time_now: clock(now),
    },
  };
}

export async function handleXtream(url) {
  const path = url.pathname;
  try {
    if (path === "/player_api.php") {
      const action = url.searchParams.get("action");
      const cat = url.searchParams.get("category_id");
      const byCat = (all, dir) => (cat && /^\d+$/.test(cat) ? pass(`${dir}/${cat}.json`) : pass(all));
      const within = (list) => (cat ? list.filter((s) => String(s.category_id) === cat) : list);
      switch (action) {
        case null: case "": return json(account(url));
        case "get_vod_categories": return pass("vod_categories.json");
        case "get_vod_streams": return byCat("vod_streams.json", "vod_streams");
        case "get_vod_info": {
          const info = await vodInfo(url.searchParams.get("vod_id"));
          if (!info) return json({ info: [], movie_data: [] });
          return json({ info: info.info, movie_data: info.movie_data });
        }
        case "get_live_categories": return pass("live_categories.json");
        case "get_live_streams": return json(within(await feed("live_streams.json")));
        case "get_short_epg":
        case "get_simple_data_table":
          return json(await shortEpg(url.searchParams.get("stream_id"),
            action === "get_short_epg" ? Number(url.searchParams.get("limit") || 4) : 60));
        case "get_series_categories": return pass("series_categories.json");
        case "get_series": return byCat("series.json", "series");
        case "get_series_info": {
          const id = url.searchParams.get("series_id");
          if (!/^\d+$/.test(id || "")) return json({ seasons: [], info: {}, episodes: {} });
          try { return await pass(`series_info/${id}.json`); }
          catch { return json({ seasons: [], info: {}, episodes: {} }); }
        }
        default: return json([]);
      }
    }
    if (path === "/get.php") return redirect(`${SITE}/feeds/archivewatch.m3u`);
    if (path === "/xmltv.php") return redirect(`${SITE}/feeds/guide.xml`);
    // /movie/<user>/<pass>/<id>.<ext>
    let m = path.match(/^\/movie\/[^/]+\/[^/]+\/(\d+)(?:\.\w+)?$/);
    if (m) {
      const info = await vodInfo(m[1]);
      return info ? redirect(info.url) : new Response("Not found\n", { status: 404 });
    }
    // /series/<user>/<pass>/<episode id>.<ext>
    m = path.match(/^\/series\/[^/]+\/[^/]+\/(\d+)(?:\.\w+)?$/);
    if (m) {
      const to = await episodeURL(m[1]);
      return to ? redirect(to) : new Response("Not found\n", { status: 404 });
    }
    // /live/<user>/<pass>/<id>.<ext>
    m = path.match(/^\/live\/[^/]+\/[^/]+\/(\d+)(?:\.\w+)?$/);
    if (m) {
      const to = await liveTarget(m[1]);
      return to ? redirect(to) : new Response("Not found\n", { status: 404 });
    }
  } catch {
    return new Response("The film list could not be loaded.\n", { status: 503 });
  }
  return null;
}
