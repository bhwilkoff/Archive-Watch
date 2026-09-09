/* Archive Watch — Pulse chart kit.

   Hand-rolled inline SVG. No library, no build step (Decision 001), and none of
   the shapes Stephen Few spends Information Dashboard Design arguing against:
   no gauges, no dials, no pie charts, no 3-D, no gradients, no chart junk.

   The encodings are chosen in Cleveland & McGill's order of how accurately a
   person reads them — POSITION first, then LENGTH, then area, and colour last.
   So a comparison is a bar or a position on a common scale; colour is reserved
   for state (live / in flight / needs you), never for quantity.

   Four shapes cover everything on this page:

     bullet()  a measure against a scale, bands and a target — Few's own
               replacement for the gauge: same information, a fifth of the space
     bars()    length on a common baseline, the most accurate comparison there is
     spark()   Tufte's word-sized graphic: shape over time, next to the number
     stack()   one bar showing how a whole divides — never a pie

   Everything returns an SVG STRING with an aria-label, so a caller can drop it
   into innerHTML and a screen reader still gets the number. */

const C = (() => {
const SVGNS = 'xmlns="http://www.w3.org/2000/svg"';
const esc = (s) => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

/* ── bullet: a measure, a scale, qualitative bands, a target ──────────────
   value  the featured measure (thick bar)
   max    the top of the quantitative scale
   bands  cut points, low to high — drawn as intensities of ONE hue so the
          chart survives colour-blindness and spends no colour on quantity
   target a thin perpendicular marker; omit when there is nothing to hit    */
function bullet({ value, max, bands = [], target = null, tone = "measure",
                         invert = false, label = "" }) {
  const W = 200, H = 22, r = 2;
  const x = (v) => Math.max(0, Math.min(1, v / max)) * W;
  const cuts = [...bands, max];
  let out = `<svg ${SVGNS} viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"`
    + ` class="c-bullet" role="img" aria-label="${esc(label)}">`;
  let from = 0;
  cuts.forEach((c, i) => {
    // low index = worst; invert flips that for a metric where lower is better
    const step = invert ? cuts.length - i : i + 1;
    out += `<rect x="${x(from).toFixed(1)}" y="0" width="${(x(c) - x(from)).toFixed(1)}"`
      + ` height="${H}" class="band b${Math.min(3, step)}"/>`;
    from = c;
  });
  out += `<rect x="0" y="${H / 2 - 4}" width="${x(value).toFixed(1)}" height="8"`
    + ` rx="${r}" class="measure ${tone}"/>`;
  if (target != null) {
    out += `<line x1="${x(target).toFixed(1)}" x2="${x(target).toFixed(1)}"`
      + ` y1="2" y2="${H - 2}" class="target"/>`;
  }
  return out + "</svg>";
}

/* ── bars: length on a common baseline ───────────────────────────────────
   rows: [{ label, value, tone?, note? }] — the most accurate comparison a
   reader can make, and the reason there is no pie chart on this page.     */
function bars(rows, { max = null, unit = "", showZero = true } = {}) {
  const vals = rows.map((r) => Number(r.value) || 0);
  const top = max ?? Math.max(1, ...vals);
  return `<div class="c-bars">` + rows.map((r) => {
    const v = Number(r.value) || 0;
    const pct = (v / top) * 100;
    const zero = v === 0 && !showZero;
    return `<div class="c-bar${zero ? " nil" : ""}">`
      + `<span class="c-bar-l">${esc(r.label)}</span>`
      + `<span class="c-bar-t"><i class="${esc(r.tone || "measure")}"`
      + ` style="width:${pct.toFixed(1)}%"></i></span>`
      + `<span class="c-bar-v">${esc(r.display ?? (v + unit))}</span>`
      + (r.note ? `<span class="c-bar-n">${esc(r.note)}</span>` : "")
      + `</div>`;
  }).join("") + `</div>`;
}

/* ── spark: shape over time, word-sized, beside the number ───────────────
   An area under the line so a glance reads the level, not just the wiggle;
   a dot on the last reading so "now" is findable without a legend.        */
function spark(vals, { label = "", w = 220, h = 42 } = {}) {
  const pts = vals.map((v, i) => [i, typeof v === "number" ? v : null])
    .filter(([, v]) => v !== null);
  if (pts.length < 2) return "";
  const pad = 3;
  const nums = pts.map(([, v]) => v);
  const lo = Math.min(...nums), hi = Math.max(...nums);
  const span = (hi - lo) || 1;
  const X = (i) => pad + (i / Math.max(1, vals.length - 1)) * (w - pad * 2);
  const Y = (v) => h - pad - ((v - lo) / span) * (h - pad * 2);
  const line = pts.map(([i, v]) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const first = pts[0], last = pts[pts.length - 1];
  const area = `${X(first[0]).toFixed(1)},${h} ${line} ${X(last[0]).toFixed(1)},${h}`;
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-spark" role="img" aria-label="${esc(label)}">`
    + `<polygon class="fill" points="${area}"/>`
    + `<polyline class="line" points="${line}"/>`
    + `<circle class="dot" cx="${X(last[0]).toFixed(1)}" cy="${Y(last[1]).toFixed(1)}" r="2.6"/>`
    + `</svg>`;
}

/* ── stack: how one whole divides ────────────────────────────────────────
   segments: [{ label, value, tone }] — a single bar, never a pie: a reader
   compares lengths along one axis instead of judging angles.              */
function stack(segments, { label = "" } = {}) {
  const total = segments.reduce((s, x) => s + (Number(x.value) || 0), 0) || 1;
  return `<div class="c-stack" role="img" aria-label="${esc(label)}">`
    + segments.map((s) => {
      const pct = ((Number(s.value) || 0) / total) * 100;
      if (pct <= 0) return "";
      return `<i class="${esc(s.tone || "idle")}" style="width:${pct.toFixed(2)}%"`
        + ` title="${esc(s.label)}: ${s.value}"></i>`;
    }).join("") + `</div>`;
}

/* ── legend: the key for a stack, as text rather than a floating box ───── */
function legend(segments) {
  return `<div class="c-legend">` + segments.filter((s) => s.value)
    .map((s) => `<span><i class="${esc(s.tone || "idle")}"></i>`
      + `${esc(s.label)} <b>${esc(s.value)}</b></span>`).join("") + `</div>`;
}

/* ── dots: one mark per thing, coloured by state ─────────────────────────
   A waffle. Reads as a count AND a proportion at the same time, which is
   what "how much of the estate is live" actually asks.                    */
function dots(items, { label = "" } = {}) {
  return `<div class="c-dots" role="img" aria-label="${esc(label)}">`
    + items.map((i) => `<i class="${esc(i.tone || "idle")}" title="${esc(i.label)}"></i>`)
      .join("") + `</div>`;
}

/* ── cadence: small multiples of a timeline, one lane per platform ───────
   rows: [{ label, marks: [{ at, size, title, tone }] }] over `days` back from
   today. This is the shape a posting PROGRAMME actually needs — not how many
   posts there were, but whether they kept coming, and where the gaps are.
   Position on a common time axis, which is the most accurately read encoding
   there is; size carries engagement, which is the least, and deliberately so. */
function cadence(rows, { days = 30, label = "" } = {}) {
  const now = Date.now(), span = days * 864e5;
  const x = (t) => Math.max(0, Math.min(100, ((t - (now - span)) / span) * 100));
  const ticks = [days, Math.round(days / 2), 0]
    .map((d) => `<span style="left:${(100 - (d / days) * 100).toFixed(1)}%">`
      + `${d === 0 ? "today" : d + "d"}</span>`).join("");
  return `<div class="c-cadence" role="img" aria-label="${esc(label)}">`
    + rows.map((r) => `<div class="c-lane"><span class="c-lane-l">${esc(r.label)}</span>`
      + `<span class="c-lane-t">`
      + r.marks.map((m) => {
        const t = Date.parse(m.at);
        if (Number.isNaN(t) || t < now - span) return "";
        const s2 = Math.max(7, Math.min(15, 7 + (m.size || 0)));
        return `<i class="${esc(m.tone || "measure")}" title="${esc(m.title)}"`
          + ` style="left:${x(t).toFixed(2)}%;width:${s2}px;height:${s2}px"></i>`;
      }).join("")
      + `</span></div>`).join("")
    + `<div class="c-axis"><span class="c-lane-l"></span><span>${ticks}</span></div></div>`;
}


/* ── runChart: a series with its own control limits ──────────────────────
   The single most useful shape for "is this normal?". A line alone invites
   you to read every wiggle as news; a mean and ±2σ band says which points are
   SIGNAL. Statistical process control, applied to a product metric — the
   dashboard's job is not to show you 31 numbers, it is to tell you which of
   them you should look at.
   Points outside the band are drawn as filled marks and counted. */
function runChart(vals, { label = "", w = 260, h = 78, sigma = 2 } = {}) {
  const pts = vals.map((v, i) => [i, typeof v === "number" ? v : null])
    .filter(([, v]) => v !== null);
  if (pts.length < 4) return spark(vals, { label, w, h: Math.min(h, 46) });
  const nums = pts.map(([, v]) => v);
  const mean = nums.reduce((a, b) => a + b, 0) / nums.length;
  const sd = Math.sqrt(nums.reduce((a, b) => a + (b - mean) ** 2, 0) / nums.length) || 1;
  const hi = mean + sigma * sd, lo = Math.max(0, mean - sigma * sd);
  const top = Math.max(...nums, hi), bot = Math.min(...nums, lo);
  const span = (top - bot) || 1, pad = 4;
  const X = (i) => pad + (i / Math.max(1, vals.length - 1)) * (w - pad * 2);
  const Y = (v) => h - pad - ((v - bot) / span) * (h - pad * 2);
  const line = pts.map(([i, v]) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
  const out = pts.filter(([, v]) => v > hi || v < lo);
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-run" role="img" aria-label="${esc(label)}">`
    + `<rect class="band" x="0" y="${Y(hi).toFixed(1)}" width="${w}"`
    + ` height="${Math.max(0.5, Y(lo) - Y(hi)).toFixed(1)}"/>`
    + `<line class="mean" x1="0" x2="${w}" y1="${Y(mean).toFixed(1)}" y2="${Y(mean).toFixed(1)}"/>`
    + `<polyline class="line" points="${line}"/>`
    + out.map(([i, v]) => `<circle class="out" cx="${X(i).toFixed(1)}"`
        + ` cy="${Y(v).toFixed(1)}" r="3"><title>${v} — outside ${sigma}σ</title></circle>`).join("")
    + `</svg>`;
}

/* ── smallMultiples: the answer to "twenty series and they all matter" ───
   Twenty lines in one panel is unreadable; twenty panels in a grid is
   scannable (Tufte). A SHARED scale is what makes the comparison honest —
   per-panel scales make a tiny series look like a big one, which is the
   commonest way this chart lies.
   series: [{ label, values[], note? }] */
function smallMultiples(series, { label = "", shared = true, w = 120, h = 34 } = {}) {
  const all = series.flatMap((s) => s.values.filter((v) => typeof v === "number"));
  const gmax = Math.max(1, ...all);
  return `<div class="c-sm" role="img" aria-label="${esc(label)}">`
    + series.map((s) => {
      const nums = s.values.filter((v) => typeof v === "number");
      const max = shared ? gmax : Math.max(1, ...nums);
      const pad = 2;
      const X = (i) => pad + (i / Math.max(1, s.values.length - 1)) * (w - pad * 2);
      const Y = (v) => h - pad - (v / max) * (h - pad * 2);
      const pl = s.values.map((v, i) => typeof v === "number"
        ? `${X(i).toFixed(1)},${Y(v).toFixed(1)}` : null).filter(Boolean).join(" ");
      const last = nums.length ? nums[nums.length - 1] : 0;
      return `<div class="c-sm-cell"><span class="c-sm-l">${esc(s.label)}</span>`
        + `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">`
        + (pl ? `<polygon class="fill" points="${X(0).toFixed(1)},${h} ${pl} `
                + `${X(s.values.length - 1).toFixed(1)},${h}"/>`
                + `<polyline class="line" points="${pl}"/>` : "")
        + `</svg><span class="c-sm-v">${last.toLocaleString()}</span>`
        + (s.note ? `<span class="c-sm-n">${esc(s.note)}</span>` : "")
        + `</div>`;
    }).join("") + `</div>`;
}

/* ── slope: what moved between two periods, and which way ────────────────
   When the question is "who is up and who is down since last period", a full
   time series buries the answer in detail. A slope graph removes everything
   except the change (Tufte). Crossing lines are the finding, not the noise. */
function slope(rows, { label = "", from = "before", to = "after", h = 150 } = {}) {
  const vals = rows.flatMap((r) => [r.a, r.b]).filter((v) => typeof v === "number");
  if (!vals.length) return "";
  const max = Math.max(...vals), min = Math.min(...vals, 0);
  const span = (max - min) || 1, pad = 12;
  const Y = (v) => pad + (1 - (v - min) / span) * (h - pad * 2);
  const L = 4, R = 96;
  return `<div class="c-slope" role="img" aria-label="${esc(label)}">`
    + `<svg ${SVGNS} viewBox="0 0 100 ${h}" preserveAspectRatio="none">`
    + rows.map((r) => {
      const up = r.b > r.a, flat = r.b === r.a;
      return `<line class="${flat ? "flat" : up ? "up" : "down"}"`
        + ` x1="${L}" y1="${Y(r.a).toFixed(1)}" x2="${R}" y2="${Y(r.b).toFixed(1)}">`
        + `<title>${esc(r.label)}: ${r.a} → ${r.b}</title></line>`;
    }).join("")
    + `</svg>`
    + `<div class="c-slope-k">`
    + rows.slice(0, 8).map((r) => {
      const d = r.b - r.a;
      return `<span class="${d > 0 ? "up" : d < 0 ? "down" : "flat"}">`
        + `${esc(r.label)} <b>${r.a}\u2192${r.b}</b></span>`;
    }).join("")
    + `</div><div class="c-slope-x"><span>${esc(from)}</span><span>${esc(to)}</span></div></div>`;
}

/* ── calendarHeat: activity by day, so gaps are visible ──────────────────
   A posting programme's real question is "did they keep coming", and a total
   cannot answer it. days: [{ date: "YYYY-MM-DD", value }] */
function calendarHeat(days, { label = "", weeks = 8 } = {}) {
  if (!days.length) return "";
  const by = new Map(days.map((d) => [d.date, d.value]));
  const max = Math.max(1, ...days.map((d) => d.value || 0));
  const end = new Date(days[days.length - 1].date + "T00:00:00Z");
  const cells = [];
  for (let i = weeks * 7 - 1; i >= 0; i--) {
    const d = new Date(end); d.setUTCDate(d.getUTCDate() - i);
    const k = d.toISOString().slice(0, 10);
    const v = by.get(k) || 0;
    const lvl = v === 0 ? 0 : Math.min(4, Math.ceil((v / max) * 4));
    cells.push(`<i class="l${lvl}" title="${k}: ${v}"></i>`);
  }
  return `<div class="c-cal" role="img" aria-label="${esc(label)}">${cells.join("")}</div>`;
}

/* ── dotPlot: many categories, ranked, without a wall of bars ────────────
   Cleveland's dot plot. At a dozen categories a bar chart spends most of its
   ink on the bars' shared origin; a dot plot spends it on the position, which
   is the thing being read. */
function dotPlot(rows, { label = "", max = null } = {}) {
  const top = max ?? Math.max(1, ...rows.map((r) => Number(r.value) || 0));
  return `<div class="c-dot" role="img" aria-label="${esc(label)}">`
    + rows.map((r) => {
      const v = Number(r.value) || 0;
      return `<div class="c-dot-r"><span class="c-dot-l">${esc(r.label)}</span>`
        + `<span class="c-dot-t"><i style="left:${((v / top) * 100).toFixed(1)}%"`
        + ` class="${esc(r.tone || "measure")}"></i></span>`
        + `<span class="c-dot-v">${esc(r.display ?? v.toLocaleString())}</span></div>`;
    }).join("") + `</div>`;
}

/* ── pareto: what to fix first ───────────────────────────────────────────
   Bars descending with a cumulative line. It answers "how much of the problem
   do the top three account for", which is the only question worth asking of a
   crash list. */
function pareto(rows, { label = "" } = {}) {
  const sorted = [...rows].sort((a, b) => (b.value || 0) - (a.value || 0));
  const total = sorted.reduce((a, b) => a + (b.value || 0), 0) || 1;
  let run = 0;
  const w = 240, h = 70, pad = 3;
  const bw = (w - pad * 2) / Math.max(1, sorted.length);
  const max = Math.max(1, ...sorted.map((r) => r.value || 0));
  const bars = sorted.map((r, i) => {
    const bh = ((r.value || 0) / max) * (h - pad * 2);
    return `<rect class="${esc(r.tone || "measure")}" x="${(pad + i * bw + 1).toFixed(1)}"`
      + ` y="${(h - pad - bh).toFixed(1)}" width="${Math.max(1, bw - 2).toFixed(1)}"`
      + ` height="${bh.toFixed(1)}"><title>${esc(r.label)}: ${r.value}</title></rect>`;
  }).join("");
  const line = sorted.map((r, i) => {
    run += r.value || 0;
    return `${(pad + i * bw + bw / 2).toFixed(1)},${(h - pad - (run / total) * (h - pad * 2)).toFixed(1)}`;
  }).join(" ");
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-pareto" role="img" aria-label="${esc(label)}">${bars}`
    + `<polyline class="cum" points="${line}"/></svg>`;
}

/* ── stackedArea: composition over time ──────────────────────────────────
   series: [{ label, values[], tone }] — all the same length. Answers "is the
   growth coming from the same place it used to". */
function stackedArea(series, { label = "", w = 260, h = 70 } = {}) {
  if (!series.length) return "";
  const n = Math.max(...series.map((s) => s.values.length));
  const totals = Array.from({ length: n }, (_, i) =>
    series.reduce((a, s) => a + (Number(s.values[i]) || 0), 0));
  const max = Math.max(1, ...totals);
  const pad = 2;
  const X = (i) => pad + (i / Math.max(1, n - 1)) * (w - pad * 2);
  const Y = (v) => h - pad - (v / max) * (h - pad * 2);
  const base = new Array(n).fill(0);
  return `<svg ${SVGNS} viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"`
    + ` class="c-area" role="img" aria-label="${esc(label)}">`
    + series.map((s) => {
      const upper = base.map((b, i) => b + (Number(s.values[i]) || 0));
      const path = upper.map((v, i) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ")
        + " " + base.map((v, i) => `${X(n - 1 - i).toFixed(1)},${Y(base[n - 1 - i]).toFixed(1)}`).join(" ");
      for (let i = 0; i < n; i++) base[i] = upper[i];
      return `<polygon class="${esc(s.tone || "measure")}" points="${path}">`
        + `<title>${esc(s.label)}</title></polygon>`;
    }).join("") + `</svg>`;
}

/* ── ratio: a number said as a proportion, with the bar under it ───────── */
function ratio(part, whole, { label = "", tone = "measure" } = {}) {
  const pct = whole ? (part / whole) * 100 : 0;
  return `<div class="c-ratio" role="img" aria-label="${esc(label)}">`
    + `<div class="c-ratio-t"><i class="${esc(tone)}" style="width:${pct.toFixed(1)}%"></i></div>`
    + `<div class="c-ratio-v">${part.toLocaleString()}<small> of ${whole.toLocaleString()}`
    + ` · ${pct.toFixed(pct < 10 ? 1 : 0)}%</small></div></div>`;
}

return { bullet, bars, spark, stack, legend, dots, ratio, cadence,
         runChart, smallMultiples, slope, calendarHeat, dotPlot, pareto, stackedArea };
})();
