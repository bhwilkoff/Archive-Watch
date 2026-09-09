/* Archive Watch — Pulse.
   One fetch, one render. No framework, no build step (Decision 001).

   The load-bearing rule here is honesty about absence: a source that could not
   answer must never render as a zero. `n()` returns an em-dash for null, the
   Sources panel names every reader that failed and why, and a tile whose reader
   is off says so instead of showing 0. A dashboard that reports a confident 0
   for a broken reader is worse than no dashboard — it reads as good news. */

const DATA = "../ops/pulse.json";
const $ = (id) => document.getElementById(id);

const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};
const n = (v) => (v === null || v === undefined || v === "") ? "—" : v;
const int = (v) => (typeof v === "number") ? v.toLocaleString() : n(v);

function ago(iso) {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const h = (Date.now() - t) / 36e5;
  if (h < 1) return `${Math.max(1, Math.round(h * 60))}m ago`;
  if (h < 48) return `${Math.round(h)}h ago`;
  const d = Math.round(h / 24);
  return d < 14 ? `${d}d ago` : new Date(t).toISOString().slice(0, 10);
}

const STATE_CLASS = (s = "") => {
  const u = s.toUpperCase();
  if (/READY_FOR_SALE|COMPLETED|LIVE|APPROVED/.test(u)) return "live";
  if (/REVIEW|PENDING|SUBMITT|PROCESS|PREPARE|DRAFT|INPROGRESS/.test(u)) return "flight";
  if (/REJECT|REMOVED|INVALID/.test(u)) return "stop";
  return "idle";
};
const STATE_WORD = (s = "") => s.replace(/_/g, " ").toLowerCase()
  .replace(/\b\w/g, (c) => c.toUpperCase());

const clip = (t, n2) => (t || "").length > n2 ? (t || "").slice(0, n2 - 1) + "…" : (t || "");

const stars = (r) => (typeof r === "number" && r > 0)
  ? "★".repeat(r) + "☆".repeat(5 - r) : "";

/* ── row: the one shape used everywhere ──────────────────────────────────── */
function row(parent, { name, meta, num, state, href, cls }) {
  const r = el("div", "row" + (cls ? " " + cls : ""));
  const left = el("div", "name");
  if (href) {
    const a = el("a", null, name); a.href = href; a.target = "_blank"; a.rel = "noopener";
    left.appendChild(a);
  } else left.textContent = name;
  r.appendChild(left);
  if (state) r.appendChild(el("span", "state " + STATE_CLASS(state), STATE_WORD(state)));
  else if (num != null) { const d = el("span", "num"); d.innerHTML = num; r.appendChild(d); }
  else r.appendChild(el("span"));
  if (meta) r.appendChild(el("div", "meta", meta));
  parent.appendChild(r);
  return r;
}

/* ── needs you ───────────────────────────────────────────────────────────── */
function needs(d) {
  const box = $("needs"); box.innerHTML = "";
  const items = [];

  (d.health?.workflows || []).filter((f) => ["BROKEN", "KILLED"].includes(f.severity))
    .forEach((f) => items.push({
      name: `${f.severity}: ${f.workflow}`,
      meta: "A run went green having produced nothing, or was killed before publishing.",
      href: "https://github.com/bhwilkoff/Archive-Watch/actions",
    }));

  const DAYS = 60;
  (d.reviews || []).filter((r) => r.rating && r.rating <= 3
      && (!r.responded || (Date.now() - Date.parse(r.date || 0)) / 864e5 < DAYS))
    .forEach((r) => items.push({
      name: `${r.rating}★ on ${r.store}: ${r.title || clip(r.body, 60)}`,
      meta: `“${r.body}” — ${r.author || "someone"}, ${ago(r.date)}`
        + (r.responded ? " · you replied" : " · NOT REPLIED"),
      href: r.url,
    }));

  (d.health?.playCrashes || []).slice(0, 5).forEach((c) => items.push({
    name: `Crash: ${c.cause || c.type}`,
    meta: `${c.location || ""}${c.users ? ` · ${c.users} user(s) affected` : ""}`,
    href: "https://play.google.com/console",
  }));

  (d.health?.issues || []).filter((i) => i.external).forEach((i) => items.push({
    name: `Issue #${i.number}: ${i.title}`,
    meta: `opened by ${i.author}, updated ${ago(i.updated)}`, href: i.url,
  }));

  (d.stores || []).filter((s) => /REJECT|REMOVED|INVALID/i.test(s.state || ""))
    .forEach((s) => items.push({
      name: `${s.store} (${s.platform}) — ${STATE_WORD(s.state)}`,
      meta: `version ${n(s.version)}`, href: s.url,
    }));

  (d.asks || []).slice(0, 6).forEach((a) => items.push({
    name: `Asked for: ${a.text}`,
    meta: `${a.who || "someone"} on ${a.where}, ${ago(a.date)}`, href: a.url,
  }));

  $("needs-n").textContent = items.length ? items.length : "";
  if (!items.length) {
    const p = el("p", "clear");
    p.innerHTML = "<b>Nothing is asking for you.</b> No urgent workflow finding, no "
      + "review under four stars in the last 60 days, no crash cluster, no issue from "
      + "outside, no request waiting to be read.";
    box.appendChild(p);
    return;
  }
  items.forEach((i) => row(box, i));
}

/* ── stores ──────────────────────────────────────────────────────────────── */
function stores(d) {
  const box = $("stores"); box.innerHTML = "";
  const rows = (d.stores || []).slice().sort((a, b) =>
    (a.store + a.platform).localeCompare(b.store + b.platform));
  $("stores-n").textContent = rows.length;
  rows.forEach((s) => {
    const bits = [];
    if (s.version) bits.push(`v${s.version}`);
    if (s.live && s.live !== s.version) bits.push(`live v${s.live}`);
    if (s.build) bits.push(`build ${s.build}`);
    const repo = d.repoVersion;
    if (repo && s.version && s.version !== repo && !s.manual) {
      bits.push(`behind the repo, which is at ${repo}`);
    }
    if (s.since) bits.push(`since ${s.since}`);
    if (s.note) bits.push(s.note);
    if (s.manual) bits.push("declared by hand — no API");
    row(box, {
      name: `${s.store} · ${s.platform}`, meta: bits.join(" · "),
      state: s.state, href: s.url,
    });
  });
}

/* ── at a glance ─────────────────────────────────────────────────────────── */
function tiles(d) {
  const box = $("tiles"); box.innerHTML = "";
  const h = d.history || [];
  const prev = h.length > 1 ? h[h.length - 2] : null;
  const cur = h[h.length - 1] || {};
  const off = (name) => d.sources?.[name] && !d.sources[name].ok;

  const add = (k, v, key, suffix = "", why = null) => {
    const t = el("div", "tile");
    t.appendChild(el("div", "k", k));
    const val = el("div", "v");
    val.innerHTML = (v === null || v === undefined)
      ? `<small>${why || "not read"}</small>`
      : `${v}${suffix ? `<small> ${suffix}</small>` : ""}`;
    t.appendChild(val);
    if (key && prev && typeof cur[key] === "number" && typeof prev[key] === "number") {
      const diff = +(cur[key] - prev[key]).toFixed(2);
      if (diff) {
        const dd = el("div", "d", `${diff > 0 ? "+" : ""}${diff} since yesterday`);
        dd.style.color = `var(--${diff > 0 ? "live" : "stop"})`;
        t.appendChild(dd);
      }
    }
    box.appendChild(t);
  };

  const ap = (d.ratings || []).find((r) => r.store === "App Store");
  const pl = (d.ratings || []).find((r) => r.store === "Google Play");
  add("App Store", ap ? ap.average : null, "appleRating",
      ap ? `from ${ap.count}` : "", "no rating yet");
  add("Google Play", pl ? pl.average : null, "playRating",
      pl ? `from ${pl.count}` : "", "no rating yet");
  add("Reviews", int((d.reviews || []).length), "reviews");
  add("Mentions", (!(d.mentions || []).length && off("mentions_bluesky"))
      ? null : int((d.mentions || []).length), "mentions", "", "readers offline");
  add("Posts", int(d.social?.totalPosts), "posts");
  const reach = d.social?.reach;
  add("Followers", reach ? int(Object.values(reach)
      .reduce((s, v) => s + (v?.followers || 0), 0)) : null, "followers", "", "not read");
  add("Catalog", int(d.health?.catalog?.items), "catalogItems", "titles");
  add("GitHub", int(d.github?.stars), "stars", "stars");
}

/* ── what people said ────────────────────────────────────────────────────── */
let saidFilter = "all";
const wantKey = (t) => (t || "").replace(/…$/, "");

function said(d) {
  const box = $("said"); box.innerHTML = "";
  const asks = (d.asks || []).map((a) => wantKey(a.text));
  const isWant = (text) => asks.some((t) => t && (text || "").includes(t));

  const items = [
    ...(d.reviews || []).map((r) => ({
      kind: "review", src: r.store, who: r.author, date: r.date, url: r.url,
      rating: r.rating, lead: r.title, text: r.body,
      tag: r.territory, extra: r.responded ? "replied" : null,
    })),
    ...(d.mentions || []).map((m) => ({
      kind: "mention", src: m.source, who: m.author, date: m.date, url: m.url,
      lead: m.title, text: m.excerpt,
      extra: [m.likes && `${m.likes} likes`, m.points && `${m.points} points`]
        .filter(Boolean).join(" · ") || null,
    })),
  ].sort((a, b) => (b.date || "").localeCompare(a.date || ""));

  const shown = items.filter((i) => saidFilter === "all"
    || (saidFilter === "reviews" && i.kind === "review")
    || (saidFilter === "mentions" && i.kind === "mention")
    || (saidFilter === "asks" && isWant(i.text)));

  $("said-n").textContent = items.length;
  if (!shown.length) {
    box.appendChild(el("p", "clear", items.length
      ? "Nothing under this filter."
      : "Nobody has said anything yet that our readers can see. "
        + "The App Store reviews land here the moment they are written."));
    return;
  }
  shown.slice(0, 80).forEach((i) => {
    const r = el("div", "row");
    const who = el("div", "who");
    who.appendChild(el("span", "src", i.src));
    if (i.rating) who.appendChild(el("span", "stars", stars(i.rating)));
    if (i.who) who.appendChild(el("span", null, i.who));
    if (i.tag) who.appendChild(el("span", null, i.tag));
    who.appendChild(el("span", null, ago(i.date)));
    if (i.extra) who.appendChild(el("span", null, i.extra));
    if (i.url) {
      const a = el("a", null, "open"); a.href = i.url; a.target = "_blank"; a.rel = "noopener";
      who.appendChild(a);
    }
    r.appendChild(who);
    const q = el("p", "quote" + (isWant(i.text) ? " want" : ""));
    if (i.lead) q.appendChild(el("span", "lead", i.lead + " "));
    q.appendChild(document.createTextNode(i.text || ""));
    r.appendChild(q);
    box.appendChild(r);
  });
}

function saidChips(d) {
  const box = $("said-chips"); box.innerHTML = "";
  const counts = {
    all: (d.reviews || []).length + (d.mentions || []).length,
    reviews: (d.reviews || []).length,
    mentions: (d.mentions || []).length,
    asks: (d.asks || []).length,
  };
  Object.entries(counts).forEach(([k, v]) => {
    const b = el("button", null, `${k[0].toUpperCase()}${k.slice(1)} ${v}`);
    b.setAttribute("aria-pressed", String(saidFilter === k));
    b.onclick = () => { saidFilter = k; saidChips(d); said(d); };
    box.appendChild(b);
  });
}

const PLAT_NAMES = { youtube: "YouTube", bluesky: "Bluesky", mastodon: "Mastodon",
  instagram: "Instagram", threads: "Threads", facebook: "Facebook" };
const PLAT = (p) => PLAT_NAMES[p] || (p ? p[0].toUpperCase() + p.slice(1) : "");

/* ── the programme ───────────────────────────────────────────────────────── */
function social(d) {
  const box = $("social"); box.innerHTML = "";
  const per = d.social?.byPlatform || {};
  const reach = d.social?.reach || {};
  const names = [...new Set([...Object.keys(per), ...Object.keys(reach)])].sort();
  $("social-n").textContent = d.social?.totalPosts ?? "";
  if (!names.length) {
    box.appendChild(el("p", "clear", "The programme has not posted yet."));
    return;
  }
  names.forEach((p) => {
    const s = per[p] || {}; const r = reach[p] || {};
    const eng = (s.likes || 0) + (s.reposts || 0) + (s.replies || 0);
    const bits = [];
    if (s.posts) bits.push(`${s.posts} post${s.posts === 1 ? "" : "s"}`);
    if (s.posts && s.measured != null) bits.push(`${s.measured} measured`);
    if (r.followers != null) bits.push(`${r.followers} follower${r.followers === 1 ? "" : "s"}`);
    if (r.views) bits.push(`${int(r.views)} views`);
    if (r.error) bits.push(`could not read: ${r.error}`);
    if (s.posts && !s.measured) bits.push("no readings yet — run social_metrics.py");
    row(box, {
      name: PLAT(p),
      meta: bits.join(" · "),
      num: s.measured ? `${eng}<small> engagements</small>` : "<small>—</small>",
    });
  });
  (d.social?.posts || []).slice(0, 8).forEach((p) => row(box, {
    name: p.title || p.id, cls: "sub",
    meta: `${PLAT(p.platform)} · ${p.format || ""} · ${ago(p.at)}`
      + (p.likes != null ? ` · ${p.likes} likes` : ""),
    href: p.url, num: "<small></small>",
  }));
}

/* ── over time ───────────────────────────────────────────────────────────── */
const SERIES = [
  ["appleRating", "App Store rating"], ["appleRatings", "App Store ratings"],
  ["reviews", "Reviews"], ["mentions", "Mentions"],
  ["followers", "Followers"], ["likes", "Post engagement"],
  ["posts", "Posts published"], ["stars", "GitHub stars"],
  ["views14d", "Repo views (14d)"], ["catalogItems", "Catalog titles"],
];

function spark(vals) {
  const w = 220, h = 46, pad = 3;
  const nums = vals.filter((v) => typeof v === "number");
  if (nums.length < 2) return null;
  const lo = Math.min(...nums), hi = Math.max(...nums);
  const span = (hi - lo) || 1;
  const step = (w - pad * 2) / Math.max(1, vals.length - 1);
  const pts = vals.map((v, i) => typeof v === "number"
    ? `${(pad + i * step).toFixed(1)},${(h - pad - ((v - lo) / span) * (h - pad * 2)).toFixed(1)}`
    : null).filter(Boolean);
  const last = pts[pts.length - 1].split(",");
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true">`
    + `<polyline class="line" points="${pts.join(" ")}"/>`
    + `<circle class="dot" cx="${last[0]}" cy="${last[1]}" r="2.5"/></svg>`;
}

function trend(d) {
  const box = $("trend"); box.innerHTML = "";
  const h = d.history || [];
  if (h.length < 2) {
    box.appendChild(el("p", "none",
      `Only ${h.length} reading so far. The shape of things appears from the second day — `
      + "this section fills itself in as the collector runs."));
    return;
  }
  const grid = el("div", "trend");
  SERIES.forEach(([key, label]) => {
    const vals = h.map((r) => r[key]);
    if (!vals.some((v) => typeof v === "number")) return;
    const cur = [...vals].reverse().find((v) => typeof v === "number");
    const first = vals.find((v) => typeof v === "number");
    const diff = +(cur - first).toFixed(2);
    const cell = el("div", "cell");
    cell.appendChild(el("div", "k", label));
    const v = el("div", "v");
    v.style.font = "var(--l6)"; v.style.fontSize = "1.35rem";
    const tone = diff > 0 ? "live" : diff < 0 ? "stop" : "text-faint";
    v.innerHTML = `${cur}<small style="color:var(--${tone})">`
      + `  ${diff > 0 ? "+" : ""}${diff} over ${h.length} days</small>`;
    cell.appendChild(v);
    const svg = spark(vals);
    if (svg) cell.insertAdjacentHTML("beforeend", svg);
    grid.appendChild(cell);
  });
  box.appendChild(grid);
}

/* ── sources ─────────────────────────────────────────────────────────────── */
function sources(d) {
  const box = $("sources"); box.innerHTML = "";
  const rows = Object.entries(d.sources || {});
  const ok = rows.filter(([, v]) => v.ok).length;
  $("src-n").textContent = `${ok}/${rows.length}`;
  rows.forEach(([k, v]) => {
    const r = el("div", "row" + (v.ok ? "" : " off"));
    r.appendChild(el("div", "name", k));
    r.appendChild(el("div", "why", (v.ok ? "" : "could not read — ") + (v.note || "")));
    box.appendChild(r);
  });
}

/* ── the one line ────────────────────────────────────────────────────────── */
function ticker(d) {
  const t = $("ticker"); t.innerHTML = "";
  const h = d.history || [];
  const cur = h[h.length - 1] || {}, prev = h.length > 1 ? h[h.length - 2] : null;
  const say = (label, key) => {
    const c = cur[key];
    if (typeof c !== "number") return;
    const s = el("span");
    s.innerHTML = `${label} <b>${c}</b>`;
    if (prev && typeof prev[key] === "number") {
      const diff = +(c - prev[key]).toFixed(2);
      s.appendChild(el("span", "delta " + (diff > 0 ? "up" : diff < 0 ? "down" : "flat"),
        ` ${diff > 0 ? "+" : ""}${diff || "—"}`));
    }
    t.appendChild(s);
  };
  say("Rating", "appleRating");
  say("Reviews", "reviews");
  say("Mentions", "mentions");
  say("Posts", "posts");
  say("Followers", "followers");
  if (!t.children.length) t.appendChild(el("span", "flat", "no readings yet"));
}

/* ── go ──────────────────────────────────────────────────────────────────── */
fetch(DATA, { cache: "no-store" })
  .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
  .then((d) => {
    $("when").textContent = d.generatedAt
      ? `read ${ago(d.generatedAt)} · ${d.generatedAt.replace("T", " ").replace("+00:00", " UTC")}`
      : "";
    ticker(d); needs(d); stores(d); tiles(d);
    saidChips(d); said(d); social(d); trend(d); sources(d);
  })
  .catch((e) => {
    $("ticker").innerHTML = `<span class="down">Could not load the readings (${e.message}).</span>`;
    document.querySelectorAll("main .rows").forEach((b) => {
      b.innerHTML = "";
      b.appendChild(el("p", "clear", "No data — ops/pulse.json did not load."));
    });
  });
