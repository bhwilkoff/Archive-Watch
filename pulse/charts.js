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

/* ── ratio: a number said as a proportion, with the bar under it ───────── */
function ratio(part, whole, { label = "", tone = "measure" } = {}) {
  const pct = whole ? (part / whole) * 100 : 0;
  return `<div class="c-ratio" role="img" aria-label="${esc(label)}">`
    + `<div class="c-ratio-t"><i class="${esc(tone)}" style="width:${pct.toFixed(1)}%"></i></div>`
    + `<div class="c-ratio-v">${part.toLocaleString()}<small> of ${whole.toLocaleString()}`
    + ` · ${pct.toFixed(pct < 10 ? 1 : 0)}%</small></div></div>`;
}

return { bullet, bars, spark, stack, legend, dots, ratio, cadence };
})();
