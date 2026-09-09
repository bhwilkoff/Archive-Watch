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
  // Negation FIRST: "NOT SUBMITTED" contains "SUBMITT", so an in-flight test
  // run before this one counted two never-sent stores as in review.
  if (/\bNOT\b|NONE|NEVER/.test(u)) return "idle";
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

  // A review that has been answered is not waiting on anyone. It stays in the
  // reading list below, where its stars are still visible.
  (d.reviews || []).filter((r) => r.rating && r.rating <= 3 && !r.responded)
    .forEach((r) => items.push({
      name: `${r.rating}\u2605 on ${r.store}: ${r.title || clip(r.body, 60)}`,
      meta: `\u201c${r.body}\u201d \u2014 ${r.author || "someone"}, ${ago(r.date)} \u00b7 not replied`,
      href: r.url,
    }));

  // Only crashes still happening on the build that is LIVE. Ten of the twelve
  // clusters were last seen on build 34 against a production build of 54;
  // listing those as things to fix today is how a list stops being read.
  const shipped = (c) => c.fixedIn && d.repoBuild && Number(d.repoBuild) >= c.fixedIn.build;
  const waiting = (d.health?.playCrashes || []).filter((c) => !c.stale && shipped(c));
  if (waiting.length) {
    const f = waiting[0].fixedIn;
    items.push({
      name: `Release ${f.version} \u2014 it carries the fix for ${waiting.length} live crash`
        + `${waiting.length === 1 ? "" : "es"}`,
      meta: `${f.what}: ${f.fix}. Users are on the build the crash is still on.`,
      href: "https://play.google.com/console",
    });
  }
  (d.health?.playCrashes || []).filter((c) => !c.stale && !shipped(c)).slice(0, 6).forEach((c) => items.push({
    name: `${c.type === "CRASH" ? "Crash" : "ANR"}: ${c.location || c.cause}`,
    meta: [c.cause, c.ours, `${c.users} user(s)`, `build ${c.lastBuild}`,
           `API ${c.api}`, ago(c.lastSeen)].filter(Boolean).join(" \u00b7 "),
    href: c.url || "https://play.google.com/console",
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
    if (s.version) bits.push(/^\d/.test(s.version) ? `v${s.version}` : s.version);
    if (s.live && s.live !== s.version) bits.push(`live v${s.live}`);
    if (s.build) bits.push(`build ${s.build}`);
    const repo = d.repoVersion;
    if (repo && s.version && s.version !== repo && !s.manual) {
      bits.push(`behind the repo, which is at ${repo}`);
    }
    if (s.since) bits.push(`since ${s.since}`);
    if (s.note) bits.push(s.note);
    if (s.manual) bits.push("declared by hand — no API");
    const r = row(box, {
      name: `${s.store} · ${s.platform}`, meta: bits.join(" · "),
      state: s.state, href: s.url,
    });
    // A colour ALSO carried at the start of the row, so the estate reads down
    // the left edge without the eye travelling to the state word each time.
    r.classList.add("lead-" + STATE_CLASS(s.state || ""));
  });
}

/* ── at a glance: every number given a SHAPE ─────────────────────────────
   Panels, not tiles. A bare number tells a reader nothing without a
   comparison, so each one carries its own: a bullet against a scale, a bar
   against its siblings, a spark against its own past, or a proportion of a
   whole. Colour is state only — length and position carry the quantity. */

/* Every panel opens. A number with no way into it is a number you have to
   take on trust, and the whole point of this page is that you should not have
   to — so `detail` carries the rows BEHIND the figure, and `href` sends you to
   the place it came from. Progressive disclosure is predictable here: a panel
   with a chevron expands in place, a link leaves, and nothing does both. */
const panel = (box, { k, right, v, chart, cap, detail, href, open }) => {
  const el2 = el("div", "panel" + (chart && chart.wide ? " wide" : ""));
  const head = el("div", "k");
  head.appendChild(el("span", null, k));
  if (right) { const rr = el("span", "r"); rr.innerHTML = right; head.appendChild(rr); }
  el2.appendChild(head);
  if (v != null) { const d = el("div", "v"); d.innerHTML = v; el2.appendChild(d); }
  if (chart && chart.html) el2.insertAdjacentHTML("beforeend", chart.html);
  if (cap) { const c = el("div", "cap"); c.innerHTML = cap; el2.appendChild(c); }

  const rows = (detail || []).filter(Boolean);
  if (rows.length || href) {
    const bar = el("div", "more");
    if (rows.length) {
      const btn = el("button", null, `${rows.length} detail${rows.length === 1 ? "" : "s"}`);
      const body = el("div", "detail");
      body.hidden = !open;
      btn.setAttribute("aria-expanded", String(!!open));
      rows.forEach((r) => {
        const line = el("div", "dline");
        const lab = el("span", "dl");
        if (r.href) {
          const a = el("a", null, r.label); a.href = r.href;
          a.target = "_blank"; a.rel = "noopener"; lab.appendChild(a);
        } else lab.textContent = r.label;
        line.appendChild(lab);
        const val = el("span", "dv"); val.innerHTML = r.value == null ? "" : String(r.value);
        line.appendChild(val);
        if (r.note) line.appendChild(el("span", "dn", r.note));
        body.appendChild(line);
      });
      btn.onclick = () => {
        body.hidden = !body.hidden;
        btn.setAttribute("aria-expanded", String(!body.hidden));
      };
      bar.appendChild(btn);
      el2.appendChild(bar);
      el2.appendChild(body);
    }
    if (href) {
      const a = el("a", "out", "open \u2197"); a.href = href;
      a.target = "_blank"; a.rel = "noopener";
      bar.appendChild(a);
    }
    if (!rows.length) el2.appendChild(bar);
  }
  box.appendChild(el2);
  return el2;
};

const deltaHTML = (cur, prev, unit = "") => {
  if (typeof cur !== "number" || typeof prev !== "number") return "";
  const diff = +(cur - prev).toFixed(2);
  const cls = diff > 0 ? "up" : diff < 0 ? "down" : "flat";
  return `<span class="${cls}">${diff > 0 ? "+" : ""}${diff || "no change"}${diff ? unit : ""}</span>`;
};

function starChart(dist, total) {
  const top = Math.max(1, ...Object.values(dist || {}));
  return `<div class="c-stars">` + [5, 4, 3, 2, 1].map((n2) => {
    const v = (dist || {})[n2] || 0;
    return `<div class="c-star"><span class="s">${n2} ★</span>`
      + `<span class="t"><i style="width:${((v / top) * 100).toFixed(1)}%"></i></span>`
      + `<span class="n">${v}</span></div>`;
  }).join("") + `</div>`;
}

const crashRow = (c) => ({
  label: `${c.type === "CRASH" ? "Crash" : "ANR"}: ${c.location || c.cause}`,
  value: `${c.users} user${c.users === 1 ? "" : "s"}`,
  note: [c.cause, c.ours, `build ${c.firstBuild}\u2013${c.lastBuild}`, `API ${c.api}`,
         ago(c.lastSeen), c.stale ? "not on the live build" : "ON THE LIVE BUILD",
        ].filter(Boolean).join(" \u00b7 "),
  href: c.url,
});

function glance(d) {
  const box = $("tiles"); box.innerHTML = ""; box.className = "panels";
  const h = d.history || [];
  const cur = h[h.length - 1] || {}, prev = h.length > 1 ? h[h.length - 2] : null;
  const off = (name) => d.sources?.[name] && !d.sources[name].ok;

  /* 1. The rating, as a bullet against the only scale it has — five stars —
        with 3.0 and 4.0 as the bands every store treats as the real cut
        points, and 4.5 as the target. */
  const ap = (d.ratings || []).find((r) => r.store === "App Store");
  if (ap && typeof ap.average === "number") {
    panel(box, {
      k: "App Store rating", right: deltaHTML(cur.appleRating, prev?.appleRating),
      v: `${ap.average}<small> of 5 · ${ap.count} rating${ap.count === 1 ? "" : "s"}</small>`,
      chart: { html: C.bullet({ value: ap.average, max: 5, bands: [3, 4], target: 4.5,
        tone: ap.average >= 4 ? "live" : ap.average >= 3 ? "flight" : "stop",
        label: `${ap.average} out of 5, target 4.5` }) },
      cap: "bands at 3 and 4 \u00b7 marker is the 4.5 target" + staleNote(d, "ratings"),
      href: ap.url,
      detail: (d.reviews || []).slice(0, 12).map((r) => ({
        label: `${stars(r.rating)} ${r.title || clip(r.body, 44)}`,
        value: `${r.author || "someone"} \u00b7 ${ago(r.date)}`,
        note: r.responded ? null : "not replied", href: r.url,
      })),
    });
  } else {
    panel(box, { k: "App Store rating", v: "<small>not read</small>" });
  }

  /* 2. Where those stars actually fall — the chart a store shows its users,
        and the one that makes a single 2★ impossible to miss. */
  const dist = (d.distribution || {})["App Store"];
  if (dist && Object.values(dist).some(Boolean)) {
    const low = (dist[1] || 0) + (dist[2] || 0) + (dist[3] || 0);
    panel(box, {
      k: "How the reviews fall", right: `${Object.values(dist).reduce((a, b) => a + b, 0)} written`,
      chart: { html: starChart(dist) },
      cap: (low ? `<b>${low}</b> under four stars — every one is in Needs you`
        : "nothing under four stars") + staleNote(d, "reviews"),
    });
  }

  /* 3. The whole estate in one bar: how much of what we ship is actually out. */
  const st = d.stores || [];
  const buckets = { live: 0, flight: 0, stop: 0, idle: 0 };
  st.forEach((x) => { buckets[STATE_CLASS(x.state || "")] += 1; });
  const segs = [
    { label: "live", value: buckets.live, tone: "live" },
    { label: "in flight", value: buckets.flight, tone: "flight" },
    { label: "needs you", value: buckets.stop, tone: "stop" },
    { label: "not submitted", value: buckets.idle, tone: "idle" },
  ];
  panel(box, {
    k: "The estate", right: `${st.length} surfaces`,
    v: `${buckets.live}<small> live of ${st.length}</small>`,
    chart: { html: C.stack(segs, { label: "store states" }) + C.legend(segs) },
    detail: st.map((x) => ({
      label: `${x.store} \u00b7 ${x.platform}`,
      value: STATE_WORD(x.state || ""),
      note: [x.version && (/^\d/.test(x.version) ? `v${x.version}` : x.version),
             x.build && `build ${x.build}`, x.note].filter(Boolean).join(" \u00b7 "),
      href: x.url,
    })),
  });

  /* 4. What we actually ship: the catalog, as coverage rather than a count. */
  const cat = d.health?.catalog || {};
  if (cat.items) {
    panel(box, {
      k: "Catalog", right: deltaHTML(cur.catalogItems, prev?.catalogItems),
      v: `${int(cat.items)}<small> titles</small>`,
      chart: { html: C.bars([
        { label: "playable", value: cat.playable || 0, tone: "live",
          display: pct(cat.playable, cat.items) },
        { label: "real poster", value: cat.professionalArt || 0, tone: "measure",
          display: pct(cat.professionalArt, cat.items) },
        { label: "trick play", value: cat.withBif || 0, tone: "measure",
          display: pct(cat.withBif, cat.items) },
      ], { max: cat.items }) },
      href: "https://archivewatch.org",
      detail: [
        { label: "titles in the index", value: int(cat.items) },
        { label: "playable", value: int(cat.playable) },
        { label: "professional poster", value: int(cat.professionalArt) },
        { label: "trick-play thumbnails", value: int(cat.withBif) },
        { label: "index schema", value: cat.schema },
        { label: "built", value: ago(cat.builtAt) || "\u2014" },
      ],
    });
  }

  /* 5. Reach, per platform, on one baseline — the number that says whether the
        programme is building anything or shouting into a new room each day. */
  const reach = d.social?.reach || {};
  const reachRows = Object.entries(reach).map(([k, v]) => ({
    label: PLAT(k), value: v?.followers || 0,
    display: v?.error ? "—" : String(v?.followers ?? 0),
    note: v?.error ? "could not read" : null,
  }));
  const totalReach = reachRows.reduce((a, b) => a + b.value, 0);
  panel(box, {
    k: "Followers", right: deltaHTML(cur.followers, prev?.followers),
    v: reachRows.length ? `${int(totalReach)}<small> across ${reachRows.length}</small>`
      : "<small>not read</small>",
    chart: reachRows.length ? { html: C.bars(reachRows) } : null,
    detail: Object.entries(reach).map(([k, v]) => ({
      label: PLAT(k),
      value: v?.error ? "\u2014" : `${v?.followers ?? 0} followers`,
      note: v?.error ? `could not read: ${v.error}`
        : [v?.posts != null ? `${v.posts} posts` : null,
           v?.views ? `${int(v.views)} views` : null].filter(Boolean).join(" \u00b7 "),
      href: PROFILE[k],
    })),
  });

  /* 6. The programme's output and its return, side by side per platform. */
  const per = d.social?.byPlatform || {};
  const postRows = Object.entries(per).map(([k, v]) => ({
    label: PLAT(k), value: v.posts || 0, tone: "measure",
  }));
  if (postRows.length) {
    const measured = Object.values(per).reduce((a, b) => a + (b.measured || 0), 0);
    panel(box, {
      k: "Posts published", right: deltaHTML(cur.posts, prev?.posts),
      v: `${int(d.social?.totalPosts)}<small> still up</small>`,
      chart: { html: C.bars(postRows) },
      cap: measured ? `<b>${measured}</b> have engagement readings`
        : "no engagement readings yet \u2014 a post is sampled at 20h",
      detail: (d.social?.posts || []).slice(0, 20).map((x) => ({
        label: `${x.live === false ? "\u2717 " : ""}${x.title || x.id}`,
        value: `${PLAT(x.platform)} \u00b7 ${ago(x.at)}`,
        note: [x.likes != null ? `${x.likes} likes` : null,
               x.live === false ? "deleted from the platform" : null,
               x.live == null ? "not verified" : null].filter(Boolean).join(" \u00b7 "),
        href: x.url,
      })),
    });
  }

  /* 7. Who is talking, by source. Zero is a real answer here and is shown as
        one, because the alternative is hiding an empty row and pretending the
        source was never asked. */
  const bySrc = {};
  (d.mentions || []).forEach((m) => { bySrc[m.source] = (bySrc[m.source] || 0) + 1; });
  const readers = ["Reddit", "Hacker News", "Lemmy", "News", "Bluesky", "Mastodon"];
  const srcRows = readers.map((r) => {
    const key = Object.keys(bySrc).find((k) => k.startsWith(r));
    const readerOff = off("mentions_" + r.toLowerCase().replace(" ", "_").replace("hacker_news", "hn"));
    return { label: r, value: bySrc[key] || 0, tone: "measure",
             display: readerOff ? "—" : String(bySrc[key] || 0),
             note: readerOff ? "reader offline" : null };
  });
  panel(box, {
    k: "Mentions", right: deltaHTML(cur.mentions, prev?.mentions),
    v: `${int((d.mentions || []).length)}<small> found</small>`,
    chart: { html: C.bars(srcRows, { max: Math.max(3, ...srcRows.map((r) => r.value)) }) },
    detail: (d.mentions || []).slice(0, 15).map((m) => ({
      label: clip(m.excerpt || m.title, 90),
      value: `${m.source}${m.author ? " \u00b7 " + m.author : ""}`,
      note: ago(m.date), href: m.url,
    })),
  });

  /* 8. Play's vitals against Google's OWN bad-behaviour thresholds — the only
        numbers here where a target exists that somebody else set. */
  const vit = d.health?.playVitals || {};
  if (typeof vit.crashRate === "number" || typeof vit.anrRate === "number") {
    let html = "";
    if (typeof vit.crashRate === "number") {
      html += `<div class="cap">Crash rate</div>` + C.bullet({
        value: vit.crashRate * 100, max: 3, bands: [1.09, 2], target: 1.09, invert: true,
        tone: vit.crashRate * 100 <= 1.09 ? "live" : "stop",
        label: `crash rate ${(vit.crashRate * 100).toFixed(2)}%` });
    }
    if (typeof vit.anrRate === "number") {
      html += `<div class="cap">ANR rate</div>` + C.bullet({
        value: vit.anrRate * 100, max: 2, bands: [0.47, 1], target: 0.47, invert: true,
        tone: vit.anrRate * 100 <= 0.47 ? "live" : "stop",
        label: `ANR rate ${(vit.anrRate * 100).toFixed(2)}%` });
    }
    panel(box, { k: "Android vitals", right: "28 days", chart: { html },
      cap: "markers are Google's own bad-behaviour thresholds",
      detail: (d.health?.playCrashes || []).map(crashRow) });
  } else {
    const why = d.health?.playVitalsNote;
    panel(box, { k: "Android vitals",
      v: why ? "<small>no rate published</small>" : "<small>not read</small>",
      chart: (d.health?.playCrashes || []).length ? { html: C.bars(
        d.health.playCrashes.slice(0, 5).map((c) => ({
          label: (c.location || c.type || "").split(".").pop().slice(0, 22),
          value: c.users || 0, tone: c.type === "CRASH" ? "stop" : "flight",
        }))) } : null,
      cap: why ? `${why} \u2014 the clusters below are what it DID report`
        : "needs the Play Developer Reporting API enabled \u2014 see docs/PULSE.md",
      detail: (d.health?.playCrashes || []).map(crashRow) });
  }

  /* 9. The fleet: one mark per finding, none at all when nothing is wrong. */
  const wf = d.health?.workflows || [];
  const marks = wf.map((f) => ({
    label: `${f.severity}: ${f.workflow}`,
    tone: ["BROKEN", "KILLED"].includes(f.severity) ? "stop" : "flight",
  }));
  panel(box, {
    k: "Workflow fleet", right: wf.length ? `${wf.length} finding${wf.length === 1 ? "" : "s"}` : "",
    v: wf.length ? `${marks.filter((m) => m.tone === "stop").length}<small> urgent</small>`
      : `<span class="up">all clear</span>`,
    chart: marks.length ? { html: C.dots(marks, { label: "workflow findings" }) } : null,
    cap: wf.length ? "red needs action now; amber is a decision"
      : "every scheduled run produced something",
    href: "https://github.com/bhwilkoff/Archive-Watch/actions",
    detail: wf.map((f) => ({ label: f.workflow, value: f.severity })),
  });

  /* 10. GitHub — a repo nobody has starred is a fact, and it is shown as one. */
  const g = d.github || {};
  if (g.url) {
    panel(box, {
      k: "The repository", right: deltaHTML(cur.stars, prev?.stars),
      v: `${int(g.stars)}<small> star${g.stars === 1 ? "" : "s"}</small>`,
      chart: { html: C.bars([
        // `value || 0` would paint a bar at zero for a reading GitHub refused —
        // the Actions token is not allowed the traffic endpoint, and "0 views"
        // is a very different claim from "we were not permitted to ask".
        { label: "views 14d", value: g.views14d || 0, tone: "measure",
          display: g.views14d == null ? "—" : int(g.views14d),
          note: g.views14d == null ? "traffic needs a token with repo admin" : null },
        { label: "uniques 14d", value: g.uniques14d || 0, tone: "measure",
          display: g.uniques14d == null ? "—" : int(g.uniques14d) },
        { label: "open issues", value: g.openIssues || 0, tone: g.openIssues ? "flight" : "measure" },
      ]) },
      cap: g.clones14d ? `${int(g.clones14d)} clones in 14 days \u2014 nearly all of them CI` : null,
      href: g.url,
      detail: (d.health?.issues || []).map((i) => ({
        label: `#${i.number} ${i.title}`, value: i.external ? "from outside" : "ours",
        note: `${i.author} \u00b7 ${ago(i.updated)}`, href: i.url,
      })),
    });
  }
  /* 10b. Downloads — the only number here that counts PEOPLE, so it leads
        with its own shape rather than sitting in a list. */
  const dl = d.health?.appleDownloads;
  if (dl?.daily?.length) {
    panel(box, {
      k: "Downloads", right: `${dl.daily.length} days`,
      v: `${int(dl.total14d)}<small> first-time installs</small>`,
      chart: { html: C.spark(dl.daily.map((x) => x.units),
        { label: `${dl.total14d} downloads over ${dl.daily.length} days` }) },
      cap: "updates and redownloads are excluded \u2014 these are new people",
      href: "https://appstoreconnect.apple.com/analytics",
      detail: [...dl.daily].reverse().slice(0, 14)
        .map((x) => ({ label: x.date, value: `${x.units} install${x.units === 1 ? "" : "s"}` })),
    });
  } else if (off("apple_downloads")) {
    panel(box, { k: "Downloads", v: "<small>not read</small>",
      cap: "needs <b>ASC_VENDOR_NUMBER</b> — an identifier, not a secret; "
        + "App Store Connect → Payments and Financial Reports" });
  }

  /* 10c. Apple's own field metrics. An empty answer here is normal for a young
        app — Apple aggregates across opted-in devices and needs a population. */
  const perf = d.health?.applePerf;
  if (perf) {
    const regs = perf.regressions || [];
    panel(box, {
      k: "Apple field metrics", right: perf.metrics?.length ? `${perf.metrics.length} metrics` : "",
      v: regs.length ? `<span class="down">${regs.length}</span><small> regression${regs.length === 1 ? "" : "s"}</small>`
        : (perf.metrics?.length ? `<span class="up">no regressions</span>`
                                : "<small>not enough devices yet</small>"),
      chart: perf.metrics?.length ? { html: C.bars(perf.metrics.slice(0, 5).map((m) => ({
        label: (m.metric || "").replace(/([A-Z])/g, " $1").trim().toLowerCase(),
        value: Number(m.value) || 0, tone: "measure",
        display: `${m.value}${m.unit ? " " + m.unit : ""}`,
      }))) } : null,
      cap: regs.length ? regs.map((r) => `<b>${r}</b>`).join(" · ")
        : "launch time, hang rate, memory and disk, aggregated by Apple across "
          + "devices that opted in to share diagnostics",
    });
  }

  /* 10d. Android installs — the number Play gives that Apple does not. */
  const pin = d.health?.playInstalls;
  if (pin?.daily?.length) {
    const byC = pin.byCountry || {};
    panel(box, {
      k: "Android installs", right: `${pin.daily.length} days${staleNote(d, "playInstalls") ? " \u00b7 older reading" : ""}`,
      v: `${int(pin.installs28d)}<small> installs \u00b7 ${int(pin.activeDevices)} active devices</small>`,
      chart: { html: C.spark(pin.daily.map((x) => x.installs),
        { label: `${pin.installs28d} installs over ${pin.daily.length} days` })
        + C.bars(Object.entries(byC).slice(0, 6)
            .map(([k, v]) => ({ label: k, value: v, tone: "measure" }))) },
      cap: `${pin.uninstalls28d} uninstall(s) in the same window \u00b7 top countries by install`,
      href: "https://play.google.com/console",
      detail: [
        ...Object.entries(pin.byDevice || {}).slice(0, 6)
          .map(([k, v]) => ({ label: `device \u00b7 ${k}`, value: v })),
        ...Object.entries(pin.byOs || {}).slice(0, 6)
          .map(([k, v]) => ({ label: `Android API ${k}`, value: v })),
        ...Object.entries(pin.byLanguage || {}).slice(0, 5)
          .map(([k, v]) => ({ label: `language \u00b7 ${k}`, value: v })),
      ],
    });
  }

  /* 11. Praise against requests — the owner's question in one bar. */
  const loves = (d.loves || []).length, wants = (d.asks || []).length;
  if (loves || wants || (d.reviews || []).length) {
    const segs2 = [
      { label: "praise", value: loves, tone: "live" },
      { label: "requests", value: wants, tone: "flight" },
    ];
    panel(box, {
      k: "Enjoying vs asking", right: `${loves + wants} sentence${loves + wants === 1 ? "" : "s"}`,
      v: wants ? `${wants}<small> asked for something</small>`
        : `<span class="up">${loves}</span><small> said something kind</small>`,
      chart: { html: C.stack(segs2, { label: "praise against requests" }) + C.legend(segs2) },
      cap: "pulled sentence by sentence out of reviews and mentions",
      detail: [...(d.asks || []).map((a) => ({
                label: a.text, value: "asked for",
                note: `${a.who || "someone"} \u00b7 ${a.where} \u00b7 ${ago(a.date)}`, href: a.url })),
              ...(d.loves || []).map((l) => ({
                label: l.text, value: "praise",
                note: `${l.who || "someone"} \u00b7 ${l.where} \u00b7 ${ago(l.date)}`, href: l.url }))],
    });
  }
}

const pct = (part, whole) => whole ? `${Math.round((part / whole) * 100)}%` : "—";

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

/* ── the programme ───────────────────────────────────────────────────────
   The question a posting programme has to answer is not "how many" — that is
   already a panel above — but "did they keep coming, and where are the gaps".
   So the lead shape is a cadence chart: one lane per platform, every post a
   mark on a shared 30-day axis, sized by the engagement it earned. */
function social(d) {
  const box = $("social"); box.innerHTML = "";
  const per = d.social?.byPlatform || {};
  const reach = d.social?.reach || {};
  const posts = d.social?.posts || [];
  const names = [...new Set([...Object.keys(per), ...Object.keys(reach)])].sort();
  $("social-n").textContent = d.social?.totalPosts ?? "";
  if (!names.length) {
    box.appendChild(el("p", "clear", "The programme has not posted yet."));
    return;
  }

  const lanes = names.map((p) => ({
    label: PLAT(p),
    marks: posts.filter((x) => x.platform === p).map((x) => ({
      at: x.at, size: Math.min(8, (x.likes || 0) + (x.reposts || 0) + (x.replies || 0)),
      title: `${x.title || x.id} · ${ago(x.at)}`
        + (x.likes != null ? ` · ${x.likes} likes` : " · not measured"),
      tone: x.likes ? "live" : "measure",
    })),
  }));
  const grid = el("div", "panels");
  panel(grid, {
    k: "Cadence", right: "last 30 days",
    chart: { wide: true, html: C.cadence(lanes, { days: 30, label: "posts per platform" }) },
    cap: "each mark is a post, sized by the engagement it earned · "
      + "a <b>filled</b> mark has a reading, an orange one is not measured yet",
  });
  box.appendChild(grid);

  /* Engagement per platform, on one baseline, beneath the cadence. */
  const engRows = names.map((p) => {
    const s2 = per[p] || {}, r = reach[p] || {};
    const eng = (s2.likes || 0) + (s2.reposts || 0) + (s2.replies || 0);
    return {
      label: PLAT(p), value: eng, tone: eng ? "live" : "measure",
      display: s2.measured ? String(eng) : "—",
      note: [s2.posts ? `${s2.posts} post${s2.posts === 1 ? "" : "s"}` : null,
             r.followers != null ? `${r.followers} follower${r.followers === 1 ? "" : "s"}` : null,
             r.views ? `${int(r.views)} views` : null,
             s2.posts && !s2.measured ? "no reading yet — a post is sampled at 20h" : null,
             r.error ? `could not read: ${r.error}` : null].filter(Boolean).join(" · "),
    };
  });
  const g2 = el("div", "panels");
  panel(g2, {
    k: "What it earned",
    right: [d.social?.deleted ? `${d.social.deleted} deleted` : null,
            d.social?.unverified ? `${d.social.unverified} unverified` : null,
            `${d.social?.measured || 0} measured`].filter(Boolean).join(" \u00b7 "),
    chart: { wide: true, html: C.bars(engRows) },
  });
  box.appendChild(g2);

  const list = el("div", "rows");
  posts.slice(0, 8).forEach((p) => row(list, {
    name: p.title || p.id, cls: "sub",
    meta: `${PLAT(p.platform)} · ${p.format || ""} · ${ago(p.at)}`
      + (p.likes != null ? ` · ${p.likes} likes` : ""),
    href: p.url, num: "<small></small>",
  }));
  box.appendChild(list);
}

/* ── over time: one reading a day, each series in its own panel ─────────
   Tufte's sparkline — the shape sits next to the number, at the size of a
   word, so a reader gets level and direction in one glance without a
   legend, an axis, or a chart to open. */
const SERIES = [
  ["appleRating", "App Store rating"], ["appleRatings", "Ratings"],
  ["reviews", "Reviews"], ["mentions", "Mentions"],
  ["followers", "Followers"], ["likes", "Post engagement"],
  ["posts", "Posts published"], ["stars", "GitHub stars"],
  ["views14d", "Repo views (14d)"], ["catalogItems", "Catalog titles"],
];

function trend(d) {
  const box = $("trend"); box.innerHTML = "";
  const h = d.history || [];
  if (h.length < 2) {
    box.appendChild(el("p", "none",
      `Only ${h.length} reading so far. Every series below appears from the second `
      + "day — the collector runs at 07:17 each morning and this fills itself in."));
    return;
  }
  const grid = el("div", "panels");
  const days = h.length;
  SERIES.forEach(([key, label]) => {
    const vals = h.map((r) => r[key]);
    if (!vals.some((v) => typeof v === "number")) return;
    const cur = [...vals].reverse().find((v) => typeof v === "number");
    const first = vals.find((v) => typeof v === "number");
    const diff = +(cur - first).toFixed(2);
    const tone = diff > 0 ? "up" : diff < 0 ? "down" : "flat";
    panel(grid, {
      k: label,
      right: `<span class="${tone}">${diff > 0 ? "+" : ""}${diff || "level"}</span>`,
      v: `${int(cur)}`,
      chart: { html: C.spark(vals, { label: `${label} over ${days} days` }) },
      cap: `${days} day${days === 1 ? "" : "s"} of readings`,
    });
  });
  box.appendChild(grid);
}

/* ── sources ─────────────────────────────────────────────────────────────── */
function staleNote(d, key) {
  const at = (d.stale || {})[key];
  return at ? ` · standing on the reading from ${ago(at)} — its reader is offline` : "";
}

function sources(d) {
  const box = $("sources"); box.innerHTML = "";
  const rows = Object.entries(d.sources || {});
  const ok = rows.filter(([, v]) => v.ok).length;
  $("src-n").textContent = `${ok}/${rows.length}`;
  const grid = el("div", "panels");
  const marks = rows.map(([k, v]) => ({ label: k + (v.ok ? " — ok" : " — offline"),
                                        tone: v.ok ? "live" : "flight" }));
  panel(grid, {
    k: "Readers", right: `${ok} of ${rows.length}`,
    v: `${ok}<small> answered</small>`,
    chart: { html: C.dots(marks, { label: "one mark per reader" }) },
    cap: ok === rows.length ? "every reader answered"
      : `<b>${rows.length - ok}</b> could not read — the reasons are listed below, `
        + "and any panel standing on an older reading says so",
  });
  box.appendChild(grid);
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
// `cache: no-store` bypasses the BROWSER cache; the Pages CDN caches for 600s
// regardless, and a dashboard that shows a reading up to ten minutes stale on
// the morning it is read is a dashboard that gets doubted. The query makes each
// load a distinct CDN object.
fetch(`${DATA}?t=${Math.floor(Date.now() / 6e4)}`, { cache: "no-store" })
  .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json(); })
  .then((d) => {
    $("when").textContent = d.generatedAt
      ? `read ${ago(d.generatedAt)} · ${d.generatedAt.replace("T", " ").replace("+00:00", " UTC")}`
      : "";
    ticker(d); needs(d); stores(d); glance(d);
    saidChips(d); said(d); social(d); trend(d); sources(d);
  })
  .catch((e) => {
    $("ticker").innerHTML = `<span class="down">Could not load the readings (${e.message}).</span>`;
    document.querySelectorAll("main .rows").forEach((b) => {
      b.innerHTML = "";
      b.appendChild(el("p", "clear", "No data — ops/pulse.json did not load."));
    });
  });
