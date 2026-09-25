/* Archive Watch — Pulse.
   One fetch, one render. No framework, no build step (Decision 001).

   The load-bearing rule here is honesty about absence: a source that could not
   answer must never render as a zero. `n()` returns an em-dash for null, the
   Sources panel names every reader that failed and why, and a panel whose
   reader is off says so instead of showing 0. A dashboard that reports a
   confident 0 for a broken reader is worse than no dashboard — it reads as
   good news.

   The binding rules are docs/PULSE.md "How it LOOKS". The two that shape this
   file: every number opens ONE drawer, routed in the hash (rule 8), and every
   Needs attention / Going well item comes from the RULES table below. */

const DATA = "../ops/pulse.json";
const INDEX = "../catalog-index.json";
const TZ = "America/Denver";
const REPO = "https://github.com/bhwilkoff/Archive-Watch";
const SITE = "https://archivewatch.org";
const $ = (id) => document.getElementById(id);

const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};
const n = (v) => (v === null || v === undefined || v === "") ? "—" : v;
const int = (v) => (typeof v === "number") ? v.toLocaleString("en-US") : n(v);
const num = (v, dp) => (typeof v === "number")
  ? v.toLocaleString("en-US", { maximumFractionDigits: dp ?? (Math.abs(v) < 10 ? 2 : 0) })
  : "—";
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
  .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const pct = (part, whole) => whole ? `${Math.round((part / whole) * 100)}%` : "—";
const plural = (k, word) => `${int(k)} ${word}${k === 1 ? "" : "s"}`;
const clip = (t, n2) => (t || "").length > n2 ? (t || "").slice(0, n2 - 1) + "…" : (t || "");
const slugify = (s) => String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "-")
  .replace(/^-|-$/g, "");
const hash = (s) => {
  let h = 0x811c9dc5;
  for (const ch of String(s)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  return h.toString(16);
};

/* ── time: calendar days as written, instants in Mountain time ─────────── */
const mtDay = new Intl.DateTimeFormat("en-CA",
  { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" });
const mtWhen = new Intl.DateTimeFormat("en-US",
  { timeZone: TZ, month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
const todayMT = () => mtDay.format(new Date());
const dayOf = (s) => {
  if (!s) return "";
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(s))) return String(s);
  const t = Date.parse(s);
  return Number.isNaN(t) ? String(s).slice(0, 10) : mtDay.format(new Date(t));
};
const day = (s, year = false) => (s ? C.dayLabel(dayOf(s), year) : "—");
const whenMT = (iso) => {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? n(iso) : `${mtWhen.format(new Date(t))} MT`;
};
const addDays = (ymd, k) => new Date(Date.parse(ymd + "T00:00:00Z") + k * 864e5)
  .toISOString().slice(0, 10);
const daysApart = (a, b) => Math.round(
  (Date.parse(dayOf(b) + "T00:00:00Z") - Date.parse(dayOf(a) + "T00:00:00Z")) / 864e5);
const ageDays = (iso) => daysApart(iso, todayMT());

function ago(iso) {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const h = (Date.now() - t) / 36e5;
  if (h < 1) return `${Math.max(1, Math.round(h * 60))}m ago`;
  if (h < 48) return `${Math.round(h)}h ago`;
  const d = Math.round(h / 24);
  return d < 14 ? `${d}d ago` : day(iso, true);
}

/* ── the ONE way a change is written (docs/PULSE.md rule 10) ─────────────
   Always ends in its period. `invert` for a number where lower is better. */
function chgParts(cur, prev, period, { pctMode = true, invert = false, unit = "", dp } = {}) {
  if (typeof cur !== "number" || typeof prev !== "number") return null;
  const diff = cur - prev;
  if (Math.abs(diff) < 1e-9) return { text: `no change ${period}`, cls: "flat" };
  const good = invert ? diff < 0 : diff > 0;
  const sign = diff > 0 ? "+" : "−";
  const mag = pctMode && prev
    ? `${Math.round((Math.abs(diff) / Math.abs(prev)) * 100)}%`
    : `${num(Math.abs(diff), dp)}${unit}`;
  return { text: `${sign}${mag} ${period}`, cls: good ? "up" : "down" };
}
const chg = (...a) => { const p = chgParts(...a); return p ? `<span class="${p.cls}">${esc(p.text)}</span>` : ""; };
const chgText = (...a) => (chgParts(...a) || {}).text || "";

/* ── series: [{date, v}] ─────────────────────────────────────────────── */
const pts = (rows, dk, vk) => (rows || [])
  .filter((r) => r && r[dk] != null && typeof r[vk] === "number")
  .map((r) => ({ date: dayOf(r[dk]), v: r[vk] }));
function fillZero(points) {
  if (points.length < 2) return points;
  const m = new Map(points.map((p) => [p.date, p.v]));
  const out = [];
  for (let d = points[0].date; d <= points[points.length - 1].date; d = addDays(d, 1)) {
    out.push({ date: d, v: m.get(d) ?? 0 });
  }
  return out;
}
// A day still in progress is never compared (rule 10).
const complete = (points) => { const t = todayMT(); return points.filter((p) => p.date < t); };
function win(points, end, days, agg = "sum") {
  const from = addDays(end, -days + 1);
  const sel = points.filter((p) => p.date >= from && p.date <= end);
  const sum = sel.reduce((a, p) => a + p.v, 0);
  return { v: agg === "mean" ? (sel.length ? sum / sel.length : null) : sum, n: sel.length };
}
function wow(points, agg = "sum") {
  const c = complete(points);
  if (c.length < 8) return null;
  const end = c[c.length - 1].date;
  const a = win(c, end, 7, agg), b = win(c, addDays(end, -7), 7, agg);
  if (a.n < 4 || b.n < 4) return null;
  return { cur: a.v, prev: b.v, end, pct: b.v ? (a.v - b.v) / b.v : null };
}

/* Every usage series the page compares week over week, in one registry so
   the RULES, the Overview's week list, the small multiples and the series
   drawer can never disagree about what a series is. */
let SER = new Map();
function buildSeries(d) {
  const h = d.health || {};
  const m = new Map();
  const add = (o) => { if (o.points && o.points.length) m.set(o.key, { agg: "sum", lag: 3, ...o }); };
  add({ key: "apple-dl", label: "Apple downloads", unit: " downloads", view: "reach",
        points: pts(h.appleDownloads?.daily, "date", "units"),
        src: "https://appstoreconnect.apple.com/analytics", reader: "apple_downloads" });
  add({ key: "android-acq", label: "Android listing acquisitions", unit: " acquisitions",
        view: "reach", points: pts(h.playAcquisition?.daily, "date", "acquisitions"),
        src: "https://play.google.com/console", reader: "play_acquisition" });
  add({ key: "android-inst", label: "Android installs", unit: " installs", view: "reach",
        points: pts(h.playInstalls?.daily, "date", "installs"),
        src: "https://play.google.com/console", reader: "play_reports",
        staleNote: h.playInstalls?.staleDays
          ? `no new row in Google's install export for ${h.playInstalls.staleDays} days` : null });
  add({ key: "firetv-inst", label: "Fire TV installs", unit: " installs", view: "reach", lag: 4,
        points: fillZero(pts(h.amazonInstalls?.daily, "date", "installs")),
        src: h.amazonInstalls?.console, reader: "amazon_installs" });
  add({ key: "roku-inst", label: "Roku installs", unit: " installs", view: "reach",
        points: pts(h.rokuEngagement?.daily, "date", "Channel Installs"),
        src: h.rokuEngagement?.console, reader: "roku_engagement" });
  const wu = h.webUsage;
  add({ key: "web-visits", label: "Website visits", unit: " visits", view: "engagement", lag: 2,
        points: pts((wu?.daily || []).filter((r) => !wu.splitFrom || r.date >= wu.splitFrom),
                    "date", "visits"),
        src: SITE, reader: "web_usage" });
  add({ key: "web-plays", label: "Web plays", unit: " plays", view: "engagement", lag: 2,
        points: pts(h.webTitles?.daily, "date", "play"), src: SITE });
  const sc = h.searchConsole;
  add({ key: "search-clicks", label: "Search clicks", unit: " clicks", view: "search", lag: 5,
        points: pts(sc?.daily, "date", "clicks"), src: sc?.url, reader: "search_console" });
  add({ key: "search-impr", label: "Search impressions", unit: " impressions", view: "search",
        lag: 5, points: pts(sc?.daily, "date", "impressions"), src: sc?.url,
        reader: "search_console" });
  add({ key: "together-rooms", label: "Watch Together rooms", unit: " rooms",
        view: "engagement", lag: 2, points: pts(h.together?.daily, "date", "rooms") });
  return m;
}
const USAGE = ["apple-dl", "android-acq", "android-inst", "firetv-inst", "roku-inst",
               "web-visits", "web-plays", "search-clicks", "search-impr", "together-rooms"];
const lastDay = (s) => s.points[s.points.length - 1]?.date;
const isStale = (s) => daysApart(lastDay(s), todayMT()) > s.lag;
// A panel's "as of" chip (rule 11): only when its data is older than its lag.
const asOfIf = (date, lag = 2) => (date && daysApart(date, todayMT()) > lag ? dayOf(date) : null);

/* ── state words ────────────────────────────────────────────────────────── */
const STATE_CLASS = (s = "") => {
  const u = s.toUpperCase();
  // Negation FIRST: "NOT SUBMITTED" contains "SUBMITT".
  if (/\bNOT\b|NONE|NEVER/.test(u)) return "idle";
  if (/READY_FOR_SALE|COMPLETED|LIVE|APPROVED/.test(u)) return "live";
  if (/REVIEW|PENDING|SUBMITT|PROCESS|PREPARE|DRAFT|INPROGRESS|UPLOAD/.test(u)) return "flight";
  if (/REJECT|REMOVED|INVALID/.test(u)) return "stop";
  return "idle";
};
const STATE_WORD = (s = "") => s.replace(/_/g, " ").toLowerCase()
  .replace(/\b\w/g, (c) => c.toUpperCase());
const stars = (r) => (typeof r === "number" && r > 0)
  ? "★".repeat(r) + "☆".repeat(5 - r) : "";
const vstr = (v) => (v ? (/^\d/.test(v) ? `v${v}` : v) : "—");

/* ── identities used in routes ──────────────────────────────────────────── */
const crashId = (c) => (/\/(?:crashes|anrs|errors)\/([0-9a-f]+)/i.exec(c.url || "") || [])[1]
  || hash(`${c.cause}|${c.location}|${c.firstBuild}`);
const reviewId = (r) => r.id || hash(`${r.store}|${r.author}|${r.date}`);
const storeSlug = (s) => slugify(`${s.store}-${s.platform}`);
const shortLoc = (c) => {
  const ex = String(c.location || "").split(".").pop();
  const at = String(c.cause || "").split(".").slice(-2).join(".");
  return [ex, at && at !== ex ? `in ${at}` : ""].filter(Boolean).join(" ") || c.type || "cluster";
};

/* The release state of a crash fix (docs/PULSE.md "Fixed-in"). Android's
   versionCode only — the Apple build number is a different counter. */
function releaseCtx(d) {
  const prod = (d.stores || []).find((s) => s.store === "Google Play" && s.platform === "Production");
  return {
    playLive: Number(d.health?.playLiveBuild) || Number(prod?.build) || null,
    playInflight: Number(prod?.inFlight?.build) || null,
  };
}
function crashStatus(c, x) {
  const f = c.fixedIn;
  if (!f) return { k: "open", word: "no fix recorded" };
  const vc = Number(f.versionCode);
  if (!vc) return { k: "unknown", word: `fix recorded in ${f.version || "a release"}; no Android versionCode to compare` };
  if (x.playLive && x.playLive >= vc) return { k: "shipped", word: "shipped, clears as users update" };
  if (x.playInflight && x.playInflight >= vc) return { k: "review", word: "fix in review" };
  return { k: "repo", word: "fix in repo, not released" };
}

/* ═══════════════════════════════════════════════════════════════════════
   RULES — every Needs attention / Going well item, in one table.
   docs/PULSE.md carries the same table in prose; a new signal is a new row.
   tier: decide (red) · watch (amber) · good (teal).
   find(d, x, rule) returns items { text, num, cmp, period, route }.
   ═══════════════════════════════════════════════════════════════════════ */
const RULES = [
  { id: "crash-live", tier: "decide", path: "health.playCrashes[]", threshold: "not stale, no fix released",
    find: (d, x) => (d.health?.playCrashes || [])
      .filter((c) => !c.stale && ["open", "unknown"].includes(crashStatus(c, x).k))
      .map((c) => ({ text: `Live ${c.type === "CRASH" ? "crash" : "ANR"}: ${shortLoc(c)}`,
        num: plural(c.users || 0, "user"),
        cmp: `${plural(c.reports || 0, "report")}, builds ${c.firstBuild}–${c.lastBuild}`,
        period: `last seen ${day(c.lastSeen)}`, route: `crash/${crashId(c)}` })) },
  { id: "fix-unreleased", tier: "decide", path: "health.playCrashes[].fixedIn.versionCode",
    threshold: "above the live and in-flight versionCode",
    find: (d, x) => (d.health?.playCrashes || [])
      .filter((c) => !c.stale && crashStatus(c, x).k === "repo")
      .map((c) => ({ text: `Fix not released: ${c.fixedIn.what || shortLoc(c)}`,
        num: plural(c.users || 0, "user"),
        cmp: `fix is versionCode ${c.fixedIn.versionCode}, live is ${x.playLive ?? "unknown"}`,
        period: `last seen ${day(c.lastSeen)}`, route: `crash/${crashId(c)}` })) },
  { id: "fix-review", tier: "watch", path: "health.playCrashes[].fixedIn.versionCode",
    threshold: "at or below the in-flight versionCode",
    find: (d, x) => (d.health?.playCrashes || [])
      .filter((c) => !c.stale && crashStatus(c, x).k === "review")
      .map((c) => ({ text: `Fix in review: ${c.fixedIn.what || shortLoc(c)}`,
        num: plural(c.users || 0, "user"), cmp: `in flight as versionCode ${x.playInflight}`,
        period: `last seen ${day(c.lastSeen)}`, route: `crash/${crashId(c)}` })) },
  { id: "review-low", tier: "decide", path: "reviews[]", threshold: { stars: 3, days: 60 },
    find: (d, x, r) => (d.reviews || [])
      .filter((v) => v.rating && v.rating <= r.threshold.stars && !v.responded
        && ageDays(v.date) <= r.threshold.days)
      .map((v) => ({ text: `${v.rating}★ on ${v.store}: ${v.title || clip(v.body, 60)}`,
        num: "not replied", cmp: v.author || "", period: ago(v.date),
        route: `review/${reviewId(v)}` })) },
  { id: "store-rejected", tier: "decide", path: "stores[].state", threshold: "REJECT|REMOVED|INVALID",
    find: (d) => (d.stores || []).filter((s) => STATE_CLASS(s.state || "") === "stop")
      .map((s) => ({ text: `${s.store} · ${s.platform}: ${STATE_WORD(s.state)}`,
        num: vstr(s.version), period: s.since ? `since ${day(s.since)}` : "",
        route: `store/${storeSlug(s)}` })) },
  { id: "wf-broken", tier: "decide", path: "health.workflows[]", threshold: ["BROKEN", "KILLED"],
    find: (d, x, r) => (d.health?.workflows || []).filter((f) => r.threshold.includes(f.severity))
      .map((f) => ({ text: `Workflow ${f.severity.toLowerCase()}: ${wfName(f)}`,
        num: f.severity, route: "fleet" })) },
  { id: "wf-failed", tier: "watch", path: "health.workflows[]", threshold: "any other severity",
    find: (d) => (d.health?.workflows || []).filter((f) => !["BROKEN", "KILLED"].includes(f.severity))
      .map((f) => ({ text: `Workflow ${String(f.severity).toLowerCase()}: ${wfName(f)}`,
        num: f.severity, route: "fleet" })) },
  { id: "asks", tier: "watch", path: "asks[]", threshold: "any",
    find: (d) => (d.asks || []).map((a) => ({ text: `Asked for: ${clip(a.text, 90)}`,
      num: a.where || "", cmp: a.who || "", period: ago(a.date), route: "asks" })) },
  { id: "play-rating", tier: "watch", path: "health.playDaily.ratings[-1].total", threshold: 4,
    find: (d, x, r) => {
      const rs = (d.health?.playDaily?.ratings || []).filter((q) => typeof q.total === "number");
      const last = rs[rs.length - 1];
      return last && last.total < r.threshold ? [{ text: "Google Play average rating",
        num: `${num(last.total, 2)} of 5`, cmp: `below ${r.threshold}`,
        period: `to ${day(last.date)}`, route: "play-rating" }] : [];
    } },
  { id: "roku-crash", tier: "decide",
    path: 'health.rokuEngagement.headline["Channel Crashes as % of Total Devices Streaming"]',
    threshold: 2,
    find: (d, x, r) => {
      const v = d.health?.rokuEngagement?.headline?.["Channel Crashes as % of Total Devices Streaming"];
      return typeof v === "number" && v > r.threshold ? [{ text: "Roku channel crashes",
        num: `${num(v, 1)}% of streaming devices`, cmp: `threshold ${r.threshold}%`,
        period: "Roku's reporting window", route: "roku-stability" }] : [];
    } },
  { id: "usage-fell", tier: "watch", path: "usage series", threshold: { pct: -0.3, min: 10 },
    find: (d, x, r) => x.usage.filter((s) => !isStale(s)).map((s) => [s, wow(s.points, s.agg)])
      .filter(([, w]) => w && w.prev >= r.threshold.min && w.pct != null && w.pct <= r.threshold.pct)
      .map(([s, w]) => ({ text: `${s.label} fell`, num: int(Math.round(w.cur)),
        cmp: `${chgText(w.cur, w.prev, "vs prior 7 days")} (${int(Math.round(w.prev))})`,
        period: `week to ${day(w.end)}`, route: `series/${s.key}` })) },
  { id: "sitemap-errors", tier: "decide", path: "health.searchConsole.sitemaps[].errors", threshold: 0,
    find: (d, x, r) => (d.health?.searchConsole?.sitemaps || [])
      .filter((m) => Number(m.errors) > r.threshold)
      .map((m) => ({ text: `Sitemap errors: ${m.path}`, num: plural(Number(m.errors), "error"),
        period: m.lastDownloaded ? `read ${day(m.lastDownloaded)}` : "",
        route: "search-sitemaps" })) },
  { id: "stale", tier: "watch", path: "generatedAt, stale, sources[].at, series last day",
    threshold: { hours: 36 },
    find: (d, x, r) => {
      const out = [];
      const gen = Date.parse(d.generatedAt || "");
      const hrs = (Date.now() - gen) / 36e5;
      if (hrs > r.threshold.hours) {
        out.push({ text: "Pulse itself has not refreshed", num: `${Math.round(hrs)}h old`,
          period: `read ${whenMT(d.generatedAt)}`, route: "sources" });
      }
      Object.entries(d.stale || {}).forEach(([k, at]) => out.push({
        text: `${k} is standing on an older reading`, num: ago(at),
        cmp: "its reader is offline", route: "sources" }));
      Object.entries(d.sources || {}).forEach(([k, v]) => {
        const t = Date.parse(v.at || "");
        if (!Number.isNaN(t) && !Number.isNaN(gen) && (gen - t) / 36e5 > r.threshold.hours) {
          out.push({ text: `Reader ${k} last ran ${ago(v.at)}`, num: whenMT(v.at), route: "sources" });
        }
      });
      x.usage.filter(isStale).forEach((s) => out.push({
        text: `${s.label}: newest day is ${day(lastDay(s))}`,
        num: `${daysApart(lastDay(s), todayMT())} days old`, cmp: s.staleNote || "",
        route: `series/${s.key}` }));
      return out;
    } },
  { id: "inflight", tier: "watch", path: "stores[].inFlight", threshold: "present",
    find: (d) => (d.stores || []).filter((s) => s.inFlight && s.inFlight.version)
      .map((s) => ({ text: `Waiting to go live: ${s.store} · ${s.platform}`,
        num: `${vstr(s.inFlight.version)}${s.inFlight.build ? ` (${s.inFlight.build})` : ""}`,
        cmp: `live ${vstr(s.live)}`, period: STATE_WORD(s.inFlight.state || ""),
        route: `store/${storeSlug(s)}` })) },

  /* ── going well ── */
  { id: "usage-rose", tier: "good", path: "usage series", threshold: { pct: 0.3, min: 10 },
    find: (d, x, r) => x.usage.filter((s) => !isStale(s)).map((s) => [s, wow(s.points, s.agg)])
      .filter(([, w]) => w && w.cur >= r.threshold.min && (w.prev === 0 || (w.pct != null && w.pct >= r.threshold.pct)))
      .map(([s, w]) => ({ text: `${s.label} rose`, num: int(Math.round(w.cur)),
        cmp: `${chgText(w.cur, w.prev, "vs prior 7 days")} (${int(Math.round(w.prev))})`,
        period: `week to ${day(w.end)}`, route: `series/${s.key}` })) },
  { id: "praise", tier: "good", path: "reviews[] 5★, loves[]", threshold: { days: 14 },
    find: (d, x, r) => {
      const five = (d.reviews || []).filter((v) => v.rating === 5 && ageDays(v.date) <= r.threshold.days);
      const said = five.map((v) => `${v.title} ${v.body}`).join(" ");
      return [
        ...five.map((v) => ({ text: `5★ on ${v.store}: ${v.title || clip(v.body, 60)}`,
          num: v.author || "", period: ago(v.date), route: `review/${reviewId(v)}` })),
        ...(d.loves || []).filter((l) => ageDays(l.date) <= r.threshold.days
            && !said.includes(String(l.text || "").slice(0, 30)))
          .map((l) => ({ text: `Praise: “${clip(l.text, 80)}”`, num: l.where || "",
            cmp: l.who || "", period: ago(l.date), route: "loves" })),
      ];
    } },
  { id: "crashes-cleared", tier: "good", path: "health.playCrashes[].stale", threshold: "stale",
    find: (d, x) => {
      const gone = (d.health?.playCrashes || []).filter((c) => c.stale);
      return gone.length ? [{ text: "Crash clusters not seen on the live build",
        num: String(gone.length), cmp: x.playLive ? `live versionCode ${x.playLive}` : "",
        route: "crashes" }] : [];
    } },
  { id: "store-live", tier: "good", path: "stores[].since", threshold: { days: 14 },
    find: (d, x, r) => (d.stores || []).filter((s) => STATE_CLASS(s.state || "") === "live"
        && s.since && ageDays(s.since) <= r.threshold.days)
      .map((s) => ({ text: `Live: ${s.store} · ${s.platform}`, num: vstr(s.version),
        period: `since ${day(s.since)}`, route: `store/${storeSlug(s)}` })) },
  { id: "catalog-grew", tier: "good", path: "history[].catalogItems", threshold: 0,
    find: (d) => {
      const h = (d.history || []).filter((q) => typeof q.catalogItems === "number");
      const cur = h[h.length - 1];
      if (!cur) return [];
      const back = [...h].reverse().find((q) => q.date <= addDays(cur.date, -7)) || h[0];
      const diff = cur.catalogItems - back.catalogItems;
      return back !== cur && diff > 0 ? [{ text: "Catalog grew", num: `+${int(diff)}`,
        cmp: `${int(cur.catalogItems)} titles`, period: `vs ${day(back.date)}`,
        route: "history/catalogItems" }] : [];
    } },
  { id: "readers-ok", tier: "good", path: "sources", threshold: "all ok",
    find: (d) => {
      const rs = Object.values(d.sources || {});
      return rs.length && rs.every((v) => v.ok) ? [{ text: "Every reader answered",
        num: `${rs.length} of ${rs.length}`, period: whenMT(d.generatedAt), route: "sources" }] : [];
    } },
  { id: "query-top10", tier: "good", path: "health.searchConsole.queries[]", threshold: 10,
    // "New" needs a prior period to be new AGAINST: a property with no prior
    // 28 days made every query new, and the column filled with 85 of them.
    // One line for the lot, led by the query that brings the most clicks.
    find: (d, x, r) => {
      const sc = d.health?.searchConsole;
      if (!sc || !(sc.prev28?.impressions > 0)) return [];
      const fresh = (sc.queries || [])
        .filter((q) => q.position <= r.threshold && !q.prevImpressions && q.impressions > 0)
        .sort((a, b) => (b.clicks || 0) - (a.clicks || 0));
      return fresh.length ? [{ text: fresh.length === 1 ? `New in the top 10: “${fresh[0].key}”`
          : `${fresh.length} searches newly in the top 10, led by “${fresh[0].key}”`,
        num: `position ${num(fresh[0].position, 1)}`, cmp: plural(fresh[0].clicks || 0, "click"),
        period: "last 28 days", route: "search-queries" }] : [];
    } },
];
const wfName = (f) => String(f.workflow || "").replace(/\s*conclusion=\S+/g, "");
const wfRuns = (f) => `${REPO}/actions?query=${encodeURIComponent(`workflow:"${wfName(f)}"`)}`;

function board(d) {
  const x = { ...releaseCtx(d), usage: USAGE.map((k) => SER.get(k)).filter(Boolean) };
  const needs = [], well = [];
  RULES.forEach((r) => {
    let items;
    try { items = r.find(d, x, r) || []; } catch (e) {
      items = [{ text: `Rule ${r.id} could not run: ${e.message}`, tier: "watch" }];
    }
    items.forEach((it) => (r.tier === "good" ? well : needs).push({ tier: r.tier, ...it }));
  });
  needs.sort((a, b) => (a.tier === "decide" ? 0 : 1) - (b.tier === "decide" ? 0 : 1));
  column($("needs"), $("needs-n"), needs,
    "Nothing needs you: no live crash, no unreplied low review, no failed workflow, "
    + "no fall in usage, no stale reader.");
  column($("well"), $("well-n"), well, "Nothing moved up this week.");
}

function column(box, count, items, empty) {
  if (!box) return;
  box.innerHTML = "";
  if (count) count.textContent = items.length ? String(items.length) : "";
  if (!items.length) { box.appendChild(el("li", "clear", empty)); return; }
  items.forEach((it, i) => {
    const li = el("li", `item t-${it.tier}${i >= 6 ? " extra" : ""}`);
    const b = el("button", "it");
    b.type = "button";
    b.appendChild(el("span", "it-t", it.text));
    if (it.num) b.appendChild(el("span", "it-n", it.num));
    const meta = [it.cmp, it.period].filter(Boolean).join(" · ");
    if (meta) b.appendChild(el("span", "it-m", meta));
    if (it.route) b.onclick = () => nav(it.route);
    li.appendChild(b);
    box.appendChild(li);
  });
  if (items.length > 6) {
    const li = el("li", "more");
    const b = el("button", null, `${items.length - 6} more`);
    b.type = "button";
    b.onclick = () => { box.classList.add("all"); li.hidden = true; };
    li.appendChild(b);
    box.appendChild(li);
  }
}

/* ═══════════════════════════════════════════════════════════════════════
   THE DRAWER — one drill-down for the whole page (docs/PULSE.md rule 8).
   Route: #<view>/<drawer>. <drawer> is either a GLOBAL kind resolved by
   DRAWERS (crash/<id>, review/<id>, series/<key>, …) or a panel's own drawer,
   registered in REG under "<view>/p/<slug>" when the panel is drawn.
   ═══════════════════════════════════════════════════════════════════════ */
let D = null, LIST = [], CUR = "overview";
const REG = new Map();

function nav(route, view) {
  const r = String(route).split("/").map(encodeURIComponent).join("/");
  location.hash = `${view || CUR}/${r}`;
}

function openDrawer(path) {
  const dlg = $("drawer"), body = $("drawer-body");
  if (!dlg || !body) return;
  const segs = path.split("/");
  let spec = null;
  try {
    const reg = REG.get(`${CUR}/${path}`);
    if (reg) spec = reg();
    else if (DRAWERS[segs[0]]) spec = DRAWERS[segs[0]](D, segs.slice(1));
  } catch (e) {
    spec = { title: "Could not open this", note: e.message };
  }
  if (!spec) spec = { title: "Nothing here", note: "This link points at something the latest reading does not carry." };
  $("drawer-title").textContent = spec.title;
  body.innerHTML = "";
  renderSpec(body, spec);
  dlg.dataset.path = path;
  if (!dlg.open) {
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute("open", "");
  }
  dlg.scrollTop = 0;
}
function closeDrawer() {
  const dlg = $("drawer");
  if (dlg && dlg.open) dlg.close();
}

function renderSpec(body, spec) {
  if (spec.sub) body.appendChild(el("p", "dr-sub", spec.sub));
  if (spec.deltas && spec.deltas.length) {
    const s = el("div", "dr-deltas");
    s.innerHTML = spec.deltas.filter((x) => x.html)
      .map((x) => `<span><b>${esc(x.label)}</b> ${x.html}</span>`).join("");
    body.appendChild(s);
  }
  (spec.charts || []).filter(Boolean).forEach((h) => {
    const c = el("div", "dr-chart");
    c.innerHTML = h;
    body.appendChild(c);
  });
  if (spec.facts && spec.facts.length) {
    const dl = el("dl", "facts");
    spec.facts.filter(([, v]) => v != null && v !== "").forEach(([k, v, cls]) => {
      dl.appendChild(el("dt", null, k));
      dl.appendChild(el("dd", cls || null, String(v)));
    });
    body.appendChild(dl);
  }
  if (spec.quote) {
    const q = el("blockquote", "dr-quote");
    if (spec.quote.lead) q.appendChild(el("b", null, spec.quote.lead + " "));
    q.appendChild(document.createTextNode(spec.quote.text || ""));
    body.appendChild(q);
  }
  (spec.tables || []).filter(Boolean).forEach((t) => body.appendChild(table(t)));
  if (spec.note) body.appendChild(el("p", "dr-note", spec.note));
  if (spec.source && spec.source.href) {
    const a = el("a", "dr-src", `${spec.source.label || "Source"} ↗`);
    a.href = spec.source.href; a.target = "_blank"; a.rel = "noopener";
    body.appendChild(a);
  }
}

/* The complete table behind a figure, sortable by any column. Never capped:
   a list that silently stops at twelve is a list that lies about thirteen. */
function table({ title, cols, rows, sort }) {
  const wrap = el("div", "t-wrap");
  if (title) {
    const h = el("h3", "t-h", title);
    h.appendChild(el("span", "count", ` ${rows.length}`));
    wrap.appendChild(h);
  }
  if (!rows.length) { wrap.appendChild(el("p", "clear", "No rows.")); return wrap; }
  const tbl = el("table", "t");
  const thead = el("thead"), tr = el("tr"), tb = el("tbody");
  let key = (sort && sort.k) || cols[0].k;
  let dir = (sort && sort.dir) || (cols.find((c) => c.k === key)?.num ? -1 : 1);
  const val = (c, r) => (c.sortv ? c.sortv(r) : r[c.k]);
  const ths = cols.map((c) => {
    const th = el("th", c.num ? "num" : null);
    th.setAttribute("scope", "col");
    const b = el("button", null, c.label);
    b.type = "button";
    b.onclick = () => {
      if (key === c.k) dir = -dir; else { key = c.k; dir = c.num ? -1 : 1; }
      draw();
    };
    th.appendChild(b);
    tr.appendChild(th);
    return [c, th];
  });
  thead.appendChild(tr);
  const draw = () => {
    ths.forEach(([c, th]) => th.setAttribute("aria-sort",
      c.k === key ? (dir > 0 ? "ascending" : "descending") : "none"));
    const col = cols.find((c) => c.k === key);
    const sorted = rows.slice().sort((a, b) => {
      const va = val(col, a), vb = val(col, b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      return (typeof va === "number" && typeof vb === "number"
        ? va - vb : String(va).localeCompare(String(vb))) * dir;
    });
    tb.innerHTML = "";
    sorted.forEach((r) => {
      const row = el("tr");
      cols.forEach((c) => {
        const td = el("td", [c.num ? "num" : "", c.cls ? c.cls(r) || "" : ""].filter(Boolean).join(" ") || null);
        const raw = r[c.k];
        const text = c.fmt ? c.fmt(raw, r) : (typeof raw === "number" ? num(raw) : n(raw));
        const route = c.route && c.route(r);
        const href = c.href && c.href(r);
        if (route) {
          const b = el("button", "t-open", text);
          b.type = "button";
          b.onclick = () => nav(route);
          td.appendChild(b);
        } else if (href) {
          const a = el("a", null, text);
          a.href = href; a.target = "_blank"; a.rel = "noopener";
          td.appendChild(a);
        } else td.textContent = text;
        row.appendChild(td);
      });
      tb.appendChild(row);
    });
  };
  draw();
  tbl.appendChild(thead);
  tbl.appendChild(tb);
  const scroller = el("div", "t-scroll");
  scroller.appendChild(tbl);
  wrap.appendChild(scroller);
  return wrap;
}

/* Deltas for a series drawer: one day, seven days, the whole window — each
   labeled with the period it compares (rule 10). */
function seriesDeltas(points, { agg = "sum", invert = false } = {}) {
  const c = complete(points);
  const out = [];
  if (c.length >= 2) {
    const a = c[c.length - 1], b = c[c.length - 2];
    out.push({ label: `${day(a.date)}`, html: chg(a.v, b.v, `vs ${day(b.date)}`, { invert, pctMode: agg === "sum" }) });
  }
  const w = wow(points, agg);
  if (w) out.push({ label: `Week to ${day(w.end)}`, html: chg(w.cur, w.prev, "vs prior 7 days", { invert, pctMode: agg === "sum" }) });
  if (c.length >= 14) {
    const end = c[c.length - 1].date, first = c[0].date;
    const a = win(c, end, 7, agg), b = win(c, addDays(first, 6), 7, agg);
    out.push({ label: "Whole window", html: chg(a.v, b.v, `vs week of ${day(first)}`, { invert, pctMode: agg === "sum" }) });
  }
  return out;
}

function seriesSpec(s) {
  const c = s.points;
  const weeks = [];
  const cc = complete(c);
  if (cc.length) {
    for (let end = cc[cc.length - 1].date; end >= cc[0].date; end = addDays(end, -7)) {
      const a = win(cc, end, 7, s.agg), b = win(cc, addDays(end, -7), 7, s.agg);
      weeks.push({ end, v: a.v, n: a.n, prev: b.n ? b.v : null });
    }
  }
  const byDay = c.map((p) => ({ date: p.date, v: p.v,
    w: win(c, p.date, 7, s.agg).v }));
  return {
    title: s.label,
    sub: isStale(s) ? `Newest day is ${day(lastDay(s), true)}${s.staleNote ? ` — ${s.staleNote}` : ""}.` : null,
    deltas: seriesDeltas(c, s),
    charts: [C.timeChart([{ label: s.label, points: c }],
      { label: s.label, band: c.length >= 8, h: 150, to: isStale(s) ? todayMT() : null })],
    tables: [
      weeks.length > 1 ? { title: "By week", sort: { k: "end", dir: -1 }, rows: weeks, cols: [
        { k: "end", label: "Week ending", fmt: (v) => day(v, true) },
        { k: "n", label: "Days", num: true },
        { k: "v", label: s.agg === "mean" ? "Average" : "Total", num: true, fmt: (v) => num(v, 2) },
        { k: "chg", label: "vs prior week", sortv: (r) => (r.prev ? (r.v - r.prev) / r.prev : null),
          fmt: (_, r) => chgText(r.v, r.prev, "", { pctMode: s.agg === "sum" }) || "—",
          cls: (r) => (chgParts(r.v, r.prev, "", { invert: s.invert }) || {}).cls },
      ] } : null,
      { title: "By day", sort: { k: "date", dir: -1 }, rows: byDay, cols: [
        { k: "date", label: "Day", fmt: (v) => day(v, true) },
        { k: "v", label: s.label, num: true },
        { k: "w", label: s.agg === "mean" ? "7-day average" : "7-day total", num: true },
      ] },
    ],
    source: s.src ? { href: s.src, label: "Source" } : null,
  };
}

function genericSpec({ k, rows, href, series }) {
  const s = series ? { agg: "sum", ...series } : null;
  return {
    title: k,
    deltas: s ? seriesDeltas(s.points, s) : [],
    charts: s ? [C.timeChart(s.multi || [{ label: s.label || k, points: s.points }],
      { label: k, band: !s.multi && s.points.length >= 8, h: 150, unit: s.unit || "" })] : [],
    tables: rows.length ? [{ rows, sort: rows.some((r) => typeof r.sortv === "number")
      ? { k: "value", dir: -1 } : null, cols: [
      { k: "label", label: "Item", href: (r) => r.href, route: (r) => r.route },
      { k: "value", label: "Value", num: true, sortv: (r) => (typeof r.sortv === "number" ? r.sortv : null),
        fmt: (v) => String(v == null ? "" : v).replace(/<[^>]*>/g, "") },
      ...(rows.some((r) => r.note) ? [{ k: "note", label: "Note", fmt: (v) => v || "" }] : []),
    ] }] : [],
    source: href ? { href, label: "Source" } : null,
  };
}
// Detail rows carry a numeric sort key alongside their display string.
const drow = (label, value, extra = {}) => ({ label, value: typeof value === "number" ? int(value) : value,
  sortv: typeof value === "number" ? value : parseFloat(String(value).replace(/,/g, "")), ...extra });

/* ── panel: a titled cell; its header opens its drawer ─────────────────── */
function panel(box, { k, right, v, chart, cap, detail, href, drill, series, asOf, wide }) {
  if (!box) return null;
  const view = (box.dataset && box.dataset.view) || CUR;
  const p = el("div", "panel" + ((chart && chart.wide) || wide ? " wide" : ""));
  const rows = (detail || []).filter(Boolean);
  let route = null;
  if (typeof drill === "string") route = drill;
  else if (drill || rows.length || series) {
    route = `p/${slugify(k)}`;
    REG.set(`${view}/${route}`, typeof drill === "function" ? drill
      : () => genericSpec({ k, rows, href, series }));
  }
  const head = el("div", "k");
  if (route) {
    const b = el("button", "k-open", k);
    b.type = "button";
    b.onclick = () => nav(route, view);
    head.appendChild(b);
  } else if (href) {
    const a = el("a", "k-out", `${k} ↗`);
    a.href = href; a.target = "_blank"; a.rel = "noopener";
    head.appendChild(a);
  } else head.appendChild(el("span", null, k));
  if (asOf) head.appendChild(el("span", "asof", `as of ${day(asOf)}`));
  if (right) { const rr = el("span", "r"); rr.innerHTML = right; head.appendChild(rr); }
  p.appendChild(head);
  if (v != null) { const d2 = el("div", "v"); d2.innerHTML = v; p.appendChild(d2); }
  if (chart && chart.html) {
    const c = el("div", "chart");
    c.innerHTML = chart.html;
    if (route) { c.dataset.nav = route; c.dataset.view = view; }
    p.appendChild(c);
    p.chartEl = c;
  }
  if (cap) { const c = el("div", "cap"); c.innerHTML = cap; p.appendChild(c); }
  box.appendChild(p);
  return p;
}

/* ── row: the list shape used everywhere else ─────────────────────────── */
function row(parent, { name, meta, num: numHTML, state, href, route, cls }) {
  const r = el("div", "row" + (cls ? " " + cls : ""));
  const left = el("div", "name");
  if (route) {
    const b = el("button", "row-open", name);
    b.type = "button";
    b.onclick = () => nav(route);
    left.appendChild(b);
  } else if (href) {
    const a = el("a", null, name); a.href = href; a.target = "_blank"; a.rel = "noopener";
    left.appendChild(a);
  } else left.textContent = name;
  r.appendChild(left);
  if (state) r.appendChild(el("span", "state " + STATE_CLASS(state), STATE_WORD(state)));
  else if (numHTML != null) { const d2 = el("span", "num"); d2.innerHTML = numHTML; r.appendChild(d2); }
  else r.appendChild(el("span"));
  if (meta) r.appendChild(el("div", "meta", meta));
  parent.appendChild(r);
  return r;
}

/* ── web titles, resolved lazily from the catalog index (~6 MB) ────────── */
const Titles = {
  map: null, p: null,
  load() {
    if (!this.p) {
      this.p = fetch(INDEX).then((r) => (r.ok ? r.json() : null)).then((j) => {
        const f = (j && j.fields) || [];
        const ii = f.indexOf("id"), ti = f.indexOf("title"), yi = f.indexOf("year");
        const m = new Map();
        ((j && j.items) || []).forEach((it) => {
          if (Array.isArray(it)) {
            m.set(it[ii < 0 ? 0 : ii], { t: it[ti < 0 ? 1 : ti], y: it[yi < 0 ? 2 : yi] });
          }
        });
        this.map = m;
        return m;
      }).catch(() => { this.map = new Map(); this.failed = true; return this.map; });
    }
    return this.p;
  },
  name(id) {
    const bare = String(id).replace(/^series:/, "");
    const t = this.map && this.map.get(bare);
    if (t && t.t) return `${t.t}${typeof t.y === "number" ? ` (${t.y})` : ""}`;
    return bare;
  },
  missing(id) { return !!(this.map && this.map.size && !this.map.has(String(id).replace(/^series:/, ""))); },
};
const itemURL = (id) => String(id).startsWith("series:")
  ? `${SITE}/#/series/${encodeURIComponent(id.slice(7))}`
  : `${SITE}/#/item/${encodeURIComponent(id)}`;
let titlePanels = [];
function wantTitles() {
  if (Titles.map) return;
  Titles.load().then(() => {
    titlePanels.forEach(({ p, box }) => { if (p && p.chartEl) p.chartEl.innerHTML = titlesBars(D?.health?.webTitles); });
    const dlg = $("drawer");
    if (dlg && dlg.open && /^titles/.test(dlg.dataset.path || "")) openDrawer(dlg.dataset.path);
  });
}
function titlesBars(wt) {
  const rows = ((wt && (wt.topPlayed || []).length ? wt.topPlayed : wt?.topOpened) || []).slice(0, 10);
  return C.bars(rows.map((r) => ({ label: Titles.name(r.id), value: r.count })));
}

/* ═══════════════════════════════════════════════════════════════════════
   THE VIEWS
   ═══════════════════════════════════════════════════════════════════════ */
function stores(d) {
  const box = $("stores"); if (!box) return;
  box.innerHTML = "";
  const rows = (d.stores || []).slice().sort((a, b) =>
    (a.store + a.platform).localeCompare(b.store + b.platform));
  const cnt = $("stores-n"); if (cnt) cnt.textContent = rows.length;
  rows.forEach((s) => {
    const bits = [];
    if (s.version) bits.push(vstr(s.version));
    if (s.live && s.live !== s.version) bits.push(`live ${vstr(s.live)}`);
    if (s.build) bits.push(`build ${s.build}`);
    // A newer build is waiting ONLY when the store says so (docs/PULSE.md).
    if (s.inFlight && s.inFlight.version) {
      bits.push(`${vstr(s.inFlight.version)} ${STATE_WORD(s.inFlight.state || "in flight").toLowerCase()}`);
    }
    if (s.since) bits.push(`since ${day(s.since)}`);
    const r = row(box, { name: `${s.store} · ${s.platform}`, meta: bits.join(" · "),
      state: s.state, route: `store/${storeSlug(s)}` });
    r.classList.add("lead-" + STATE_CLASS(s.state || ""));
  });
}

function glance(d, list) {
  const boxes = {};
  const B = (v) => {
    if (!boxes[v]) {
      const e = $(v === "overview" ? "tiles" : "tiles-" + v);
      if (e) { e.innerHTML = ""; e.className = "panels"; e.dataset.view = v; }
      boxes[v] = e;
    }
    return boxes[v] || $("tiles");
  };
  ["overview", "reach", "engagement", "health", "voice", "program", "ops"].forEach(B);
  titlePanels = [];
  const h = d.health || {};
  const off = (name) => d.sources?.[name] && !d.sources[name].ok;

  /* ── OVERVIEW ── */
  overviewWeek(B("overview"));
  const st = d.stores || [];
  const buckets = { live: 0, flight: 0, stop: 0, idle: 0 };
  st.forEach((x) => { buckets[STATE_CLASS(x.state || "")] += 1; });
  const segs = [
    { label: "live", value: buckets.live, tone: "live" },
    { label: "in flight", value: buckets.flight, tone: "flight" },
    { label: "needs you", value: buckets.stop, tone: "stop" },
    { label: "not submitted", value: buckets.idle, tone: "idle" },
  ];
  panel(B("overview"), {
    k: "The estate", right: `${st.length} surfaces`,
    v: `${buckets.live}<small> live of ${st.length}</small>`,
    chart: { html: C.stack(segs, { label: "store states" }) + C.legend(segs) },
    drill: "stores",
  });
  const cat = h.catalog || {};
  if (cat.items) {
    const hist = d.history || [];
    const cur = hist[hist.length - 1] || {}, prev = hist.length > 1 ? hist[hist.length - 2] : null;
    panel(B("overview"), {
      k: "Catalog", right: prev ? chg(cur.catalogItems, prev.catalogItems, `vs ${day(prev.date)}`, { pctMode: false }) : "",
      v: `${int(cat.items)}<small> titles</small>`,
      chart: { html: C.bars([
        { label: "playable", value: cat.playable || 0, tone: "live", display: pct(cat.playable, cat.items) },
        { label: "real poster", value: cat.professionalArt || 0, tone: "measure", display: pct(cat.professionalArt, cat.items) },
        { label: "trick play", value: cat.withBif || 0, tone: "measure", display: pct(cat.withBif, cat.items) },
      ], { max: cat.items }) },
      drill: "history/catalogItems",
    });
  }
  const loves = (d.loves || []).length, wants = (d.asks || []).length;
  if (loves || wants || (d.reviews || []).length) {
    const segs2 = [
      { label: "praise", value: loves, tone: "live" },
      { label: "requests", value: wants, tone: "flight" },
    ];
    panel(B("overview"), {
      k: "Enjoying vs asking", right: `${plural(loves + wants, "sentence")}`,
      v: wants ? `${wants}<small> asked for something</small>`
        : `<span class="up">${loves}</span><small> said something kind</small>`,
      chart: { html: C.stack(segs2, { label: "praise against requests" }) + C.legend(segs2) },
      drill: wants ? "asks" : "loves",
    });
  }

  /* ── REACH ── */
  const reachRow = (list || []).filter((p) => p.family === "app" && p.views == null && (p.daily || []).length);
  if (reachRow.length) {
    const ends = reachRow.map((p) => p.daily[p.daily.length - 1].date).sort();
    const to = ends[ends.length - 1];
    const from = addDays(to, -34);
    const peak = Math.max(1, ...reachRow.flatMap((p) => p.daily.filter((r) => r.date >= from).map((r) => r.v || 0)));
    const cells = reachRow.map((p) => {
      const inWin = p.daily.filter((r) => r.date >= from);
      const total = inWin.reduce((a, r) => a + (r.v || 0), 0);
      const end = p.daily[p.daily.length - 1].date;
      return `<button type="button" class="sm" data-nav="series/plat-${esc(p.key)}" data-view="reach">
          <span class="sm-k">${esc(p.name)}</span>
          <span class="sm-v">${int(total)}</span>
          <span class="sm-c">${C.timeChart([{ label: `${p.name} installs`, points: inWin }],
            { label: `${p.name} installs`, from, to, max: peak, h: 34, mini: true })}</span>
          <span class="sm-n${asOfIf(end, 3) ? " stale" : ""}">to ${esc(day(end))}</span>
        </button>`;
    }).join("");
    panel(B("reach"), {
      k: "Who is installing", right: `${day(from)} – ${day(to)} · peak ${int(peak)} a day`,
      chart: { wide: true, html: `<div class="smalls">${cells}</div>` },
    });
  }
  const scs = SER.get("search-clicks");
  const sc = h.searchConsole;
  if (sc && scs) {
    panel(B("reach"), {
      k: "Search clicks", right: (sc.prev28?.days || 0) >= 28 && sc.prev28?.impressions > 0
        ? chg(sc.last28?.clicks, sc.prev28?.clicks, "vs prior 28 days") : `data from ${day((sc.daily || [{}])[0].date)}`,
      v: `${int(sc.last28?.clicks)}<small> in 28 days · ${int(sc.last28?.impressions)} impressions</small>`,
      asOf: asOfIf(sc.through || lastDay(scs), 4),
      chart: { html: C.timeChart([{ label: "clicks", points: scs.points }], { label: "Search clicks", h: 64 }) },
      drill: "series/search-clicks",
    });
  } else {
    panel(B("reach"), { k: "Search clicks", v: "<small>not collected yet</small>",
      cap: d.sources?.search_console?.note ? esc(d.sources.search_console.note) : null });
  }
  const dl = h.appleDownloads;
  const adl = SER.get("apple-dl");
  if (adl) {
    const end = lastDay(adl), from = addDays(end, -27);
    const win28 = adl.points.filter((p) => p.date >= from);
    panel(B("reach"), {
      k: "Apple downloads", right: `${day(from)} – ${day(end)}`,
      v: `${int(win28.reduce((a, p) => a + p.v, 0))}<small> first-time installs in 28 days</small>`,
      asOf: asOfIf(end, 3),
      chart: { html: C.timeChart([{ label: "downloads", points: win28 }], { label: "Apple downloads", h: 64, band: true }) },
      drill: "series/apple-dl",
    });
    const byC = Object.entries(dl.byCountry || {}).sort((a, b) => b[1] - a[1]);
    if (byC.length) {
      panel(B("reach"), {
        k: "Apple downloads by country", right: `${byC.length} countries`,
        chart: { html: C.dotPlot(byC.slice(0, 8).map(([k, v]) => ({ label: k, value: v }))) },
        detail: byC.map(([k, v]) => drow(k, v)), href: "https://appstoreconnect.apple.com/analytics",
      });
    }
    const byV = Object.entries(dl.byVersion || {}).sort((a, b) => b[1] - a[1]);
    if (byV.length) {
      panel(B("reach"), {
        k: "Apple downloads by version", right: `${byV.length} versions`,
        chart: { html: C.bars(byV.slice(0, 6).map(([k, v]) => ({ label: vstr(k), value: v, tone: "measure" }))) },
        detail: byV.map(([k, v]) => drow(vstr(k), v)), href: "https://appstoreconnect.apple.com/analytics",
      });
    }
  } else if (off("apple_downloads")) {
    panel(B("reach"), { k: "Apple downloads", v: "<small>not read</small>",
      cap: esc(d.sources.apple_downloads.note || "") });
  }
  const acq = h.playAcquisition;
  if (acq?.daily?.length) {
    panel(B("reach"), {
      k: "Android store listing", right: `${Math.round((acq.conversion28d || 0) * 100)}% of visitors installed`,
      v: `${int(acq.acquisitions28d)}<small> acquisitions from ${int(acq.visitors28d)} visitors · 28 days</small>`,
      asOf: asOfIf(acq.asOf, 3),
      chart: { html: C.timeChart([
        { label: "visitors", points: pts(acq.daily, "date", "visitors") },
        { label: "acquisitions", points: pts(acq.daily, "date", "acquisitions") },
      ], { label: "Store listing funnel", h: 70 }) },
      drill: "funnel",
    });
  }
  const pin = h.playInstalls;
  if (pin?.daily?.length) {
    const all = (o, lab) => Object.entries(o || {}).sort((a, b) => b[1] - a[1]).map(([k, v]) => drow(`${lab} · ${k}`, v));
    panel(B("reach"), {
      k: "Android installs", asOf: asOfIf(pin.asOf, 3),
      v: `${int(pin.installs28d)}<small> installs · ${int(pin.activeDevices)} active devices</small>`,
      chart: { html: C.timeChart([{ label: "installs", points: pts(pin.daily, "date", "installs") }], { label: "Android installs", h: 64 }) },
      cap: pin.staleDays ? `Google's install export has written no new row in ${pin.staleDays} days.` : null,
      series: { label: "installs", points: pts(pin.daily, "date", "installs") },
      detail: [...all(pin.byCountry, "country"), ...all(pin.byDevice, "device"),
               ...all(pin.byOs, "Android API"), ...all(pin.byLanguage, "language")],
      href: "https://play.google.com/console",
    });
  }

  /* ── ENGAGEMENT ── */
  titlesPanel(B("engagement"), h.webTitles);
  const wu = h.webUsage;
  const wv = SER.get("web-visits");
  if (wu?.visits28d != null) {
    const w = wv ? wow(wv.points) : null;
    panel(B("engagement"), {
      k: "Website visits", right: w ? chg(w.cur, w.prev, "vs prior 7 days") : "28 days",
      v: `${int(wu.visits28d)}<small> visits · 28 days</small>`,
      chart: wv ? { html: C.timeChart([{ label: "visits", points: wv.points }], { label: "Website visits", h: 64, band: true }) } : null,
      cap: `${int(wu.views28d || 0)} route views in the same 28 days; a visit is one page load.`,
      drill: wv ? "series/web-visits" : null,
    });
  }
  const rk = h.rokuEngagement;
  if (rk?.headline) {
    const hd = rk.headline;
    const mins = hd["Average Minutes Streamed per Viewer"];
    const rows = pts(rk.daily, "date", "Total Minutes Streamed");
    panel(B("engagement"), {
      k: "Roku viewing", right: `${rows.length} days`,
      v: mins != null ? `${num(mins, 1)}<small> min per viewer</small>` : int(hd["Avg Daily Viewers"] || 0),
      chart: rows.length >= 2 ? { html: C.timeChart([{ label: "minutes", points: rows }], { label: "Roku minutes streamed", h: 64 }) } : null,
      cap: `${int(hd["Avg Daily Viewers"] || 0)} viewers a day · ${int(hd["Hours Streamed"] || 0)} hours streamed`,
      series: { label: "Minutes streamed", points: rows },
      detail: (rk.daily || []).filter((r) => r["Total Minutes Streamed"] != null).map((r) => drow(day(r.date, true),
        r["Total Minutes Streamed"], { note: `${int(r.Viewers ?? 0)} viewers · ${int(r.Visitors ?? 0)} visitors` })),
      href: rk.console,
    });
  }
  if (pin?.activeDevices != null) {
    panel(B("engagement"), {
      k: "Android active devices", asOf: asOfIf(pin.asOf, 3), v: int(pin.activeDevices),
      chart: { html: C.timeChart([{ label: "active devices", points: pts(pin.daily, "date", "activeDevices") }], { label: "Android active devices", h: 64 }) },
      series: { label: "Active devices", points: pts(pin.daily, "date", "activeDevices"), agg: "mean" },
      href: "https://play.google.com/console",
    });
  }
  const pu = h.playUsers;
  if (pu) {
    const up = pts(pu.daily, "date", "users");
    panel(B("engagement"), {
      k: "Android daily users",
      v: up.length >= 2 ? int(up[up.length - 1].v) : `<small>${up.length ? "one day reported" : "none reported"}</small>`,
      chart: up.length >= 2 ? { html: C.timeChart([{ label: "users", points: up }], { label: "Android daily users", h: 64 }) } : null,
      cap: up.length < 2 ? `Play returned ${up.length ? `one day (${day(up[0].date)}, ${int(up[0].v)} users)` : "no days"} for ${esc(pu.window || "its window")}; a chart needs two.` : null,
      series: up.length >= 2 ? { label: "Daily users", points: up, agg: "mean" } : null,
    });
  }
  togetherPanel(B("engagement"), h.together);

  /* ── HEALTH ── */
  const x = releaseCtx(d);
  const crashes = h.playCrashes || [];
  const liveC = crashes.filter((c) => !c.stale);
  if (crashes.length) {
    panel(B("health"), {
      k: "Android crash clusters", right: x.playLive ? `live versionCode ${x.playLive}` : "",
      v: liveC.length ? `<span class="down">${liveC.length}</span><small> on the live build · ${crashes.length} in all</small>`
        : `<span class="up">none on the live build</span><small> · ${crashes.length} in all</small>`,
      chart: { html: C.pareto(crashes.map((c) => ({ label: shortLoc(c), value: c.users,
        tone: c.stale ? "measure" : c.type === "CRASH" ? "stop" : "flight" })), { label: "crash clusters by users affected" }) },
      drill: "crashes",
    });
  }
  const vit = h.playVitals || {};
  if (typeof vit.crashRate === "number" || typeof vit.anrRate === "number") {
    let html = "";
    if (typeof vit.crashRate === "number") {
      html += `<div class="cap">Crash rate ${num(vit.crashRate * 100, 2)}%</div>` + C.bullet({
        value: vit.crashRate * 100, max: 3, bands: [1.09, 2], target: 1.09, invert: true,
        tone: vit.crashRate * 100 <= 1.09 ? "live" : "stop",
        label: `crash rate ${(vit.crashRate * 100).toFixed(2)}%` });
    }
    if (typeof vit.anrRate === "number") {
      html += `<div class="cap">ANR rate ${num(vit.anrRate * 100, 2)}%</div>` + C.bullet({
        value: vit.anrRate * 100, max: 2, bands: [0.47, 1], target: 0.47, invert: true,
        tone: vit.anrRate * 100 <= 0.47 ? "live" : "stop",
        label: `ANR rate ${(vit.anrRate * 100).toFixed(2)}%` });
    }
    panel(B("health"), { k: "Android vitals", right: vit.crashRateDays ? plural(vit.crashRateDays, "day") : "", chart: { html },
      cap: "Markers are Google's bad-behavior thresholds.", drill: "crashes" });
  } else if (h.playVitalsNote) {
    panel(B("health"), { k: "Android vitals", v: "<small>no rate published</small>", cap: esc(h.playVitalsNote), drill: "crashes" });
  }
  const pdc = h.playDaily?.crashes || [];
  if (pdc.length >= 2) {
    panel(B("health"), {
      k: "Android crashes per day", asOf: asOfIf(h.playDaily.asOf, 3),
      v: `${pdc.filter((r) => r.date > addDays(pdc[pdc.length - 1].date, -7)).reduce((a, b) => a + (b.crashes || 0), 0)}<small> in the last 7 days</small>`,
      chart: { html: C.timeChart([{ label: "crashes", points: fillZero(pts(pdc, "date", "crashes")) },
        { label: "ANRs", points: fillZero(pts(pdc, "date", "anrs")) }], { label: "Android crashes per day", h: 64 }) },
      series: { label: "crashes", points: fillZero((pts(pdc, "date", "crashes"))), invert: true,
        multi: [{ label: "crashes", points: fillZero(pts(pdc, "date", "crashes")) }, { label: "ANRs", points: fillZero(pts(pdc, "date", "anrs")) }] },
      detail: [...pdc].reverse().map((r) => drow(day(r.date, true), r.crashes || 0, { note: r.anrs ? `${r.anrs} ANR` : "" })),
      href: "https://play.google.com/console",
    });
  }
  const hd = rk?.headline || {};
  const rkPct = hd["Channel Crashes as % of Total Devices Streaming"];
  const rkReb = hd["Rebuffers per Hours Streamed"];
  if (typeof rkPct === "number" || typeof rkReb === "number") {
    let html = "";
    if (typeof rkPct === "number") {
      html += `<div class="cap">Crashes, % of devices streaming: ${num(rkPct, 1)}%</div>` + C.bullet({
        value: rkPct, max: 10, bands: [2, 5], target: 2, invert: true,
        tone: rkPct <= 2 ? "live" : "stop", label: `${rkPct}% of devices streaming crashed` });
    }
    if (typeof rkReb === "number") {
      html += `<div class="cap">Rebuffers per streaming hour: ${num(rkReb, 2)}</div>` + C.bullet({
        value: rkReb, max: 2, bands: [0.5, 1], invert: true,
        tone: rkReb <= 0.5 ? "live" : "flight", label: `${rkReb} rebuffers per streaming hour` });
    }
    panel(B("health"), { k: "Roku stability", right: `${rkDaysWith(rk, "Total Count of Crashes").length} days`,
      chart: { html }, drill: "roku-stability" });
  }
  const perf = h.applePerf;
  if (perf) {
    const regs = perf.regressions || [];
    panel(B("health"), {
      k: "Apple field metrics", right: perf.metrics?.length ? plural(perf.metrics.length, "metric") : "",
      v: regs.length ? `<span class="down">${regs.length}</span><small> regression${regs.length === 1 ? "" : "s"}</small>`
        : (perf.metrics?.length ? `<span class="up">no regressions</span>` : "<small>not enough devices yet</small>"),
      chart: perf.metrics?.length ? { html: C.bars(perf.metrics.slice(0, 5).map((m) => ({
        label: (m.metric || "").replace(/([A-Z])/g, " $1").trim().toLowerCase(),
        value: Number(m.value) || 0, tone: "measure", display: `${m.value}${m.unit ? " " + m.unit : ""}` }))) } : null,
      cap: regs.length ? regs.map((r) => `<b>${esc(r)}</b>`).join(" · ") : null,
      detail: (perf.metrics || []).map((m) => drow((m.metric || "").replace(/([A-Z])/g, " $1").trim().toLowerCase(),
        `${m.value}${m.unit ? " " + m.unit : ""}`)),
    });
  }

  /* ── VOICE ── */
  const ap = (d.ratings || []).find((r) => r.store === "App Store");
  const hist = d.history || [];
  const curH = hist[hist.length - 1] || {}, prevH = hist.length > 1 ? hist[hist.length - 2] : null;
  if (ap && typeof ap.average === "number") {
    panel(B("voice"), {
      k: "App Store rating", right: prevH ? chg(curH.appleRating, prevH.appleRating, `vs ${day(prevH.date)}`, { pctMode: false }) : "",
      v: `${ap.average}<small> of 5 · ${plural(ap.count, "rating")}</small>`,
      chart: { html: C.bullet({ value: ap.average, max: 5, bands: [3, 4], target: 4.5,
        tone: ap.average >= 4 ? "live" : ap.average >= 3 ? "flight" : "stop",
        label: `${ap.average} out of 5, target 4.5` }) },
      cap: staleNote(d, "ratings") || null,
      drill: "history/appleRating",
    });
  } else {
    panel(B("voice"), { k: "App Store rating", v: "<small>not read</small>" });
  }
  const pr = (h.playDaily?.ratings || []).filter((r) => typeof r.total === "number");
  if (pr.length) {
    const last = pr[pr.length - 1];
    const wk = [...pr].reverse().find((r) => r.date <= addDays(last.date, -7));
    panel(B("voice"), {
      k: "Google Play rating", asOf: asOfIf(last.date, 3),
      right: wk ? chg(last.total, wk.total, `vs ${day(wk.date)}`, { pctMode: false }) : "",
      v: `${num(last.total, 2)}<small> of 5 · Play's average to ${day(last.date)}</small>`,
      chart: { html: C.bullet({ value: last.total, max: 5, bands: [3, 4], target: 4.5,
        tone: last.total >= 4 ? "live" : last.total >= 3 ? "flight" : "stop",
        label: `${last.total} out of 5, target 4.5` })
        + C.timeChart([{ label: "average", points: pts(pr, "date", "total") }], { label: "Google Play rating", h: 56, min: 1, max: 5 }) },
      drill: "play-rating",
    });
  } else {
    panel(B("voice"), { k: "Google Play rating", v: "<small>no rating yet</small>",
      cap: esc(d.sources?.play_rating?.note || "") || null });
  }
  const dist = (d.distribution || {})["App Store"];
  if (dist && Object.values(dist).some(Boolean)) {
    const low = (dist[1] || 0) + (dist[2] || 0) + (dist[3] || 0);
    panel(B("voice"), {
      k: "How the App Store reviews fall", right: `${Object.values(dist).reduce((a, b) => a + b, 0)} written`,
      chart: { html: C.bars([5, 4, 3, 2, 1].map((s) => ({ label: `${s} ★`, value: dist[s] || 0,
        tone: s >= 4 ? "live" : s === 3 ? "flight" : "stop" }))) },
      cap: (low ? `<b>${low}</b> under four stars.` : "") + (staleNote(d, "reviews") || "") || null,
      drill: "reviews",
    });
  }
  const bySrc = {};
  (d.mentions || []).forEach((m) => { bySrc[m.source] = (bySrc[m.source] || 0) + 1; });
  const readers = ["Reddit", "Hacker News", "Lemmy", "News", "Bluesky", "Mastodon"];
  const srcRows = readers.map((r) => {
    const key = Object.keys(bySrc).find((k) => k.startsWith(r));
    const readerOff = off("mentions_" + r.toLowerCase().replace(" ", "_").replace("hacker_news", "hn"));
    return { label: r, value: bySrc[key] || 0, tone: "measure",
             display: readerOff ? "—" : String(bySrc[key] || 0), note: readerOff ? "reader offline" : null };
  });
  panel(B("voice"), {
    k: "Mentions", right: prevH ? chg(curH.mentions, prevH.mentions, `vs ${day(prevH.date)}`, { pctMode: false }) : "",
    v: `${int((d.mentions || []).length)}<small> found</small>`,
    chart: { html: C.bars(srcRows, { max: Math.max(3, ...srcRows.map((r) => r.value)) }) },
    drill: "mentions",
  });

  /* ── PROGRAM ── */
  const reach = d.social?.reach || {};
  const reachRows = Object.entries(reach).map(([k, v]) => ({
    label: PLAT(k), value: v?.followers || 0,
    display: v?.error ? "—" : String(v?.followers ?? 0), note: v?.error ? "could not read" : null }));
  panel(B("program"), {
    k: "Followers", right: prevH ? chg(curH.followers, prevH.followers, `vs ${day(prevH.date)}`, { pctMode: false }) : "",
    v: reachRows.length ? `${int(reachRows.reduce((a, b) => a + b.value, 0))}<small> across ${reachRows.length}</small>` : "<small>not read</small>",
    chart: reachRows.length ? { html: C.bars(reachRows) } : null,
    series: { label: "followers", agg: "mean", points: histPoints(d, "followers") },
    detail: Object.entries(reach).map(([k, v]) => drow(PLAT(k), v?.error ? "—" : (v?.followers ?? 0), {
      note: v?.error ? `could not read: ${v.error}` : [v?.posts != null ? `${v.posts} posts` : null,
        v?.views ? `${int(v.views)} views` : null].filter(Boolean).join(" · "), href: PROFILE[k] })),
  });
  const per = d.social?.byPlatform || {};
  const postRows = Object.entries(per).map(([k, v]) => ({ label: PLAT(k), value: v.posts || 0, tone: "measure" }));
  if (postRows.length) {
    const measured = Object.values(per).reduce((a, b) => a + (b.measured || 0), 0);
    panel(B("program"), {
      k: "Posts published", right: prevH ? chg(curH.posts, prevH.posts, `vs ${day(prevH.date)}`, { pctMode: false }) : "",
      v: `${int(d.social?.totalPosts)}<small> still up</small>`,
      chart: { html: C.bars(postRows) },
      cap: measured ? null : "No engagement readings yet; a post is sampled at 20h.",
      drill: "posts",
    });
  }
  trendPanels(B("program"), "program");

  /* ── OPS ── */
  const wf = h.workflows || [];
  const marks = wf.map((f) => ({ label: `${f.severity}: ${wfName(f)}`,
    tone: ["BROKEN", "KILLED"].includes(f.severity) ? "stop" : "flight" }));
  panel(B("ops"), {
    k: "Workflow fleet", right: wf.length ? plural(wf.length, "finding") : "",
    v: wf.length ? `${marks.filter((m) => m.tone === "stop").length}<small> urgent · ${marks.filter((m) => m.tone === "flight").length} failed</small>`
      : `<span class="up">all clear</span>`,
    chart: marks.length ? { html: C.dots(marks, { label: "workflow findings" }) } : null,
    drill: "fleet",
  });
  const g = d.github || {};
  if (g.url) {
    panel(B("ops"), {
      k: "The repository", right: prevH ? chg(curH.stars, prevH.stars, `vs ${day(prevH.date)}`, { pctMode: false }) : "",
      v: `${int(g.stars)}<small> star${g.stars === 1 ? "" : "s"}</small>`,
      chart: { html: C.bars([
        { label: "views 14d", value: g.views14d || 0, tone: "measure",
          display: g.views14d == null ? "—" : int(g.views14d),
          note: g.views14d == null ? "traffic needs a token with repo admin" : null },
        { label: "uniques 14d", value: g.uniques14d || 0, tone: "measure",
          display: g.uniques14d == null ? "—" : int(g.uniques14d) },
        { label: "open issues", value: g.openIssues || 0, tone: g.openIssues ? "flight" : "measure" },
      ]) },
      series: { label: "stars", agg: "mean", points: histPoints(d, "stars") },
      detail: (h.issues || []).map((i) => drow(`#${i.number} ${i.title}`, i.external ? "from outside" : "ours",
        { note: `${i.author} · ${ago(i.updated)}`, href: i.url })),
      href: g.url,
    });
  }
  trendPanels(B("ops"), "ops");
}

function overviewWeek(box) {
  const rows = USAGE.map((k) => SER.get(k)).filter(Boolean).map((s) => {
    const w = wow(s.points, s.agg);
    const stale = isStale(s);
    return { s, w, stale };
  });
  if (!rows.length) return;
  const html = `<div class="wk">` + rows.map(({ s, w, stale }) => {
    const p = w && !stale ? chgParts(w.cur, w.prev, "vs prior 7 days") : null;
    return `<button type="button" class="wk-r" data-nav="series/${esc(s.key)}" data-view="overview">`
      + `<span class="wk-l">${esc(s.label)}</span>`
      + `<span class="wk-v">${w ? int(Math.round(w.cur)) : "—"}</span>`
      + `<span class="wk-d ${stale ? "asof" : p ? p.cls : "flat"}">${esc(stale
        ? `as of ${day(lastDay(s))}` : p ? p.text : "too few days to compare")}</span></button>`;
  }).join("") + `</div>`;
  panel(box, { k: "Last 7 complete days", chart: { wide: true, html }, wide: true });
}

function rkDaysWith(rk, col) { return (rk?.daily || []).filter((r) => r[col] != null); }

function titlesPanel(box, wt) {
  if (!box) return;
  const ranks = ["topPlayed", "topOpened", "topAmbient"];
  const any = wt && ranks.some((k) => (wt[k] || []).length);
  if (!any) {
    panel(box, { k: "What people watch", v: "<small>nothing counted yet</small>" });
    return;
  }
  const p = panel(box, {
    k: "What people watch on the web", right: `${int(wt.distinctPlayed || 0)} films played`,
    v: wt.totals ? `${int(wt.totals.play)}<small> plays from ${int(wt.totals.open)} opens · ${pct(wt.totals.play, wt.totals.open)}</small>` : null,
    chart: { html: titlesBars(wt) },
    drill: "titles",
  });
  titlePanels.push({ p, box });
}

function togetherPanel(box, tg) {
  if (!box) return;
  if (!tg) { panel(box, { k: "Watch Together rooms", v: "<small>not collected yet</small>" }); return; }
  const l = tg.last28 || {}, pv = tg.prev28 || {};
  const series = [
    { label: "rooms", points: pts(tg.daily, "date", "rooms") },
    { label: "guests", points: pts(tg.daily, "date", "guests") },
  ].filter((s) => s.points.length);
  panel(box, {
    k: "Watch Together rooms", right: chg(l.rooms, pv.rooms, "vs prior 28 days"),
    v: typeof l.rooms === "number"
      ? `${int(l.rooms)}<small> rooms${typeof l.guests === "number" ? ` · ${int(l.guests)} guests` : ""} · 28 days</small>`
      : "<small>no 28-day total</small>",
    chart: series.length ? { html: C.timeChart(series, { label: "Watch Together rooms", h: 64 }) } : null,
    cap: typeof l.lives === "number" ? `${plural(l.lives, "YouTube show")} in 28 days` : null,
    drill: "together",
  });
}

/* ── over time: one reading a day ─────────────────────────────────────── */
const HIST = [
  { key: "appleRating", label: "App Store rating", view: "overview", pctMode: false },
  { key: "appleRatings", label: "App Store ratings", view: "overview", pctMode: false },
  { key: "playRating", label: "Google Play rating", view: "overview", pctMode: false },
  { key: "reviews", label: "Reviews", view: "overview", pctMode: false },
  { key: "mentions", label: "Mentions", view: "overview", pctMode: false },
  { key: "catalogItems", label: "Catalog titles", view: "overview", pctMode: false },
  { key: "urgent", label: "Urgent findings", view: "overview", pctMode: false, invert: true },
  // Followers, posts and stars are drawn by their own panels, whose drawers
  // carry the history; only the series with no panel of its own is listed.
  { key: "followers", label: "Followers", view: "-", pctMode: false },
  { key: "likes", label: "Post engagement", view: "program", pctMode: false },
  { key: "posts", label: "Posts published", view: "-", pctMode: false },
  { key: "stars", label: "GitHub stars", view: "-", pctMode: false },
  { key: "views14d", label: "Repo views (14d)", view: "ops", pctMode: false },
];
function histPoints(d, key) { return pts(d.history, "date", key); }
function histBack(p, days) {
  const last = p[p.length - 1];
  return [...p].reverse().find((q) => q.date <= addDays(last.date, -days)) || null;
}
function trendPanels(box, view) {
  if (!box) return;
  HIST.filter((s) => s.view === view).forEach((s) => {
    const p = histPoints(D, s.key);
    if (!p.length) return;
    const last = p[p.length - 1];
    const back = histBack(p, 7) || (p.length > 1 ? p[0] : null);
    panel(box, {
      k: s.label,
      right: back ? chg(last.v, back.v, `vs ${day(back.date)}`, s) : "one reading so far",
      v: num(last.v),
      chart: p.length >= 2 ? { html: C.timeChart([{ label: s.label, points: p }], { label: s.label, h: 46, mini: true }) } : null,
      drill: `history/${s.key}`,
    });
  });
}
function trend(d) {
  const box = $("trend"); if (!box) return;
  box.innerHTML = "";
  if ((d.history || []).length < 2) {
    box.appendChild(el("p", "clear", `Only ${(d.history || []).length} reading so far; every series appears from the second day.`));
    return;
  }
  const grid = el("div", "panels");
  grid.dataset.view = "overview";
  trendPanels(grid, "overview");
  box.appendChild(grid);
}

/* ── what people said ─────────────────────────────────────────────────── */
let saidFilter = "all";
const wantKey = (t) => (t || "").replace(/…$/, "");
function said(d) {
  const box = $("said"); if (!box) return;
  box.innerHTML = "";
  const asks = (d.asks || []).map((a) => wantKey(a.text));
  const isWant = (text) => asks.some((t) => t && (text || "").includes(t));
  const items = [
    ...(d.reviews || []).map((r) => ({
      kind: "review", src: r.store, who: r.author, date: r.date, url: r.url,
      rating: r.rating, lead: r.title, text: r.body, tag: r.territory,
      extra: r.responded ? "replied" : "not replied", route: `review/${reviewId(r)}` })),
    ...(d.mentions || []).map((m, i) => ({
      kind: "mention", src: m.source, who: m.author, date: m.date, url: m.url,
      lead: m.title, text: m.excerpt, route: `mention/${i}`,
      extra: [m.likes && `${m.likes} likes`, m.points && `${m.points} points`].filter(Boolean).join(" · ") || null })),
  ].sort((a, b) => (b.date || "").localeCompare(a.date || ""));
  const shown = items.filter((i) => saidFilter === "all"
    || (saidFilter === "reviews" && i.kind === "review")
    || (saidFilter === "mentions" && i.kind === "mention")
    || (saidFilter === "asks" && isWant(i.text)));
  const cnt = $("said-n"); if (cnt) cnt.textContent = items.length;
  if (!shown.length) {
    box.appendChild(el("p", "clear", items.length ? "Nothing under this filter."
      : "Nobody has said anything yet that our readers can see."));
    return;
  }
  shown.forEach((i) => {
    const r = el("div", "row");
    const who = el("div", "who");
    who.appendChild(el("span", "src", i.src));
    if (i.rating) who.appendChild(el("span", "stars", stars(i.rating)));
    if (i.who) who.appendChild(el("span", null, i.who));
    if (i.tag) who.appendChild(el("span", null, i.tag));
    who.appendChild(el("span", null, ago(i.date)));
    if (i.extra) who.appendChild(el("span", null, i.extra));
    r.appendChild(who);
    const q = el("button", "quote" + (isWant(i.text) ? " want" : ""));
    q.type = "button";
    q.onclick = () => nav(i.route);
    if (i.lead) q.appendChild(el("span", "lead", i.lead + " "));
    q.appendChild(document.createTextNode(i.text || ""));
    r.appendChild(q);
    box.appendChild(r);
  });
}
function saidChips(d) {
  const box = $("said-chips"); if (!box) return;
  box.innerHTML = "";
  const counts = {
    all: (d.reviews || []).length + (d.mentions || []).length,
    reviews: (d.reviews || []).length, mentions: (d.mentions || []).length, asks: (d.asks || []).length,
  };
  Object.entries(counts).forEach(([k, v]) => {
    const b = el("button", null, `${k[0].toUpperCase()}${k.slice(1)} ${v}`);
    b.type = "button";
    b.setAttribute("aria-pressed", String(saidFilter === k));
    b.onclick = () => { saidFilter = k; saidChips(d); said(d); };
    box.appendChild(b);
  });
}

const PROFILE = {
  bluesky: "https://bsky.app/profile/archivewatch.bsky.social",
  mastodon: "https://mastodon.social/@archivewatch",
  instagram: "https://www.instagram.com/archivewatch.org/",
  threads: "https://www.threads.net/@archivewatch.org",
  youtube: "https://www.youtube.com/@archivewatch",
  facebook: "https://www.facebook.com/archivewatch.org",
};
const PLAT_NAMES = { youtube: "YouTube", bluesky: "Bluesky", mastodon: "Mastodon",
  instagram: "Instagram", threads: "Threads", facebook: "Facebook" };
const PLAT = (p) => PLAT_NAMES[p] || (p ? p[0].toUpperCase() + p.slice(1) : "");

/* ── the program ──────────────────────────────────────────────────────── */
const postCols = [
  { k: "title", label: "Post", route: (r) => `post/${r.i}`, fmt: (v, r) => `${r.live === false ? "✗ " : ""}${v || r.id}` },
  { k: "platform", label: "Where", fmt: (v) => PLAT(v) },
  { k: "at", label: "When", fmt: (v) => whenMT(v) },
  { k: "format", label: "Format", fmt: (v) => v || "" },
  { k: "slot", label: "Slot", fmt: (v) => v || "" },
  { k: "likes", label: "Likes", num: true },
  { k: "reposts", label: "Reposts", num: true },
  { k: "replies", label: "Replies", num: true },
  { k: "views", label: "Views", num: true },
  { k: "live", label: "Live", fmt: (v) => (v === false ? "deleted" : v == null ? "not verified" : "yes") },
];
const postRowsOf = (d) => (d.social?.posts || []).map((p, i) => ({ ...p, i }));

function social(d) {
  const box = $("social"); if (!box) return;
  box.innerHTML = "";
  const per = d.social?.byPlatform || {};
  const reach = d.social?.reach || {};
  const posts = d.social?.posts || [];
  const names = [...new Set([...Object.keys(per), ...Object.keys(reach)])].sort();
  const cnt = $("social-n"); if (cnt) cnt.textContent = d.social?.totalPosts ?? "";
  if (!names.length) { box.appendChild(el("p", "clear", "The program has not posted yet.")); return; }
  const lanes = names.map((p) => ({
    label: PLAT(p),
    marks: posts.filter((x) => x.platform === p).map((x) => ({
      at: x.at, size: Math.min(8, (x.likes || 0) + (x.reposts || 0) + (x.replies || 0)),
      title: `${x.title || x.id} · ${whenMT(x.at)}` + (x.likes != null ? ` · ${x.likes} likes` : " · not measured"),
      tone: x.likes ? "live" : "measure" })),
  }));
  const grid = el("div", "panels");
  grid.dataset.view = "program";
  panel(grid, { k: "Cadence", right: "last 30 days",
    chart: { wide: true, html: C.cadence(lanes, { days: 30, label: "posts per platform" }) }, drill: "posts" });
  const engRows = names.map((p) => {
    const s2 = per[p] || {}, r = reach[p] || {};
    const eng = (s2.likes || 0) + (s2.reposts || 0) + (s2.replies || 0);
    return { label: PLAT(p), value: eng, tone: eng ? "live" : "measure", display: s2.measured ? String(eng) : "—",
      note: [s2.posts ? plural(s2.posts, "post") : null,
             s2.posts && !s2.measured ? "no reading yet" : null,
             r.error ? `could not read: ${r.error}` : null].filter(Boolean).join(" · ") };
  });
  panel(grid, { k: "What it earned",
    right: [d.social?.deleted ? `${d.social.deleted} deleted` : null,
            d.social?.unverified ? `${d.social.unverified} unverified` : null,
            `${d.social?.measured || 0} measured`].filter(Boolean).join(" · "),
    chart: { wide: true, html: C.bars(engRows) }, drill: "posts" });
  box.appendChild(grid);
  box.appendChild(table({ title: "Every post", rows: postRowsOf(d), cols: postCols, sort: { k: "at", dir: -1 } }));
}

/* ── sources ──────────────────────────────────────────────────────────── */
function staleNote(d, key) {
  const at = (d.stale || {})[key];
  return at ? ` Standing on the reading from ${ago(at)}; its reader is offline.` : "";
}
function sources(d) {
  const box = $("sources"); if (!box) return;
  box.innerHTML = "";
  const rows = Object.entries(d.sources || {});
  const ok = rows.filter(([, v]) => v.ok).length;
  const cnt = $("src-n"); if (cnt) cnt.textContent = `${ok}/${rows.length}`;
  const grid = el("div", "panels");
  grid.dataset.view = "ops";
  panel(grid, {
    k: "Readers", right: `${ok} of ${rows.length}`, v: `${ok}<small> answered</small>`,
    chart: { html: C.dots(rows.map(([k, v]) => ({ label: k + (v.ok ? " — ok" : " — could not read"),
      tone: v.ok ? "live" : "flight" })), { label: "one mark per reader" }) },
    cap: ok === rows.length ? null : `<b>${rows.length - ok}</b> could not read.`,
    drill: "sources",
  });
  box.appendChild(grid);
  rows.forEach(([k, v]) => {
    const r = row(box, { name: k, route: "sources", meta: `${v.ok ? "" : "could not read — "}${v.note || ""}`,
      num: `<small>${esc(v.at ? whenMT(v.at) : "")}</small>`, cls: v.ok ? "" : "off" });
    r.classList.add(v.ok ? "lead-live" : "lead-flight");
  });
}

/* ── search (Google Search Console) ───────────────────────────────────── */
const SC_COLS = (keyLabel, keyFmt) => [
  { k: "key", label: keyLabel, fmt: keyFmt || ((v) => v) },
  { k: "clicks", label: "Clicks", num: true },
  { k: "d", label: "vs prior 28 days", num: true, sortv: (r) => (r.clicks || 0) - (r.prevClicks || 0),
    fmt: (_, r) => (typeof r.prevClicks === "number" ? chgText(r.clicks || 0, r.prevClicks, "", { pctMode: false }) || "no change" : "—"),
    cls: (r) => (chgParts(r.clicks || 0, r.prevClicks, "") || {}).cls },
  { k: "impressions", label: "Impressions", num: true },
  { k: "prevImpressions", label: "Prior impressions", num: true },
  { k: "ctr", label: "CTR", num: true, fmt: (v) => (typeof v === "number" ? `${num(v * 100, 1)}%` : "—") },
  { k: "position", label: "Position", num: true, fmt: (v) => num(v, 1) },
];
function search(d) {
  const box = $("tiles-search"); if (!box) return;
  box.innerHTML = ""; box.dataset.view = "search";
  const sc = d.health?.searchConsole;
  if (!sc) {
    panel(box, { k: "Google Search", v: "<small>not collected yet</small>",
      cap: d.sources?.search_console?.note ? esc(d.sources.search_console.note) : null });
    return;
  }
  const l = sc.last28 || {};
  // No comparison until a WHOLE prior 28 days exists: the property's data
  // began 2026-09-20, and "+263 vs prior 28 days" against nothing is a claim
  // about a period Google never measured.
  const hasPrev = (sc.prev28?.days || 0) >= 28 && sc.prev28?.impressions > 0;
  const pv = hasPrev ? sc.prev28 : {};
  const since = !hasPrev && sc.daily?.length ? `data from ${day(sc.daily[0].date)}` : null;
  const through = sc.through || lastDay(SER.get("search-clicks") || { points: [] });
  const asOf = asOfIf(through, 4);
  const clicks = pts(sc.daily, "date", "clicks"), imps = pts(sc.daily, "date", "impressions");
  panel(box, { k: "Clicks", asOf, right: since || chg(l.clicks, pv.clicks, "vs prior 28 days"),
    v: `${int(l.clicks)}<small> in 28 days${through ? ` to ${day(through)}` : ""}</small>`,
    chart: clicks.length >= 2 ? { html: C.timeChart([{ label: "clicks", points: clicks }], { label: "Search clicks", h: 80, band: true }) } : null,
    drill: "series/search-clicks" });
  panel(box, { k: "Impressions", asOf, right: since || chg(l.impressions, pv.impressions, "vs prior 28 days"),
    v: `${int(l.impressions)}<small> in 28 days</small>`,
    chart: imps.length >= 2 ? { html: C.timeChart([{ label: "impressions", points: imps }], { label: "Search impressions", h: 80, band: true }) } : null,
    drill: "series/search-impr" });
  panel(box, { k: "Click-through rate", right: chg(l.ctr, pv.ctr, "vs prior 28 days", { pctMode: false, unit: "", dp: 3 }),
    v: typeof l.ctr === "number" ? `${num(l.ctr * 100, 2)}%<small> of impressions clicked</small>` : "—",
    chart: (sc.daily || []).length >= 2 ? { html: C.timeChart([{ label: "CTR", points: (sc.daily || []).filter((r) => typeof r.ctr === "number").map((r) => ({ date: r.date, v: +(r.ctr * 100).toFixed(2) })) }], { label: "Click-through rate", h: 56, unit: "%" }) } : null,
    series: { label: "CTR %", agg: "mean", points: (sc.daily || []).filter((r) => typeof r.ctr === "number").map((r) => ({ date: r.date, v: +(r.ctr * 100).toFixed(2) })) } });
  panel(box, { k: "Average position", right: chg(l.position, pv.position, "vs prior 28 days", { pctMode: false, invert: true, dp: 1 }),
    v: typeof l.position === "number" ? `${num(l.position, 1)}<small> lower is better</small>` : "—",
    chart: (sc.daily || []).length >= 2 ? { html: C.timeChart([{ label: "position", points: pts(sc.daily, "date", "position") }], { label: "Average position (lower is better)", h: 56 }) } : null,
    series: { label: "Average position", agg: "mean", invert: true, points: pts(sc.daily, "date", "position") } });
  const q = sc.queries || [];
  if (q.length) {
    panel(box, { k: "Top queries", right: `${q.length} in 28 days`,
      chart: { html: C.bars(q.slice().sort((a, b) => (b.clicks || 0) - (a.clicks || 0)).slice(0, 8)
        .map((r) => ({ label: r.key, value: r.clicks || 0, tone: "measure" }))) },
      drill: "search-queries" });
    const moved = !hasPrev ? [] : q.filter((r) => typeof r.prevClicks === "number")
      .map((r) => ({ ...r, dd: (r.clicks || 0) - r.prevClicks })).filter((r) => r.dd);
    const up = moved.filter((r) => r.dd > 0).sort((a, b) => b.dd - a.dd).slice(0, 4);
    const down = moved.filter((r) => r.dd < 0).sort((a, b) => a.dd - b.dd).slice(0, 4);
    if (hasPrev) panel(box, { k: "Rising and falling queries", right: "clicks vs prior 28 days",
      chart: { html: up.length || down.length ? C.bars([
        ...up.map((r) => ({ label: r.key, value: r.dd, tone: "live", display: `+${r.dd}` })),
        ...down.map((r) => ({ label: r.key, value: -r.dd, tone: "stop", display: `−${-r.dd}` })),
      ]) : `<p class="clear">No query moved.</p>` },
      drill: "search-rising" });
  }
  [["pages", "Pages", "search-pages"], ["countries", "Countries", "search-countries"],
   ["devices", "Devices", "search-devices"]].forEach(([k, label, route]) => {
    const rs = sc[k] || [];
    if (!rs.length) return;
    panel(box, { k: label, right: `${rs.length}`,
      chart: { html: (k === "countries" ? C.dotPlot : C.bars)(rs.slice().sort((a, b) => (b.clicks || 0) - (a.clicks || 0)).slice(0, 8)
        .map((r) => ({ label: k === "countries" ? String(r.key).toUpperCase() : k === "pages" ? pagePath(r.key) : r.key,
          value: r.clicks || 0, tone: "measure" }))) },
      drill: route });
  });
  const sm = sc.sitemaps || [];
  panel(box, { k: "Sitemaps", right: sm.length ? plural(sm.length, "sitemap") : "",
    v: sm.length ? (sm.some((m) => Number(m.errors) > 0)
      ? `<span class="down">${sm.reduce((a, m) => a + Number(m.errors || 0), 0)}</span><small> errors</small>`
      : `<span class="up">no errors</span>`) : "<small>none submitted</small>",
    cap: sm.map((m) => `${esc(m.path)}: ${int(Number(m.indexed ?? 0))} of ${int(Number(m.submitted ?? 0))} indexed`).join("<br>") || null,
    drill: sm.length ? "search-sitemaps" : null, href: sc.url });
}
const pagePath = (u) => String(u || "").replace(/^https?:\/\/[^/]+/, "") || "/";

/* ═══════════════════════════════════════════════════════════════════════
   DRAWERS — the global kinds. Each returns a spec for renderSpec(); a
   drawer about ONE thing (a crash cluster, a review, a post) carries its
   full record where a series drawer carries its chart.
   ═══════════════════════════════════════════════════════════════════════ */
const crashCols = (x) => [
  { k: "loc", label: "Cluster", route: (r) => `crash/${crashId(r)}`, sortv: (r) => shortLoc(r), fmt: (_, r) => shortLoc(r) },
  { k: "type", label: "Type" },
  { k: "users", label: "Users", num: true },
  { k: "reports", label: "Reports", num: true },
  { k: "builds", label: "Builds", sortv: (r) => Number(r.lastBuild) || 0, fmt: (_, r) => `${r.firstBuild}–${r.lastBuild}` },
  { k: "api", label: "API" },
  { k: "lastSeen", label: "Last seen", fmt: (v) => day(v, true) },
  { k: "live", label: "Live build", sortv: (r) => (r.stale ? 0 : 1), fmt: (_, r) => (r.stale ? "no" : "yes"),
    cls: (r) => (r.stale ? "" : "down") },
  { k: "fix", label: "Fix", sortv: (r) => crashStatus(r, x).k, fmt: (_, r) => crashStatus(r, x).word },
];
const DRAWERS = {
  crash(d, [cid]) {
    const x = releaseCtx(d);
    const c = (d.health?.playCrashes || []).find((q) => crashId(q) === cid);
    if (!c) return null;
    const f = c.fixedIn, st = crashStatus(c, x);
    return {
      title: `${c.type === "CRASH" ? "Crash" : "ANR"}: ${shortLoc(c)}`,
      facts: [["Cause", c.cause], ["Location", c.location], ["Our stack line", c.ours],
        ["Users", int(c.users)], ["Reports", int(c.reports)], ["Builds", `${c.firstBuild}–${c.lastBuild}`],
        ["Android API", c.api], ["Last seen", whenMT(c.lastSeen)],
        ["On the live build", c.stale ? "no" : "yes", c.stale ? "up" : "down"],
        ["Fix", f ? [f.what, f.fix].filter(Boolean).join(" — ") : "none recorded"],
        ["Fixed in", f ? [f.version && vstr(f.version), f.versionCode && `versionCode ${f.versionCode}`].filter(Boolean).join(", ") : ""],
        ["Release state", st.word, st.k === "shipped" ? "up" : st.k === "review" ? "" : "down"],
        ["Play production", x.playLive ? `versionCode ${x.playLive}` : "unknown"],
        ["In flight", x.playInflight ? `versionCode ${x.playInflight}` : ""]],
      source: { href: c.url || "https://play.google.com/console", label: "Play Console" },
    };
  },
  crashes(d) {
    const x = releaseCtx(d);
    const cs = d.health?.playCrashes || [];
    const pdc = d.health?.playDaily?.crashes || [];
    const s = { points: fillZero((pts(pdc, "date", "crashes"))), invert: true };
    return {
      title: "Android crash clusters",
      deltas: pdc.length ? seriesDeltas(s.points, s) : [],
      charts: [pdc.length >= 2 ? C.timeChart([{ label: "crashes", points: fillZero(pts(pdc, "date", "crashes")) },
        { label: "ANRs", points: fillZero(pts(pdc, "date", "anrs")) }], { label: "Android crashes per day", h: 130 }) : ""],
      tables: [{ title: "Every cluster", rows: cs, cols: crashCols(x), sort: { k: "users", dir: -1 } }],
      source: { href: "https://play.google.com/console", label: "Play Console vitals" },
    };
  },
  review(d, [id]) {
    const r = (d.reviews || []).find((q) => reviewId(q) === id);
    if (!r) return null;
    return {
      title: `${stars(r.rating)} ${r.store}`,
      quote: { lead: r.title, text: r.body },
      facts: [["Rating", `${r.rating} of 5`], ["Author", r.author], ["Left", whenMT(r.date)],
        ["Territory", r.territory], ["Device", r.device], ["App version", r.appVersion && vstr(r.appVersion)],
        ["Replied", r.responded ? "yes" : "not yet", r.responded ? "up" : "down"]],
      source: { href: r.url, label: r.responded ? "Open in the console" : "Reply in the console" },
    };
  },
  reviews(d) {
    const rs = (d.reviews || []).map((r) => ({ ...r }));
    return {
      title: "Every review",
      charts: [C.timeChart([{ label: "App Store rating", points: histPoints(d, "appleRating") }],
        { label: "App Store rating", h: 100, min: 1, max: 5 })],
      tables: [{ rows: rs, sort: { k: "date", dir: -1 }, cols: [
        { k: "title", label: "Review", route: (r) => `review/${reviewId(r)}`, fmt: (v, r) => v || clip(r.body, 60) },
        { k: "rating", label: "Stars", num: true },
        { k: "store", label: "Store" },
        { k: "date", label: "Left", fmt: (v) => day(v, true) },
        { k: "responded", label: "Replied", fmt: (v) => (v ? "yes" : "no"), cls: (r) => (r.responded ? "" : "down") },
      ] }],
      source: { href: "https://appstoreconnect.apple.com/apps/6776697407/distribution/reviews", label: "App Store Connect" },
    };
  },
  mention(d, [i]) {
    const m = (d.mentions || [])[Number(i)];
    if (!m) return null;
    return { title: `${m.source}${m.author ? ` · ${m.author}` : ""}`, quote: { lead: m.title, text: m.excerpt },
      facts: [["When", whenMT(m.date)], ["Likes", m.likes], ["Reposts", m.reposts], ["Points", m.points]],
      source: { href: m.url, label: "Open the post" } };
  },
  mentions(d) {
    return { title: "Mentions", tables: [{ rows: (d.mentions || []).map((m, i) => ({ ...m, i })), sort: { k: "date", dir: -1 }, cols: [
      { k: "excerpt", label: "Said", route: (r) => `mention/${r.i}`, fmt: (v, r) => clip(r.title || v, 80) },
      { k: "source", label: "Where" }, { k: "author", label: "Who", fmt: (v) => v || "" },
      { k: "date", label: "When", fmt: (v) => day(v, true) },
    ] }] };
  },
  store(d, [slug]) {
    const s = (d.stores || []).find((q) => storeSlug(q) === slug);
    if (!s) return null;
    const h = d.health || {};
    const siblings = (d.stores || []).filter((q) => q.store === s.store && q !== s);
    const fl = s.inFlight;
    const tables = [];
    if (siblings.length) {
      tables.push({ title: `Other ${s.store} tracks`, rows: siblings, cols: [
        { k: "platform", label: "Track", route: (r) => `store/${storeSlug(r)}` },
        { k: "state", label: "State", fmt: (v) => STATE_WORD(v || "") },
        { k: "version", label: "Version", fmt: (v) => vstr(v) },
        { k: "live", label: "Live", fmt: (v) => vstr(v) },
        { k: "build", label: "Build", fmt: (v) => v || "" },
      ] });
    }
    if (s.store.startsWith("Roku") && (h.rokuEngagement?.versionsSeen || []).length) {
      tables.push({ title: "Versions seen running on Roku devices", rows: h.rokuEngagement.versionsSeen, sort: { k: "lastSeen", dir: -1 }, cols: [
        { k: "version", label: "Version", fmt: (v) => vstr(v) },
        { k: "firstSeen", label: "First seen", fmt: (v) => day(v, true) },
        { k: "lastSeen", label: "Last seen", fmt: (v) => day(v, true) },
      ] });
    }
    if (s.store.startsWith("Amazon") && (h.amazonLive?.builds || []).length) {
      tables.push({ title: "Builds on the live release", rows: h.amazonLive.builds, cols: [
        { k: "versionCode", label: "versionCode", num: true }, { k: "name", label: "Name" }] });
    }
    return {
      title: `${s.store} · ${s.platform}`,
      facts: [["State", STATE_WORD(s.state || ""), STATE_CLASS(s.state || "") === "stop" ? "down" : ""],
        ["Version", vstr(s.version)], ["Live", s.live ? vstr(s.live) : ""], ["Build", s.build],
        ["Waiting to go live", fl && fl.version ? `${vstr(fl.version)}${fl.build ? ` (build ${fl.build})` : ""}, ${STATE_WORD(fl.state || "in flight").toLowerCase()}` : ""],
        ["Live is behind by", fl && fl.version && s.live ? `${vstr(s.live)} is live; ${vstr(fl.version)} is waiting` : ""],
        ["Live build (API)", s.store.startsWith("Amazon") && h.amazonLive?.liveVersionCode ? `versionCode ${h.amazonLive.liveVersionCode}` : ""],
        ["Since", s.since ? day(s.since, true) : ""], ["How it is read", s.route || (s.manual ? "declared by hand" : "store API")],
        ["Note", s.note]],
      tables,
      source: { href: s.url, label: s.store },
    };
  },
  stores(d) {
    return { title: "Every store", tables: [{ rows: d.stores || [], cols: [
      { k: "store", label: "Store", route: (r) => `store/${storeSlug(r)}`, fmt: (v, r) => `${v} · ${r.platform}` },
      { k: "state", label: "State", fmt: (v) => STATE_WORD(v || ""), cls: (r) => ({ live: "up", stop: "down" })[STATE_CLASS(r.state || "")] || "" },
      { k: "version", label: "Version", fmt: (v) => vstr(v) },
      { k: "live", label: "Live", fmt: (v) => (v ? vstr(v) : "") },
      { k: "inFlight", label: "Waiting", sortv: (r) => r.inFlight?.version || null, fmt: (v) => (v && v.version ? vstr(v.version) : "") },
      { k: "since", label: "Since", fmt: (v) => (v ? day(v, true) : "") },
    ] }] };
  },
  series(d, [key]) {
    const s = SER.get(key);
    return s ? seriesSpec(s) : null;
  },
  history(d, [key]) {
    const meta = HIST.find((s) => s.key === key) || { key, label: key, pctMode: false };
    const p = histPoints(d, key);
    if (!p.length) return null;
    const rows = p.map((q, i) => ({ date: q.date, v: q.v, dv: i ? q.v - p[i - 1].v : null }));
    const last = p[p.length - 1], prev = p[p.length - 2], wk = histBack(p, 7);
    return {
      title: meta.label,
      deltas: [
        prev ? { label: "1 day", html: chg(last.v, prev.v, `vs ${day(prev.date)}`, meta) } : null,
        wk ? { label: "7 days", html: chg(last.v, wk.v, `vs ${day(wk.date)}`, meta) } : null,
        p.length > 2 ? { label: "Whole window", html: chg(last.v, p[0].v, `since ${day(p[0].date)}`, meta) } : null,
      ].filter(Boolean),
      charts: [C.timeChart([{ label: meta.label, points: p }], { label: meta.label, h: 150, min: key.includes("Rating") && !key.endsWith("s") ? 1 : null })],
      tables: [{ title: "Every reading", rows, sort: { k: "date", dir: -1 }, cols: [
        { k: "date", label: "Day", fmt: (v) => day(v, true) },
        { k: "v", label: meta.label, num: true },
        { k: "dv", label: "vs previous reading", num: true, fmt: (v) => (v == null ? "" : v === 0 ? "no change" : `${v > 0 ? "+" : "−"}${num(Math.abs(v))}`),
          cls: (r) => (r.dv ? ((meta.invert ? r.dv < 0 : r.dv > 0) ? "up" : "down") : "") },
      ] }],
    };
  },
  fleet(d) {
    const wf = d.health?.workflows || [];
    return { title: "Workflow fleet",
      note: wf.length ? null : "Every scheduled run produced something.",
      tables: [{ rows: wf, cols: [
        { k: "workflow", label: "Workflow", href: (r) => wfRuns(r), fmt: (_, r) => wfName(r) },
        { k: "severity", label: "Finding", cls: (r) => (["BROKEN", "KILLED"].includes(r.severity) ? "down" : "warn") },
        { k: "tier", label: "Tier", sortv: (r) => (["BROKEN", "KILLED"].includes(r.severity) ? 0 : 1),
          fmt: (_, r) => (["BROKEN", "KILLED"].includes(r.severity) ? "decide" : "watch") },
      ] }],
      source: { href: `${REPO}/actions`, label: "GitHub Actions" } };
  },
  sources(d) {
    const rows = Object.entries(d.sources || {}).map(([k, v]) => ({ k, ...v }));
    return { title: "Readers",
      sub: d.generatedAt ? `This reading was written ${whenMT(d.generatedAt)} (${ago(d.generatedAt)}).` : null,
      tables: [{ rows, sort: { k: "ok", dir: 1 }, cols: [
        { k: "k", label: "Reader" },
        { k: "ok", label: "Answered", sortv: (r) => (r.ok ? 1 : 0), fmt: (v) => (v ? "yes" : "no"), cls: (r) => (r.ok ? "" : "warn") },
        { k: "note", label: "What it said", fmt: (v) => v || "" },
        { k: "at", label: "Ran", fmt: (v) => (v ? whenMT(v) : "") },
      ] }],
      source: { href: `${REPO}/actions/workflows/pulse.yml`, label: "The Pulse workflow" } };
  },
  asks(d) {
    return { title: "Requests", note: (d.asks || []).length ? null : "Nobody has asked for anything our readers can see.",
      tables: [{ rows: d.asks || [], sort: { k: "date", dir: -1 }, cols: [
        { k: "text", label: "What they asked for", href: (r) => r.url },
        { k: "who", label: "Who", fmt: (v) => v || "someone" }, { k: "where", label: "Where" },
        { k: "date", label: "When", fmt: (v) => day(v, true) }] }] };
  },
  loves(d) {
    return { title: "Praise", tables: [{ rows: d.loves || [], sort: { k: "date", dir: -1 }, cols: [
      { k: "text", label: "What they said", href: (r) => r.url },
      { k: "who", label: "Who", fmt: (v) => v || "someone" }, { k: "where", label: "Where" },
      { k: "date", label: "When", fmt: (v) => day(v, true) }] }] };
  },
  "play-rating"(d) {
    const pr = (d.health?.playDaily?.ratings || []).filter((r) => typeof r.total === "number");
    const p = pts(pr, "date", "total");
    return {
      title: "Google Play rating",
      deltas: seriesDeltas(p, { agg: "mean" }),
      charts: [C.timeChart([{ label: "average", points: p }], { label: "Google Play rating", h: 130, min: 1, max: 5 })],
      tables: [{ rows: pr, sort: { k: "date", dir: -1 }, cols: [
        { k: "date", label: "Day", fmt: (v) => day(v, true) },
        { k: "daily", label: "That day's average", num: true, fmt: (v) => (v ? num(v, 2) : "no rating") },
        { k: "total", label: "Average", num: true, fmt: (v) => num(v, 2) }] }],
      source: { href: "https://play.google.com/console", label: "Play Console" },
    };
  },
  funnel(d) {
    const a = d.health?.playAcquisition;
    if (!a) return null;
    const rows = (a.daily || []).map((r) => ({ ...r, conv: r.visitors ? r.acquisitions / r.visitors : null }));
    const kv = (o) => Object.entries(o || {}).map(([k, v]) => ({ k, v }));
    return {
      title: "Android store listing",
      sub: a.asOf ? `Google's export runs to ${day(a.asOf, true)}.` : null,
      deltas: seriesDeltas(pts(a.daily, "date", "acquisitions")),
      charts: [C.timeChart([{ label: "visitors", points: pts(a.daily, "date", "visitors") },
        { label: "acquisitions", points: pts(a.daily, "date", "acquisitions") }], { label: "Store listing funnel", h: 150 })],
      facts: [["Visitors, 28 days", int(a.visitors28d)], ["Acquisitions, 28 days", int(a.acquisitions28d)],
        ["Conversion", a.conversion28d != null ? `${num(a.conversion28d * 100, 1)}%` : ""]],
      tables: [
        { title: "By day", rows, sort: { k: "date", dir: -1 }, cols: [
          { k: "date", label: "Day", fmt: (v) => day(v, true) },
          { k: "visitors", label: "Visitors", num: true }, { k: "acquisitions", label: "Acquisitions", num: true },
          { k: "conv", label: "Conversion", num: true, fmt: (v) => (v == null ? "—" : `${Math.round(v * 100)}%`) }] },
        { title: "By source", rows: kv(a.bySource), sort: { k: "v", dir: -1 }, cols: [{ k: "k", label: "Source" }, { k: "v", label: "Acquisitions", num: true }] },
        { title: "By country", rows: kv(a.byCountry), sort: { k: "v", dir: -1 }, cols: [{ k: "k", label: "Country" }, { k: "v", label: "Acquisitions", num: true }] },
      ],
      source: { href: "https://play.google.com/console", label: "Play Console" },
    };
  },
  "roku-stability"(d) {
    const rk = d.health?.rokuEngagement;
    if (!rk) return null;
    const hd = rk.headline || {};
    const logs = ((rk.byReport || {})["App Health"] || {}).tables || {};
    const raw = logs.brightscript_crash_logs || [];
    const groups = new Map();
    raw.forEach((r) => {
      const key = r["Error Text"] || r.Backtrace || "unknown";
      const g = groups.get(key) || { text: key, crashes: 0, devices: 0, versions: new Set(), os: new Set(), first: null, last: null };
      g.crashes += Number(r["Total Count of Crashes"]) || 0;
      g.devices += Number(r["Total Count of Devices with Crashes"]) || 0;
      if (r["App Version"]) g.versions.add(r["App Version"]);
      if (r["Roku OS Release"]) g.os.add(r["Roku OS Release"]);
      const dt = r.Date || r["Error Key Date"];
      if (dt) { g.first = !g.first || dt < g.first ? dt : g.first; g.last = !g.last || dt > g.last ? dt : g.last; }
      groups.set(key, g);
    });
    const vs = rk.versionsSeen || [];
    return {
      title: "Roku stability",
      facts: [["Crashes, % of devices streaming", hd["Channel Crashes as % of Total Devices Streaming"] != null ? `${num(hd["Channel Crashes as % of Total Devices Streaming"], 1)}%` : ""],
        ["Crashes per streaming hour", num(hd["Channel Crashes per Streaming Hour"], 3)],
        ["Rebuffers per streaming hour", num(hd["Rebuffers per Hours Streamed"], 2)]],
      deltas: seriesDeltas(pts(rk.daily, "date", "Total Count of Crashes"), { invert: true }),
      charts: [C.timeChart([{ label: "crashes", points: pts(rk.daily, "date", "Total Count of Crashes") }], { label: "Roku crashes per day", h: 110 }),
        C.timeChart([{ label: "rebuffers per streaming hour", points: pts(rk.daily, "date", "Rebuffers per Streaming Hour") }], { label: "Rebuffers per streaming hour", h: 80 }),
        vs.length ? C.spans(vs.map((v) => ({ label: vstr(v.version), from: v.firstSeen, to: v.lastSeen })), { label: "versions seen" }) : ""],
      tables: [{ title: "Crashes by error", rows: [...groups.values()].map((g) => ({ ...g, versions: [...g.versions].join(", "), os: [...g.os].join(", ") })),
        sort: { k: "crashes", dir: -1 }, cols: [
          { k: "text", label: "Error" }, { k: "crashes", label: "Crashes", num: true },
          { k: "devices", label: "Devices", num: true }, { k: "versions", label: "Versions" },
          { k: "os", label: "Roku OS" }, { k: "first", label: "First", fmt: (v) => day(v) },
          { k: "last", label: "Last", fmt: (v) => day(v) }] }],
      note: raw.length ? null : "Roku's App Health delivery carried no crash log rows.",
      source: { href: rk.console, label: "Roku analytics" },
    };
  },
  titles(d) {
    const wt = d.health?.webTitles;
    if (!wt) return null;
    wantTitles();
    const by = new Map();
    [["topPlayed", "played"], ["topOpened", "opened"], ["topAmbient", "ambient"]].forEach(([k, f]) =>
      (wt[k] || []).forEach((r) => { const o = by.get(r.id) || { id: r.id }; o[f] = r.count; by.set(r.id, o); }));
    const rows = [...by.values()].map((o) => ({ ...o, title: Titles.name(o.id),
      ratio: o.opened ? (o.played || 0) / o.opened : null, missing: Titles.missing(o.id) }));
    const t = wt.totals || {};
    return {
      title: "What people watch on the web",
      sub: Titles.map ? (Titles.failed ? "The catalog index did not load, so ids are shown." : null) : "Loading titles from the catalog index…",
      deltas: [{ label: "Plays per open", html: t.open ? `<span class="flat">${esc(pct(t.play, t.open))} of ${int(t.open)} opens since ${esc(day(wt.since, true))}</span>` : "" },
        ...seriesDeltas(pts(wt.daily, "date", "play"))],
      charts: [C.timeChart([{ label: "opened", points: pts(wt.daily, "date", "open") },
        { label: "played", points: pts(wt.daily, "date", "play") }], { label: "Web opens and plays", h: 140 })],
      tables: [{ title: "Titles", rows, sort: { k: "played", dir: -1 }, cols: [
        { k: "title", label: "Title", href: (r) => itemURL(r.id), fmt: (v, r) => (r.missing ? `${v} — not in the catalog index` : v) },
        { k: "played", label: "Played", num: true }, { k: "opened", label: "Opened", num: true },
        { k: "ratio", label: "Play / open", num: true, fmt: (v) => (v == null ? "—" : `${Math.round(v * 100)}%`) },
        ...(rows.some((r) => r.ambient) ? [{ k: "ambient", label: "Party Play", num: true }] : []),
      ] }],
      note: `The counter keeps the top ${Math.max((wt.topPlayed || []).length, (wt.topOpened || []).length)} of each rank; ${int(wt.distinctPlayed)} films were played in all.`,
      source: { href: SITE, label: "archivewatch.org" },
    };
  },
  together(d) {
    const tg = d.health?.together;
    if (!tg) return { title: "Watch Together rooms", note: "Not collected yet." };
    const keys = ["rooms", "guests", "lives"].filter((k) => (tg.daily || []).some((r) => typeof r[k] === "number"));
    const label = { rooms: "Rooms", guests: "Guests", lives: "YouTube shows" };
    const l = tg.last28 || {}, pv = tg.prev28 || {};
    return {
      title: "Watch Together",
      deltas: keys.map((k) => ({ label: `${label[k]}, 28 days`, html: chg(l[k], pv[k], "vs prior 28 days") })),
      charts: [C.timeChart(keys.filter((k) => k !== "lives").map((k) => ({ label: label[k].toLowerCase(), points: pts(tg.daily, "date", k) })), { label: "Watch Together", h: 130 }),
        keys.includes("lives") ? C.timeChart([{ label: "YouTube shows", points: pts(tg.daily, "date", "lives") }], { label: "YouTube shows", h: 70 }) : ""],
      facts: keys.map((k) => [`${label[k]}, 28 days`, typeof l[k] === "number" ? `${int(l[k])} (prior 28 days: ${int(pv[k])})` : ""]),
      tables: [
        { title: "By day", rows: tg.daily || [], sort: { k: "date", dir: -1 }, cols: [
          { k: "date", label: "Day", fmt: (v) => day(v, true) },
          ...keys.map((k) => ({ k, label: label[k], num: true }))] },
        tg.byMethod && typeof tg.byMethod === "object" ? { title: "By method", rows: Object.entries(tg.byMethod).map(([k, v]) => ({ k, v })),
          sort: { k: "v", dir: -1 }, cols: [{ k: "k", label: "Method" }, { k: "v", label: "Count", num: true }] } : null,
      ],
      note: [keys.includes("lives") ? "YouTube shows count YouTube sign-in shows only; Twitch and own-stream-key shows are not counted." : null,
        tg.note || null].filter(Boolean).join(" "),
    };
  },
  post(d, [i]) {
    const p = (d.social?.posts || [])[Number(i)];
    if (!p) return null;
    return { title: p.title || p.id,
      facts: [["Platform", PLAT(p.platform)], ["Posted", whenMT(p.at)], ["Slot", p.slot], ["Format", p.format],
        ["Likes", p.likes], ["Reposts", p.reposts], ["Replies", p.replies], ["Views", p.views],
        ["Measured at", p.window ? String(p.window) : "not measured yet"],
        ["Still up", p.live === false ? "deleted from the platform" : p.live == null ? "not verified" : "yes", p.live === false ? "down" : ""],
        ["Film", p.id]],
      source: { href: p.url, label: `Open on ${PLAT(p.platform)}` } };
  },
  posts(d) {
    const per = d.social?.byPlatform || {}, reach = d.social?.reach || {};
    const plats = [...new Set([...Object.keys(per), ...Object.keys(reach)])].map((k) => ({
      k, ...(per[k] || {}), followers: reach[k]?.followers ?? null, error: reach[k]?.error || null }));
    return { title: "Every post",
      charts: [C.timeChart([{ label: "posts published", points: histPoints(d, "posts") }], { label: "Posts published", h: 90 })],
      tables: [
        { title: "By platform", rows: plats, sort: { k: "posts", dir: -1 }, cols: [
          { k: "k", label: "Platform", fmt: (v) => PLAT(v), href: (r) => PROFILE[r.k] },
          { k: "posts", label: "Posts", num: true }, { k: "measured", label: "Measured", num: true },
          { k: "likes", label: "Likes", num: true }, { k: "reposts", label: "Reposts", num: true },
          { k: "replies", label: "Replies", num: true }, { k: "views", label: "Views", num: true },
          { k: "followers", label: "Followers", num: true, fmt: (v, r) => (r.error ? "could not read" : num(v)) }] },
        { title: "Posts", rows: postRowsOf(d), cols: postCols, sort: { k: "at", dir: -1 } },
      ] };
  },
  ...Object.fromEntries([["queries", "Query"], ["pages", "Page"], ["countries", "Country"], ["devices", "Device"]]
    .map(([k, label]) => [`search-${k}`, (d) => {
      const sc = d.health?.searchConsole;
      if (!sc) return null;
      return { title: `Search ${k}`, sub: sc.through ? `Last 28 days to ${day(sc.through, true)}.` : null,
        deltas: seriesDeltas(pts(sc.daily, "date", "clicks")),
        charts: [C.timeChart([{ label: "clicks", points: pts(sc.daily, "date", "clicks") }], { label: "Search clicks", h: 110 })],
        tables: [{ rows: sc[k] || [], sort: { k: "clicks", dir: -1 },
          cols: SC_COLS(label, k === "countries" ? (v) => String(v).toUpperCase() : k === "pages" ? pagePath : null) }],
        source: { href: sc.url, label: "Search Console" } };
    }])),
  "search-rising"(d) {
    const sc = d.health?.searchConsole;
    if (!sc) return null;
    const q = (sc.queries || []).filter((r) => typeof r.prevClicks === "number")
      .map((r) => ({ ...r, dd: (r.clicks || 0) - r.prevClicks }));
    return { title: "Rising and falling queries",
      tables: [{ title: "Rising", rows: q.filter((r) => r.dd > 0), cols: SC_COLS("Query"), sort: { k: "d", dir: -1 } },
               { title: "Falling", rows: q.filter((r) => r.dd < 0), cols: SC_COLS("Query"), sort: { k: "d", dir: 1 } }],
      source: { href: sc.url, label: "Search Console" } };
  },
  "search-sitemaps"(d) {
    const sc = d.health?.searchConsole;
    if (!sc) return null;
    return { title: "Sitemaps", tables: [{ rows: sc.sitemaps || [], cols: [
      { k: "path", label: "Sitemap", href: (r) => r.path },
      { k: "errors", label: "Errors", num: true, sortv: (r) => Number(r.errors) || 0, cls: (r) => (Number(r.errors) > 0 ? "down" : "") },
      { k: "warnings", label: "Warnings", num: true, sortv: (r) => Number(r.warnings) || 0 },
      { k: "submitted", label: "Submitted", num: true, sortv: (r) => Number(r.submitted) || 0, fmt: (v) => int(Number(v ?? 0)) },
      { k: "indexed", label: "Indexed", num: true, sortv: (r) => Number(r.indexed) || 0, fmt: (v) => int(Number(v ?? 0)) },
      { k: "lastSubmitted", label: "Submitted on", fmt: (v) => (v ? whenMT(v) : "") },
      { k: "lastDownloaded", label: "Read by Google", fmt: (v) => (v ? whenMT(v) : "") },
      { k: "isPending", label: "Pending", fmt: (v) => (v ? "yes" : "no") }] }],
      source: { href: sc.url, label: "Search Console" } };
  },
};

/* ═══════════════════════════════════════════════════════════════════════
   PLATFORMS — one section each, reached from the Apps and Social tabs.
   Each platform declares what it HAS; one with no usage data says so in
   words rather than rendering an empty chart.
   ═══════════════════════════════════════════════════════════════════════ */
const APPLE_DEVICES = { "Apple TV": "tvOS", iPhone: "iOS", iPad: "iPadOS", Desktop: "macOS" };

function platforms(d) {
  const out = [];
  const st = (store, plat) => (d.stores || []).find(
    (x) => x.store === store && (x.platform || "").toLowerCase() === plat.toLowerCase());
  const dl = d.health?.appleDownloads;
  Object.entries(APPLE_DEVICES).forEach(([device, os]) => {
    const rowName = os === "tvOS" ? "Apple TV" : os === "macOS" ? "Mac" : "iPhone & iPad";
    const units = (dl?.byDevice || {})[device];
    if (units == null && !st("App Store", rowName)) return;
    out.push({
      key: os.toLowerCase(), name: os, family: "app", store: "App Store", installs: units,
      daily: (dl?.daily || []).map((r) => ({ date: r.date, v: (r.byDevice || {})[device] || 0 })),
      row: st("App Store", rowName), shareOf: dl?.byDevice, shareLabel: "Apple installs by device",
      // THIS device's countries and versions, never the account's.
      countries: (dl?.perDevice || {})[device]?.byCountry,
      versions: (dl?.perDevice || {})[device]?.byVersion,
    });
  });
  const pin = d.health?.playInstalls;
  out.push({
    key: "android", name: "Android", family: "app", store: "Google Play",
    installs: pin?.installs28d,
    daily: (pin?.daily || []).map((r) => ({ date: r.date, v: r.installs })),
    active: pin?.activeDevices, uninstalls: pin?.uninstalls28d,
    row: st("Google Play", "Production"), installsAsOf: pin?.asOf,
    acq: d.health?.playAcquisition, playDaily: d.health?.playDaily, playUsers: d.health?.playUsers,
    countries: pin?.byCountry, devices: pin?.byDevice, os: pin?.byOs,
    crashes: d.health?.playCrashes, liveBuild: d.health?.playLiveBuild,
  });
  [["Fire TV", "Amazon Appstore"], ["Roku", "Roku Channel Store"],
   ["webOS", "LG Content Store"], ["Tizen", "Samsung Apps TV"]].forEach(([name, store]) => {
    const row = (d.stores || []).find((x) => x.store === store);
    // Fire TV installs come from the SALES report; Roku has no API and its
    // Looker dashboards DELIVER to us. noApi is the row's claim.
    const installs = name === "Fire TV" ? d.health?.amazonInstalls
                   : name === "Roku" ? d.health?.rokuEngagement : null;
    if (!row) return;
    const rokuRows = (installs?.daily || []).filter((r) => r["Channel Installs"] != null);
    out.push({
      key: name.toLowerCase().replace(/\s/g, ""), name, family: "app", store, row,
      noApi: !row.api && !installs, delivered: name === "Roku" && !!installs,
      // NULL, never 0, when no report carrying installs has arrived (Decision 108).
      installs: installs?.total ?? (rokuRows.length ? rokuRows.reduce((a, r) => a + r["Channel Installs"], 0)
        : installs?.headline?.["Account Channel Installs"] ?? null),
      daily: name === "Fire TV"
        ? fillZero(pts(installs?.daily, "date", "installs"))
        : rokuRows.map((r) => ({ date: r.date, v: r["Channel Installs"] })),
      countries: name === "Fire TV" ? Object.fromEntries((installs?.byCountry || []).map((c) => [c.key, c.value])) : null,
      uninstalls: name === "Roku" ? installs?.headline?.["Account Channel Uninstalls"] ?? null : null,
      uninstallDaily: name === "Roku" ? pts(installs?.daily, "date", "Channel Uninstalls") : null,
      rawDaily: installs?.daily || null,
      versionsSeen: name === "Roku" ? (installs?.versionsSeen || []) : null,
      extra: name === "Roku" ? [
        { k: "Visitors and viewers", col: "Visitors", alt: "Viewers",
          cap: "A visitor opened the channel; a viewer started a film." },
        { k: "Bounce rate", col: "Bounce Rate", suffix: "%", agg: "mean", invert: true },
        { k: "Minutes streamed", col: "Total Minutes Streamed" },
      ] : null,
      vitals: row.api === "vitals" ? d.health?.amazonVitals : null,
      live: name === "Fire TV" ? d.health?.amazonLive : null,
    });
  });
  const wu = d.health?.webUsage;
  out.push({
    key: "web", name: "Web", family: "app", store: "archivewatch.org",
    row: (d.stores || []).find((x) => x.store === "Web (PWA)"),
    // Route views and VISITS are different measurements and are never summed.
    views: wu?.views28d, visits: wu?.visits28d, splitFrom: wu?.splitFrom,
    daily: (wu?.daily || []).map((r) => ({ date: r.date, v: r.views })),
    paths: wu?.byPath, catalog: d.health?.catalog, webUnread: !wu,
  });
  const per = d.social?.byPlatform || {};
  const reach = d.social?.reach || {};
  [...new Set([...Object.keys(per), ...Object.keys(reach)])].sort().forEach((k) => {
    out.push({
      key: "s-" + k, name: PLAT(k), family: "social", platform: k,
      posts: (per[k] || {}).posts, measured: (per[k] || {}).measured,
      likes: (per[k] || {}).likes, replies: (per[k] || {}).replies,
      reposts: (per[k] || {}).reposts, views: (reach[k] || {}).views,
      followers: (reach[k] || {}).followers, reachError: (reach[k] || {}).error,
      href: PROFILE[k] || null,
      items: (d.social?.posts || []).map((p, i) => ({ ...p, i })).filter((p) => p.platform === k),
    });
  });
  // Each app platform's install series is a series the drawer can open.
  out.filter((p) => p.family === "app" && p.views == null && (p.daily || []).length).forEach((p) => {
    SER.set(`plat-${p.key}`, { key: `plat-${p.key}`, label: `${p.name} installs`, unit: " installs",
      view: "reach", points: p.daily.map((r) => ({ date: r.date, v: r.v || 0 })), agg: "sum", lag: 3,
      src: p.row?.url });
  });
  return out;
}

const VIEWS = ["overview", "reach", "engagement", "health", "voice", "search", "program", "ops"];

function tabs(d, list) {
  const box = $("tabs"); if (!box) return;
  box.innerHTML = "";
  const liveCrashes = (d.health?.playCrashes || []).filter((c) => !c.stale).length;
  const group = (name, items) => {
    const g = el("div", "tg");
    g.appendChild(el("span", "tg-l", name));
    const strip = el("div", "tg-s");
    items.forEach(([key, label, count]) => {
      const b = el("button", null, label);
      b.type = "button";
      b.dataset.key = key;
      if (count != null && count !== 0) b.insertAdjacentHTML("beforeend", `<span class="n">${esc(count)}</span>`);
      b.onclick = () => { location.hash = key; };
      strip.appendChild(b);
    });
    g.appendChild(strip);
    box.appendChild(g);
  };
  group("Views", [["overview", "Overview"], ["reach", "Reach"], ["engagement", "Engagement"],
    ["health", "Health", liveCrashes || null], ["voice", "Voice", (d.reviews || []).length + (d.mentions || []).length || null],
    ["search", "Search"], ["ops", "Ops"]]);
  group("Apps", list.filter((p) => p.family === "app").map((p) => [p.key, p.name]));
  group("Social", [["program", "Program", d.social?.totalPosts ?? null],
    ...list.filter((p) => p.family === "social").map((p) => [p.key, p.name, p.posts ?? null])]);
}

function show(d, list, key) {
  CUR = key;
  const tb = $("tabs");
  if (tb) tb.querySelectorAll("button").forEach((b) =>
    b.setAttribute("aria-current", b.dataset.key === key ? "page" : "false"));
  VIEWS.forEach((v) => { const s = $("sec-" + v); if (s) s.hidden = (v !== key); });
  const pl = $("sec-platform");
  if (pl) pl.hidden = VIEWS.includes(key);
  if (!VIEWS.includes(key)) {
    const p = list.find((x) => x.key === key);
    if (p) (p.family === "social" ? socialPlatform : appPlatform)(d, p);
  }
  if (key === "engagement" || key === "web") wantTitles();
  if (window.scrollTo) window.scrollTo({ top: 0 });
}

/* ── an app platform's own section ───────────────────────────────────── */
function appPlatform(d, p) {
  const lede = $("platform-lede");
  if (lede) {
    lede.innerHTML = p.noApi
      ? `<b>${esc(p.name)}</b> ships through ${esc(p.store)}, which exposes no API at all; its state is declared by hand.`
      : p.delivered
        ? `<b>${esc(p.name)}</b> ships through ${esc(p.store)}, which has no analytics API; its dashboards are delivered to us daily.`
        : p.vitals
          ? `<b>${esc(p.name)}</b> ships through ${esc(p.store)}; installs come from its sales report.`
          : p.webUnread
            ? `<b>${esc(p.name)}</b> is live and its usage counter has not reported yet.`
            : `<b>${esc(p.name)}</b> on ${esc(p.store)}.`;
  }
  const box = $("platform-panels"); box.innerHTML = "";
  box.dataset.view = p.key;
  const rows = $("platform-rows"); rows.innerHTML = "";
  $("platform-h2").textContent = "Detail";
  const obj = (o) => Object.entries(o || {}).sort((a, b) => b[1] - a[1]);

  if (p.row) {
    const fl = p.row.inFlight;
    panel(box, {
      k: "Store", right: STATE_WORD(p.row.state || ""),
      v: p.row.version ? vstr(p.row.version) : "—",
      cap: [p.row.live && p.row.live !== p.row.version ? `live ${vstr(p.row.live)}` : null,
            p.row.build && `build ${p.row.build}`, fl && fl.version ? `${vstr(fl.version)} waiting` : null,
            p.row.since && `since ${day(p.row.since)}`].filter(Boolean).map(esc).join(" · ") || null,
      drill: `store/${storeSlug(p.row)}`,
    });
  }

  if (p.key === "web") {
    const wt = d?.health?.webTitles;
    titlesPanel(box, wt);
    const any = ["topPlayed", "topOpened", "topAmbient"].some((k) => (wt?.[k] || []).length);
    if (any) {
      $("platform-h2").textContent = "Every film, by what people did with it";
      [["topPlayed", "played"], ["topOpened", "opened"], ["topAmbient", "ambient"]].forEach(([k, what]) =>
        (wt[k] || []).forEach((t) => row(rows, {
          name: Titles.name(t.id),
          meta: what === "played" ? "started" : what === "opened" ? "detail page opened" : "muted Party Play lineup",
          num: `${int(t.count)}<small> ${what}</small>`, href: itemURL(t.id) })));
    }
  }

  const series = (p.daily || []).map((r) => ({ date: r.date, v: r.v }));
  const unit = p.views != null ? "route views" : "installs";
  if (series.length >= 2) {
    const total = series.reduce((a, b) => a + b.v, 0);
    const end = series[series.length - 1].date;
    panel(box, {
      k: unit === "route views" ? "Route views" : "Installs",
      right: `${day(series[0].date)} – ${day(end)}`, asOf: asOfIf(p.installsAsOf || end, 3),
      v: `${int(total)}<small> ${unit}</small>`,
      chart: { html: C.timeChart([{ label: unit, points: series }], { label: `${p.name} ${unit}`, h: 80, band: true }) },
      drill: unit === "installs" ? `series/plat-${p.key}` : null,
      series: unit === "installs" ? null : { label: "Route views", points: series },
    });
  } else if (!p.noApi && !p.webUnread) {
    panel(box, { k: unit === "route views" ? "Route views" : "Installs", v: "<small>no daily series yet</small>" });
  }

  if (p.acq?.daily?.length) {
    const a = p.acq;
    panel(box, {
      k: "Store listing", right: `to ${day(a.asOf)}`, asOf: asOfIf(a.asOf, 3),
      v: `${int(a.acquisitions28d)}<small> acquisitions · ${a.conversion28d != null ? `${Math.round(a.conversion28d * 100)}% of visitors` : ""}</small>`,
      chart: { html: C.timeChart([{ label: "visitors", points: pts(a.daily, "date", "visitors") },
        { label: "acquisitions", points: pts(a.daily, "date", "acquisitions") }], { label: "store listing", h: 80 })
        + C.bars(obj(a.bySource).slice(0, 5).map(([k, v]) => ({ label: k, value: v, tone: "measure" }))) },
      cap: "Counts installs through the listing only; it ran at 85% of all installs while both exports existed.",
      drill: "funnel",
    });
  }

  if (p.playDaily?.crashes?.length) {
    const cd = p.playDaily.crashes;
    panel(box, {
      k: "Crashes per day", right: `to ${day(cd[cd.length - 1].date)}`, asOf: asOfIf(p.playDaily.asOf, 3),
      v: `${cd.filter((r) => r.date > addDays(cd[cd.length - 1].date, -7)).reduce((x, b) => x + (b.crashes || 0), 0)}<small> in 7 days</small>`,
      chart: { html: C.timeChart([{ label: "crashes", points: fillZero(pts(cd, "date", "crashes")) },
        { label: "ANRs", points: fillZero(pts(cd, "date", "anrs")) }], { label: "daily crashes", h: 70 }) },
      drill: "crashes",
    });
  }
  if (p.playDaily?.ratings?.length) {
    const pr = p.playDaily.ratings.filter((r) => typeof r.total === "number");
    const last = pr[pr.length - 1];
    if (last) {
      panel(box, { k: "Google Play rating", asOf: asOfIf(last.date, 3),
        v: `${num(last.total, 2)}<small> of 5 to ${day(last.date)}</small>`,
        chart: { html: C.bullet({ value: last.total, max: 5, bands: [3, 4], target: 4.5,
          tone: last.total >= 4 ? "live" : last.total >= 3 ? "flight" : "stop", label: `${last.total} of 5` }) },
        drill: "play-rating" });
    }
  }

  if (p.active != null) {
    panel(box, {
      k: "Active devices", v: int(p.active), asOf: asOfIf(p.installsAsOf, 3),
      cap: p.uninstalls != null ? `${plural(p.uninstalls, "uninstall")} in the same window` : null,
    });
  }
  if (p.playUsers) {
    const up = pts(p.playUsers.daily, "date", "users");
    panel(box, { k: "Daily users",
      v: up.length >= 2 ? int(up[up.length - 1].v) : `<small>${up.length ? "one day reported" : "none reported"}</small>`,
      chart: up.length >= 2 ? { html: C.timeChart([{ label: "users", points: up }], { label: "daily users", h: 64 }) } : null,
      cap: up.length < 2 ? `Play returned ${up.length ? `one day (${day(up[0].date)})` : "no days"}; a chart needs two.` : null });
  }

  // Roku's field versions, read out of App Health's crash logs: a version that
  // APPEARS there is proof it shipped; absence proves nothing.
  const vs = p.versionsSeen || [];
  if (vs.length) {
    const tail = (v) => Number(String(v || "").split(".").pop());
    const declared = tail(p.row?.version);
    const newest = vs.reduce((a, v) => (tail(v.version) > tail(a.version) ? v : a), vs[0]);
    const ahead = Number.isFinite(declared) && tail(newest.version) > declared;
    panel(box, {
      k: "Versions seen in the field", right: plural(vs.length, "build"),
      v: ahead ? `${vstr(newest.version)}<small> is live</small>` : vstr(newest.version),
      chart: { html: C.spans(vs.map((v) => ({ label: vstr(v.version), from: v.firstSeen, to: v.lastSeen })), { label: "versions seen" }) },
      cap: ahead ? `Declared as ${esc(vstr(p.row?.version))}; Roku has reported ${esc(vstr(newest.version))} running on devices.` : null,
      detail: vs.slice().reverse().map((v) => drow(vstr(v.version),
        v.firstSeen === v.lastSeen ? day(v.firstSeen, true) : `${day(v.firstSeen, true)} – ${day(v.lastSeen, true)}`)),
    });
  }
  if (p.uninstallDaily) {
    const ud = p.uninstallDaily || [];
    panel(box, { k: "Uninstalls", v: p.uninstalls != null ? `${int(p.uninstalls)}<small> in Roku's window</small>` : "—",
      chart: ud.length >= 2 ? { html: C.timeChart([{ label: "installs", points: series }, { label: "uninstalls", points: ud }], { label: "installs and uninstalls", h: 64 }) } : null,
      cap: ud.length < 2 ? "No daily uninstall rows delivered yet." : null,
      series: ud.length >= 2 ? { label: "uninstalls", points: ud, invert: true } : null });
  }

  (p.extra || []).forEach((xx) => {
    const r2 = (p.rawDaily || []).filter((r) => r[xx.col] != null);
    if (r2.length < 2) return;
    const multi = [{ label: xx.col.toLowerCase(), points: pts(r2, "date", xx.col) }];
    if (xx.alt) multi.push({ label: xx.alt.toLowerCase(), points: pts(r2, "date", xx.alt) });
    panel(box, {
      k: xx.k, right: `${r2.length} days`,
      v: `${num(r2[r2.length - 1][xx.col], 1)}${xx.suffix || ""}`,
      chart: { html: C.timeChart(multi, { label: xx.k, h: 70, unit: xx.suffix || "" }) },
      cap: xx.cap || null,
      series: { label: xx.k, points: multi[0].points, agg: xx.agg || "sum", invert: xx.invert, multi: multi.length > 1 ? multi : null },
    });
  });

  const geo = obj(p.countries);
  if (geo.length) {
    panel(box, {
      k: "Where they are", right: `${geo.length} countries`,
      chart: { html: C.dotPlot(geo.slice(0, 10).map(([k, v]) => ({ label: k, value: v }))) },
      detail: geo.map(([k, v]) => drow(k, v)),
    });
  }
  [["Devices", p.devices], ["OS version", p.os], ["App version", p.versions], ["Pages", p.paths]]
    .forEach(([label, o]) => {
      const e = obj(o);
      if (!e.length) return;
      panel(box, { k: label,
        chart: { html: C.bars(e.slice(0, 7).map(([k, v]) => ({ label: k, value: v, tone: "measure" }))) },
        detail: e.map(([k, v]) => drow(k, v)) });
    });

  if (p.shareOf && Object.keys(p.shareOf).length > 1) {
    const segs = Object.entries(p.shareOf).map(([k, v], i) => ({
      label: APPLE_DEVICES[k] || k, value: v, tone: ["measure", "live", "flight", "idle"][i % 4] }));
    panel(box, { k: "Share of Apple installs", chart: { html: C.stack(segs, { label: p.shareLabel }) + C.legend(segs) } });
  }

  if (p.crashes?.length) {
    const live = p.crashes.filter((c) => !c.stale);
    panel(box, {
      k: "Crash clusters", right: `${live.length} on versionCode ${p.liveBuild ?? "?"}`,
      v: live.length ? `<span class="down">${live.length}</span><small> live</small>` : `<span class="up">none live</span>`,
      chart: { html: C.pareto(p.crashes.map((c) => ({ label: shortLoc(c), value: c.users,
        tone: c.stale ? "measure" : c.type === "CRASH" ? "stop" : "flight" })), { label: "crash clusters by users affected" }) },
      drill: "crashes",
    });
  }

  if (p.catalog?.items) {
    panel(box, {
      k: "What it serves", v: `${int(p.catalog.items)}<small> titles</small>`,
      chart: { html: C.bars([
        { label: "playable", value: p.catalog.playable, tone: "live" },
        { label: "real poster", value: p.catalog.professionalArt, tone: "measure" },
        { label: "trick play", value: p.catalog.withBif, tone: "measure" },
      ], { max: p.catalog.items }) },
      drill: "history/catalogItems",
    });
  }

  if (p.key === "web" && p.visits != null) {
    panel(box, {
      k: "Visits", right: `since ${day(p.splitFrom)}`,
      v: `${int(p.visits)}<small> in 28 days</small>`,
      cap: `A visit is one page load. Rows before ${esc(day(p.splitFrom, true))} are route views only: the beacon sent location.pathname, which on a hash router is "/" everywhere.`,
      drill: SER.get("web-visits") ? "series/web-visits" : null,
    });
  }

  if (p.live) {
    panel(box, { k: "Live build", v: p.live.liveVersionCode != null ? `versionCode ${int(p.live.liveVersionCode)}` : "—",
      cap: p.live.submissionInFlight ? "A submission is in flight." : null,
      detail: (p.live.builds || []).map((b) => drow(b.name || "build", b.versionCode)), href: p.live.console });
  }
  if (p.vitals) {
    const v = p.vitals, nSets = Object.keys(v.freshness || {}).length;
    const u = p.row || {};
    if (u.units30d != null) {
      panel(box, { k: "Units", right: `to ${day(u.unitsAsOf)}`, asOf: asOfIf(u.unitsAsOf, 3),
        v: `${u.units30d}<small> in 30 days</small>`,
        cap: `${esc(u.unitsNote || "")}; read off the console by hand.` });
    }
    rows.appendChild(el("p", "clear", nSets
      ? `Amazon's Vitals API: ${plural(nSets, "metric set")} carry data.`
      : `Authenticated to Amazon's Vitals API, which holds nothing for this app yet: `
        + `${(v.empty || []).length} metric sets answer 404.`));
  }
  if (p.noApi) {
    rows.appendChild(el("p", "clear",
      `${p.store} publishes no numbers we can read. The state above is kept by hand in ops/stores-manual.json.`));
  }
  $("platform-h2").hidden = !rows.children.length;
}

/* ── a social platform's own section ─────────────────────────────────── */
function socialPlatform(d, p) {
  const lede = $("platform-lede");
  if (lede) {
    lede.innerHTML = `<b>${esc(p.name)}</b>${p.href ? ` — <a href="${esc(p.href)}" target="_blank" rel="noopener">the profile</a>` : ""}.`;
  }
  const box = $("platform-panels"); box.innerHTML = "";
  box.dataset.view = p.key;
  const rows = $("platform-rows"); rows.innerHTML = "";
  $("platform-h2").textContent = "Every post";
  $("platform-h2").hidden = false;
  panel(box, {
    k: "Reach",
    v: p.reachError ? "<small>could not read</small>"
      : p.followers != null ? `${int(p.followers)}<small> followers</small>` : "<small>not read</small>",
    cap: p.reachError ? esc(p.reachError) : (p.views ? `${int(p.views)} channel views` : null),
    href: p.href,
  });
  const eng = (p.likes || 0) + (p.reposts || 0) + (p.replies || 0);
  panel(box, {
    k: "Posts", right: p.measured ? `${p.measured} measured` : "none measured",
    v: `${int(p.posts)}<small> still up</small>`,
    chart: { html: C.bars([
      { label: "likes", value: p.likes || 0, tone: "live" },
      { label: "reposts", value: p.reposts || 0, tone: "measure" },
      { label: "replies", value: p.replies || 0, tone: "measure" },
    ]) },
    cap: p.measured ? `${plural(eng, "engagement")} across ${p.measured} measured` : "Not measured yet; a post is sampled at 20h and 144h.",
    drill: "posts",
  });
  const days = {};
  (p.items || []).forEach((x) => { const k = dayOf(x.at); if (k) days[k] = (days[k] || 0) + 1; });
  const cal = Object.entries(days).sort().map(([date, value]) => ({ date, value }));
  if (cal.length) {
    panel(box, { k: "Cadence", right: "8 weeks",
      chart: { wide: true, html: C.calendarHeat(cal, { label: `${p.name} posting cadence` }) } });
  }
  if (p.items?.length) {
    rows.appendChild(table({ rows: p.items, cols: postCols.filter((c) => c.k !== "platform"), sort: { k: "at", dir: -1 } }));
  } else rows.appendChild(el("p", "clear", "No posts recorded yet."));
}

/* ── routing ──────────────────────────────────────────────────────────── */
const isView = (k) => VIEWS.includes(k) || LIST.some((p) => p.key === k);
function route() {
  const raw = (location.hash || "").replace(/^#/, "");
  const segs = raw.split("/").map((s) => { try { return decodeURIComponent(s); } catch { return s; } });
  const view = isView(segs[0]) ? segs[0] : "overview";
  const rest = segs.slice(1).filter(Boolean).join("/");
  if (view !== CUR || !route.done) { show(D, LIST, view); route.done = true; }
  if (rest) openDrawer(rest); else closeDrawer();
}

function renderAll(d) {
  REG.clear();
  SER = buildSeries(d);
  LIST = platforms(d);
  const when = $("when");
  if (when && d.generatedAt) {
    const hrs = (Date.now() - Date.parse(d.generatedAt)) / 36e5;
    when.textContent = `read ${ago(d.generatedAt)} · ${whenMT(d.generatedAt)}`;
    if (hrs > 36) when.className = "when asof";
  }
  board(d); stores(d); glance(d, LIST); search(d);
  saidChips(d); said(d); social(d); trend(d); sources(d);
  tabs(d, LIST);
}

/* ── go ───────────────────────────────────────────────────────────────── */
if (typeof C.interact === "function") C.interact(document);
if (document.addEventListener) {
  // Anything drawn as an HTML string (a chart, a week row, a small multiple)
  // opens its drawer through data-nav.
  document.addEventListener("click", (e) => {
    const t = e.target && e.target.closest ? e.target.closest("[data-nav]") : null;
    if (t && !(e.target.closest("a"))) nav(t.dataset.nav, t.dataset.view);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    const t = e.target && e.target.closest ? e.target.closest(".chart[data-nav] .c-time") : null;
    if (t) { const host = t.closest("[data-nav]"); nav(host.dataset.nav, host.dataset.view); }
  });
}
{
  const dlg = $("drawer");
  if (dlg && dlg.addEventListener) {
    dlg.addEventListener("close", () => {
      if ((location.hash || "").includes("/")) history.replaceState(null, "", `#${CUR}`);
    });
    dlg.addEventListener("click", (e) => { if (e.target === dlg) dlg.close(); });
    const x = $("drawer-x");
    if (x) x.onclick = () => dlg.close();
  }
}
// `cache: no-store` bypasses the BROWSER cache; the query makes each load a
// distinct CDN object, since Pages caches for 600s regardless.
fetch(`${DATA}?t=${Math.floor(Date.now() / 6e4)}`, { cache: "no-store" })
  .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
  .then((d) => {
    D = d;
    renderAll(d);
    route();
    addEventListener("hashchange", route);
  })
  .catch((e) => {
    const s = $("status");
    if (s) { s.textContent = `Could not load the readings (${e.message}).`; s.hidden = false; }
    const w = $("when"); if (w) w.textContent = "";
  });
