// Power Rankings 2026: reads data/rankings.json (written by build_rankings.R) and draws the two tables and the chart.

// Ten colours that stay distinct as chart lines on both themes; a team keeps its colour in the tables too.
const TEAM_COLORS = ['#4e79a7', '#f28e2b', '#e15759', '#76b7b2', '#59a14f', '#d4a017', '#b07aa1', '#ff7f9f', '#9c755f', '#7f8c9b'];

let data = null;
let week = 22;
let highlighted = null;

const $ = (id) => document.getElementById(id);
const isLight = () => document.documentElement.dataset.theme === 'light';
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Rank-based shading: t = 0 for the worst value in the column, 1 for the best.
// Light uses the in-season page's red-to-green scale; dark runs the same scale on dark backgrounds.
const mix = (a, b, t) => a.map((v, k) => Math.round(v + (b[k] - v) * t));
function shade(t) {
  const [bg0, bg1, fg0, fg1] = isLight()
    ? [[255, 200, 200], [182, 232, 196], [180, 30, 30], [20, 110, 50]]
    : [[78, 30, 36], [26, 74, 46], [255, 140, 130], [120, 222, 150]];
  return `background:rgb(${mix(bg0, bg1, t)});color:rgb(${mix(fg0, fg1, t)})`;
}
const scaler = (vals) => {
  const lo = Math.min(...vals), hi = Math.max(...vals);
  return (v) => (v - lo) / (hi - lo || 1);
};

const rec = (r, d = 0) => r.map((x) => x.toFixed(d)).join('-');
const fmtStat = (cat, v) => (['AVG', 'OPS'].includes(cat) ? v.toFixed(3) : ['ERA', 'WHIP'].includes(cat) ? v.toFixed(2) : String(v));
function luckCell(l) {
  const cls = l > 0.05 ? 'green' : l < -0.05 ? 'red' : 'grey-txt';
  return `<td><span class="${cls}">${l >= 0 ? '+' : ''}${l.toFixed(3)}</span></td>`;
}
const teamCell = (i) => `<td class="sticky c-team" title="${esc(data.teams[i])}"><span class="dot" style="background:${TEAM_COLORS[i]}"></span>${esc(data.teams[i])}</td>`;

function head(extra) {
  const n = data.cats.length;
  return `<thead>
    <tr class="group"><th class="sticky c-rank blank"></th><th class="sticky c-team blank"></th><th class="blank"></th>
      <th colspan="${n}" class="sep">Roto Categories</th><th colspan="${extra.length}" class="sep">H2H Record</th></tr>
    <tr><th class="sticky c-rank">Rank</th><th class="sticky c-team">Team</th><th>Roto</th>
      ${data.cats.map((c, k) => `<th${k === 0 ? ' class="sep"' : ''}>${c}</th>`).join('')}
      ${extra.map((c, k) => `<th${k === 0 ? ' class="sep"' : ''}>${c}</th>`).join('')}</tr>
  </thead>`;
}

function table(rows, kind) {
  const sorted = [...rows].sort((a, b) => a.rank - b.rank);
  const totalT = scaler(rows.map((r) => r.roto));
  const catT = Object.fromEntries(data.cats.map((c) => [c, scaler(rows.map((r) => r.pts[c]))]));
  const extra = kind === 'results' ? ['Total', 'Avg', 'Actual', 'Luck'] : ['70+ Wk', 'Avg', 'Actual', 'Luck'];
  const body = sorted.map((r) => {
    const t = totalT(r.roto);
    const cats = data.cats.map((c, k) => {
      const shown = kind === 'results' ? fmtStat(c, r.stats[c]) : r.pts[c].toFixed(1);
      return `<td style="${shade(catT[c](r.pts[c]))}"${k === 0 ? ' class="sep"' : ''}>${shown}</td>`;
    }).join('');
    const first = kind === 'results'
      ? `<td class="grey sep">${rec(r.total)}</td>`
      : `<td class="sep"><span class="${r.dominant >= 3 ? 'green' : r.dominant === 0 ? 'grey-txt' : ''}" style="font-weight:600">${r.dominant}/${week}</span></td>`;
    return `<tr data-team="${r.team}">
      <td class="sticky c-rank" style="${shade(t)}">${r.rank}</td>${teamCell(r.team)}
      <td style="${shade(t)}">${r.roto}</td>${cats}${first}
      <td class="grey">${rec(r.avg, 1)}</td><td class="plain">${rec(r.actual)}</td>${luckCell(r.luck)}</tr>`;
  }).join('');
  return head(extra) + `<tbody>${body}</tbody>`;
}

// ---- Chart: each team's power rank by week ----
function chart() {
  const svg = $('chart');
  const W = Math.max(320, svg.clientWidth || 900), H = W < 500 ? 300 : 340;
  const m = { l: 28, r: 14, t: 10, b: 28 };
  const n = data.weeks;
  const x = (wk) => m.l + ((wk - 1) / (n - 1)) * (W - m.l - m.r);
  const y = (rk) => m.t + ((rk - 1) / 9) * (H - m.t - m.b);
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  let s = '<g class="axis">';
  for (let rk = 1; rk <= 10; rk++) s += `<line class="gridline" x1="${m.l}" x2="${W - m.r}" y1="${y(rk)}" y2="${y(rk)}"/><text x="${m.l - 8}" y="${y(rk) + 4}" text-anchor="end">${rk}</text>`;
  const step = W < 500 ? 3 : 1;
  for (let wk = 1; wk <= n; wk++) if ((wk - 1) % step === 0 || wk === n) s += `<text x="${x(wk)}" y="${H - 8}" text-anchor="middle">${wk}</text>`;
  s += `</g><line class="now" x1="${x(week)}" x2="${x(week)}" y1="${m.t - 4}" y2="${H - m.b + 4}"/>`;
  data.teams.forEach((_, i) => {
    const pts = data.by_week.map((b) => [x(b.week), y(b.power[i].rank)]);
    const d = pts.map((p, k) => `${k ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('');
    const nowPt = pts[week - 1];
    s += `<g class="team" data-team="${i}"><path class="line" d="${d}" stroke="${TEAM_COLORS[i]}"/>
      <circle class="pt" cx="${nowPt[0]}" cy="${nowPt[1]}" r="4" fill="${TEAM_COLORS[i]}"/><path class="hit" d="${d}"/></g>`;
  });
  svg.innerHTML = s;
  svg.querySelectorAll('.team').forEach((g) => {
    const i = Number(g.dataset.team);
    g.addEventListener('mouseenter', () => highlight(i));
    g.addEventListener('mouseleave', () => highlight(null));
    g.addEventListener('click', () => highlight(highlighted === i ? null : i));
  });
  applyHighlight();
}

function legend() {
  $('legend').innerHTML = data.teams.map((t, i) => `<button data-team="${i}"><span class="dot" style="background:${TEAM_COLORS[i]}"></span>${esc(t)}</button>`).join('');
  $('legend').querySelectorAll('button').forEach((b) => {
    const i = Number(b.dataset.team);
    b.addEventListener('mouseenter', () => highlight(i));
    b.addEventListener('mouseleave', () => highlight(null));
    b.addEventListener('click', () => highlight(highlighted === i ? null : i));
  });
}

function highlight(i) { highlighted = i; applyHighlight(); }
function applyHighlight() {
  const i = highlighted;
  const svg = $('chart');
  svg.classList.toggle('dim', i !== null);
  svg.querySelectorAll('.team').forEach((g) => {
    const on = Number(g.dataset.team) === i;
    g.classList.toggle('on', on);
    if (on) svg.appendChild(g); // draw the highlighted line on top
  });
  document.querySelectorAll('#legend button').forEach((b) => b.classList.toggle('on', Number(b.dataset.team) === i));
  document.querySelectorAll('tbody tr').forEach((tr) => tr.classList.toggle('hl', Number(tr.dataset.team) === i));
  if (i === null) { $('caption').textContent = 'Hover over a line or a team to highlight it.'; return; }
  const ranks = data.by_week.map((b) => b.power[i].rank);
  $('caption').innerHTML = `<b>${esc(data.teams[i])}</b>: rank ${ranks[week - 1]} through week ${week}; best ${Math.min(...ranks)}, worst ${Math.max(...ranks)}`;
}

// ---- Page ----
function render() {
  const b = data.by_week[week - 1];
  $('results-title').textContent = `Week ${week} Results`;
  $('power-title').textContent = `Power Rankings through Week ${week}`;
  $('results').innerHTML = table(b.results, 'results');
  $('power').innerHTML = table(b.power, 'power');
  $('week').value = String(week);
  $('prev').disabled = week === 1;
  $('next').disabled = week === data.weeks;
  $('theme').textContent = isLight() ? '☀️ Light' : '🌙 Dark';
  document.querySelectorAll('tbody tr').forEach((tr) => {
    const i = Number(tr.dataset.team);
    tr.addEventListener('mouseenter', () => highlight(i));
    tr.addEventListener('mouseleave', () => highlight(null));
  });
  chart();
  try { history.replaceState(null, '', week === data.weeks ? location.pathname : `#week=${week}`); } catch (e) { /* file:// or sandboxed */ }
}

function setWeek(w) { week = Math.min(data.weeks, Math.max(1, w)); render(); }

function toggleTheme() {
  const light = !isLight();
  if (light) document.documentElement.dataset.theme = 'light';
  else delete document.documentElement.dataset.theme;
  try { localStorage.setItem('ds-theme', light ? 'light' : 'dark'); } catch (e) { /* storage blocked: theme lasts this visit */ }
  render();
}

fetch('data/rankings.json')
  .then((r) => r.json())
  .then((d) => {
    data = d;
    $('week').innerHTML = Array.from({ length: d.weeks }, (_, k) => `<option value="${k + 1}">${k + 1}</option>`).join('');
    const fromHash = Number((location.hash.match(/week=(\d+)/) || [])[1]);
    week = fromHash >= 1 && fromHash <= d.weeks ? fromHash : d.weeks;
    $('week').addEventListener('change', (e) => setWeek(Number(e.target.value)));
    $('prev').addEventListener('click', () => setWeek(week - 1));
    $('next').addEventListener('click', () => setWeek(week + 1));
    $('theme').addEventListener('click', toggleTheme);
    document.addEventListener('keydown', (e) => {
      if (e.target.tagName === 'SELECT') return;
      if (e.key === 'ArrowLeft') setWeek(week - 1);
      else if (e.key === 'ArrowRight') setWeek(week + 1);
      else if (e.key === 'T') toggleTheme();
    });
    legend();
    render();
    let resizeTimer;
    window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(chart, 150); });
  })
  .catch(() => { $('results-title').textContent = 'Could not load data/rankings.json.'; });
