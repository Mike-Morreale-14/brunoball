// Draft Scout 2026. Plain JavaScript, no build step.
// Reads data/hitters.json, data/sp.json, data/relievers.json and data/weights.json (written by
// data-pipeline/04_scores.R) and computes every score in the browser, so the sliders work.
'use strict';

const REPO_URL = 'https://github.com/Mike-Morreale-14/brunoball';
const TEAMS_IN_LEAGUE = 10; // a pick number becomes round.pick with this many teams
const STATS_YEAR = 2025;
const SLIDER_MAX = 50;
const STORE_KEY = 'ds-draft-2026'; // picks and Score weights, saved in the viewer's browser

// ---- Fixed lookups ---------------------------------------------------------------------

const GROUPS = {
  hitter: { file: 'hitters.json', type: 'h', label: 'Hitter' },
  sp: { file: 'sp.json', type: 'sp', label: 'Starting pitcher' },
  relievers: { file: 'relievers.json', type: 'rp', label: 'Reliever' },
};

const ARCH = {
  hitter: [
    { key: 'pwr', label: 'Power', short: 'PWR', color: '#e0734a' },
    { key: 'spd', label: 'Speed', short: 'SPD', color: '#3a9cc5' },
    { key: 'avg', label: 'AVG', short: 'AVG', color: '#6aaa7a' },
  ],
  sp: [
    { key: 'anc', label: 'Anchor', short: 'ANC', color: '#3a9cc5' },
    { key: 'karm', label: 'K Arm', short: 'K', color: '#e0734a' },
    { key: 'vol', label: 'Volatility', short: 'VOL', inverse: true },
  ],
};

// What each weights.json input means, for the score dictionary.
const INPUTS = {
  barrel: ['Barrel %', '2025 Savant: share of batted balls hit at an ideal exit velocity and launch angle.'],
  ev: ['Exit velocity', '2025 Savant average exit velocity.'],
  proj_iso: ['Projected ISO', 'Marcel 2026 isolated power (SLG minus AVG).'],
  act_iso: ['2025 ISO', '2025 isolated power (SLG minus AVG).'],
  xiso: ['Expected ISO', '2025 Savant expected SLG minus expected AVG.'],
  fb: ['Fly-ball %', '2025 Savant share of batted balls that were fly balls.'],
  proj_hr: ['Projected HR', 'Marcel 2026 home runs.'],
  act_hr: ['2025 HR', '2025 home runs.'],
  act_hr_pa: ['2025 HR per PA', '2025 home runs per plate appearance.'],
  sprint: ['Sprint speed', '2025 Savant sprint speed (feet per second).'],
  proj_sb: ['Projected SB', 'Marcel 2026 stolen bases.'],
  act_sb: ['2025 SB', '2025 stolen bases.'],
  contact: ['Contact %', '100 minus 2025 Savant whiff % (contact per swing).'],
  xavg: ['xBA', '2025 Savant expected batting average.'],
  proj_avg: ['Projected AVG', 'Marcel 2026 batting average.'],
  proj_low_k: ['Projected K% (lower is better)', 'Marcel 2026 strikeout rate.'],
  act_low_k: ['2025 K% (lower is better)', '2025 strikeouts per plate appearance.'],
  ocontact: ['Chase contact %', '2025 Savant contact rate on swings at pitches outside the zone.'],
  proj_babip: ['Projected BABIP', 'Marcel 2026 batting average on balls in play.'],
  act_babip: ['2025 BABIP', '2025 batting average on balls in play.'],
  act_avg: ['2025 AVG', '2025 batting average.'],
  proj_ip: ['Projected IP', 'Marcel 2026 innings: workload.'],
  proj_qs: ['Projected QS', 'Quality starts: an extension to Marcel (QS per start times projected starts).'],
  proj_low_era: ['Projected ERA (lower is better)', 'Marcel 2026 ERA.'],
  proj_low_whip: ['Projected WHIP (lower is better)', 'Marcel 2026 WHIP.'],
  low_xera: ['xERA (lower is better)', '2025 Savant expected ERA.'],
  low_hard: ['Hard-hit % allowed (lower is better)', '2025 Savant share of batted balls at 95+ mph.'],
  gb: ['Ground-ball %', '2025 Savant share of batted balls on the ground.'],
  act_qs_gs: ['2025 QS per start', 'Starts with 18+ outs and 3 or fewer earned runs, per start.'],
  act_low_era: ['2025 ERA (lower is better)', '2025 earned run average.'],
  act_low_whip: ['2025 WHIP (lower is better)', '2025 walks plus hits per inning.'],
  fbv: ['Fastball velocity', '2025 Savant average fastball speed.'],
  act_kpct: ['2025 K%', '2025 strikeouts per batter faced.'],
  proj_k: ['Projected K', 'Marcel 2026 strikeouts.'],
  proj_k9: ['Projected K/9', 'Marcel 2026 strikeouts per nine innings.'],
  whiff: ['Whiff %', '2025 Savant misses per swing.'],
  low_zcon: ['Zone contact % allowed (lower is better)', '2025 Savant contact on swings at pitches in the zone.'],
  act_k9: ['2025 K/9', '2025 strikeouts per nine innings.'],
  hrfb: ['HR per fly ball', '2025 Savant home runs per fly ball allowed.'],
  hard: ['Hard-hit % allowed', '2025 Savant share of batted balls at 95+ mph.'],
  barrel_ag: ['Barrel % allowed', '2025 Savant barrels per batted ball allowed.'],
};

// Glossary ranges are computed from the draft pool itself: [field, label, unit, lower is better].
const GLOSSARY = {
  hitter: [
    ['avg_ev', 'Exit velocity', ' mph'], ['max_ev', 'Max exit velocity', ' mph'],
    ['barrel_pct', 'Barrel %', '%'], ['hard_hit_pct', 'Hard-hit %', '%'], ['xba', 'xBA', ''],
    ['xslg', 'xSLG', ''], ['sprint_speed', 'Sprint speed', ' ft/s'], ['k_pct_2025', 'K%', '%', true],
    ['chase_contact_pct', 'Chase contact %', '%'], ['whiff_pct', 'Whiff %', '%', true], ['fb_pct', 'Fly-ball %', '%'],
  ],
  sp: [
    ['fb_velo', 'Fastball velocity', ' mph'], ['whiff_pct', 'Whiff %', '%'], ['k_pct_2025', 'K%', '%'],
    ['bb_pct_2025', 'BB%', '%', true], ['xera', 'xERA', '', true], ['hard_hit_pct', 'Hard-hit % allowed', '%', true],
    ['gb_pct', 'Ground-ball %', '%'], ['zone_contact_pct', 'Zone contact % allowed', '%', true],
    ['hr_fb_pct', 'HR per fly ball', '%', true], ['barrel_pct', 'Barrel % allowed', '%', true],
  ],
};

const POS_LIST = ['C', '1B', '2B', '3B', 'SS', 'OF', 'DH', 'SP', 'RP'];
const POS_COL = { C: '#c4956a', '1B': '#6aaa7a', '2B': '#6a8acc', '3B': '#cc5a5a', SS: '#b070cc', OF: '#e0a040', DH: '#8a8a8a', SP: '#6a8acc', RP: '#5a9a6a' };

// FantasyPros team codes; dark team colours lightened for the dark background.
const TEAM_COL = {
  ARI: '#A71930', ATL: '#CE1141', ATH: '#3A8A5A', BAL: '#DF4601', BOS: '#BD3039', CHC: '#4A6AB6', CWS: '#7A7870',
  CIN: '#C6011F', CLE: '#3A7A9A', COL: '#6A6AAA', DET: '#3A6A9A', HOU: '#3A6A9A', KC: '#4A80B7', LAA: '#BA0021',
  LAD: '#4A8ACC', MIA: '#00A3E0', MIL: '#C9A227', MIN: '#3A6A9A', NYM: '#4A70B2', NYY: '#4A70B7', PHI: '#E81828',
  PIT: '#C99A20', SD: '#8A7A6A', SF: '#FD5A1E', SEA: '#3A6AA0', STL: '#C41E3A', TB: '#3A6A9A', TEX: '#4A70B0',
  TOR: '#4A8ABE', WSH: '#AB0003',
};
const DIVISIONS = {
  'AL East': ['BAL', 'BOS', 'NYY', 'TB', 'TOR'], 'AL Central': ['CWS', 'CLE', 'DET', 'KC', 'MIN'],
  'AL West': ['ATH', 'HOU', 'LAA', 'SEA', 'TEX'], 'NL East': ['ATL', 'MIA', 'NYM', 'PHI', 'WSH'],
  'NL Central': ['CHC', 'CIN', 'MIL', 'PIT', 'STL'], 'NL West': ['ARI', 'COL', 'LAD', 'SD', 'SF'],
};

const SCORE_FILTERS = {
  hitter: [['pwr', 'Power', '#e0734a'], ['spd', 'Speed', '#3a9cc5'], ['avg', 'AVG', '#6aaa7a'], ['rel', 'REL', '#b0a488']],
  sp: [['anc', 'Anchor', '#3a9cc5'], ['karm', 'K Arm', '#e0734a'], ['vol', 'Volatility', '#6aaa7a']],
};

const ROSTER = {
  batters: ['C', '1B', '2B', '3B', 'SS', 'OF', 'OF', 'OF', 'UTIL', 'UTIL'],
  starters: ['SP', 'SP', 'SP', 'SP', 'UP'],
  relievers: ['RP', 'RP', 'RP'],
  bench: 5,
};

// ---- State -------------------------------------------------------------------------------

const state = {
  players: [], byUid: new Map(), weights: null, mainW: null, ranges: {},
  selected: null, compare: null, search: '', pos: new Set(), teams: new Set(), filters: {},
  picks: [], hideGone: false, open: { filters: false, team: false, taken: false },
  showHist: false, showDict: false, mobileOpen: false,
};

// ---- Small helpers -----------------------------------------------------------------------

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const isNum = (v) => typeof v === 'number' && !Number.isNaN(v);
const fA = (v) => (isNum(v) ? v.toFixed(3).replace(/^0\./, '.') : '–');
const fD = (v, d = 0) => (isNum(v) ? v.toFixed(d) : '–');
const fI = (v) => (isNum(v) ? String(Math.round(v)) : '–');
const pickLabel = (n) => `${Math.ceil(n / TEAMS_IN_LEAGUE)}.${((n - 1) % TEAMS_IN_LEAGUE) + 1}`;

function tierColor(s, inverse = false) {
  if (!isNum(s)) return 'var(--text-muted)';
  const t = s < 34 ? 0 : s < 67 ? 1 : 2;
  return ['var(--tier-red)', 'var(--tier-yel)', 'var(--tier-grn)'][inverse ? 2 - t : t];
}
const gapColor = (d) => (d > 5 ? '#6aaa7a' : d < -5 ? '#c05848' : 'var(--text-muted)');

function headshot(id) {
  return `https://img.mlbstatic.com/mlb-photos/image/upload/d_people:generic:headshot:67:current.png/w_213,q_auto:best/v1/people/${id}/headshot/67/current`;
}

// Weighted mean of the percentiles a player has; missing inputs are skipped.
function cs(p, w) {
  let total = 0;
  let sum = 0;
  for (const [k, wt] of Object.entries(w)) {
    const v = p['p_' + k];
    if (isNum(v) && wt > 0) { total += v * wt; sum += wt; }
  }
  return sum > 0 ? Math.round(total / sum) : null;
}

// Archetypes with 2025 Results (raw) and 2025 Skills (und) weights, so they have a gap.
const hasGap = (group, key) => Boolean(state.weights[group][key].raw && state.weights[group][key].und);

function scoresFor(p) {
  if (p.unscored_reason || !ARCH[p.group]) return null;
  const out = {};
  for (const a of ARCH[p.group]) {
    const sets = state.weights[p.group][a.key];
    const results = sets.raw ? cs(p, sets.raw) : null;
    const skills = sets.und ? cs(p, sets.und) : null;
    out[a.key] = {
      main: cs(p, state.mainW[p.group][a.key]), results, skills,
      gap: results != null && skills != null ? skills - results : null,
    };
  }
  return out;
}

const filterPos = (p) => (p.group === 'sp' ? 'SP' : p.group === 'relievers' ? 'RP' : ['CF', 'LF', 'RF'].includes(p.position) ? 'OF' : p.position);
const season = (p, yr) => (p.history || []).find((y) => y.season === yr);

function quantiles(vals) {
  const v = vals.filter(isNum).sort((a, b) => a - b);
  if (v.length < 5) return null;
  return [0.1, 0.25, 0.5, 0.75, 0.9].map((q) => v[Math.round(q * (v.length - 1))]);
}

// ---- Loading -----------------------------------------------------------------------------

async function load() {
  const get = (f) => fetch('data/' + f).then((r) => {
    if (!r.ok) throw new Error(`${f}: HTTP ${r.status}`);
    return r.json();
  });
  const [weights, ...groups] = await Promise.all([get('weights.json'), ...Object.values(GROUPS).map((g) => get(g.file))]);
  state.weights = weights;
  state.mainW = Object.fromEntries(Object.keys(ARCH).map((g) => [g, Object.fromEntries(
    Object.entries(weights[g]).map(([a, sets]) => [a, { ...sets.main }]),
  )]));
  Object.keys(GROUPS).forEach((g, i) => groups[i].forEach((p) => {
    p.group = g;
    p.uid = `${g}:${p.player_id ?? p.name}`;
    state.players.push(p);
    state.byUid.set(p.uid, p);
  }));
  state.players.sort((a, b) => a.adp - b.adp);
  // Rank and draft round come from ADP order, so filtering never renumbers them.
  state.players.forEach((p, i) => { p.rank = i + 1; p.round = Math.ceil(p.rank / TEAMS_IN_LEAGUE); });
  for (const g of Object.keys(GLOSSARY)) {
    const pool = state.players.filter((p) => p.group === g && !p.unscored_reason);
    state.ranges[g] = Object.fromEntries(GLOSSARY[g].map(([f]) => [f, quantiles(pool.map((p) => p[f]))]));
  }
}

// ---- Saved draft ---------------------------------------------------------------------------

// Storage can be blocked (private windows, strict settings); the tool then works for this visit only.
function saveDraft() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({ picks: state.picks, mainW: state.mainW }));
  } catch (e) { /* not saved */ }
}

// Only picks of players still in the data, and weights for inputs that still exist, come back.
function restoreDraft() {
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(STORE_KEY)); } catch (e) { return; }
  if (!saved) return;
  const seen = new Set();
  state.picks = (Array.isArray(saved.picks) ? saved.picks : []).filter((k) => {
    const valid = k && state.byUid.has(k.uid) && ['draft', 'gone'].includes(k.type) && !seen.has(k.uid);
    if (valid) seen.add(k.uid);
    return valid;
  });
  for (const [g, archs] of Object.entries(state.mainW)) {
    for (const [a, w] of Object.entries(archs)) {
      for (const k of Object.keys(w)) {
        const v = saved.mainW?.[g]?.[a]?.[k];
        if (isNum(v) && v >= 0 && v <= SLIDER_MAX) w[k] = v;
      }
    }
  }
}

// ---- Derived lists ----------------------------------------------------------------------

function visiblePlayers() {
  const s = state.search.toLowerCase();
  return state.players.filter((p) => {
    if (state.pos.size && !state.pos.has(filterPos(p))) return false;
    if (s && !p.name.toLowerCase().includes(s)) return false;
    if (state.teams.size && !state.teams.has(p.team)) return false;
    if (state.hideGone && state.picks.some((k) => k.uid === p.uid && k.type === 'gone')) return false;
    const sc = scoresFor(p);
    for (const [key, f] of Object.entries(state.filters)) {
      const v = key === 'rel' ? (sc ? p.reliability : null) : sc?.[key]?.main;
      if (v == null) continue; // players without that score are never filtered out by it
      if (v < f.lo || v > f.hi) return false;
    }
    return true;
  });
}

const pickOf = (uid) => state.picks.find((k) => k.uid === uid);
const drafted = () => state.picks.filter((k) => k.type === 'draft').map((k) => state.byUid.get(k.uid));

function buildRoster() {
  const players = drafted().slice().sort((a, b) => a.adp - b.adp);
  const slots = (names) => names.map((slot) => ({ slot, player: null }));
  const r = { batters: slots(ROSTER.batters), starters: slots(ROSTER.starters), relievers: slots(ROSTER.relievers), bench: [], overflow: [] };
  const placed = new Set();
  const place = (list, test, p) => {
    const s = list.find((x) => !x.player && test(x.slot));
    if (s) { s.player = p; placed.add(p.uid); }
  };
  for (const p of players) { // natural positions first
    const fp = filterPos(p);
    if (p.group === 'hitter' && fp !== 'DH') place(r.batters, (slot) => slot === fp, p);
    else if (p.group === 'sp') place(r.starters, (slot) => slot === 'SP', p);
    else if (p.group === 'relievers') place(r.relievers, () => true, p);
  }
  for (const p of players.filter((x) => !placed.has(x.uid))) { // then UTIL / UP
    if (p.group === 'hitter') place(r.batters, (slot) => slot === 'UTIL', p);
    else if (p.group === 'sp') place(r.starters, (slot) => slot === 'UP', p);
  }
  for (const p of players.filter((x) => !placed.has(x.uid))) {
    (r.bench.length < ROSTER.bench ? r.bench : r.overflow).push(p);
  }
  return r;
}

// ---- Render: header and panels -------------------------------------------------------------

function renderHeader() {
  const nPicks = state.picks.length;
  const filtersOn = Object.keys(state.filters).length > 0 || state.teams.size > 0;
  const light = document.documentElement.dataset.theme === 'light';
  $('header').innerHTML = `
    <h1>DRAFT SCOUT 2026</h1>
    <div class="pos-chips">
      ${POS_LIST.map((pos) => `<span class="chip${state.pos.has(pos) ? ' on' : ''}" style="--chip-color:${POS_COL[pos]}" data-act="pos" data-v="${pos}">${pos}</span>`).join('')}
      ${state.pos.size ? '<span class="chip clear" data-act="clear-pos" title="Clear positions">✕</span>' : ''}
    </div>
    <span class="chip${state.open.team ? ' on' : ''}" style="--chip-color:#5a9a6a" data-act="panel" data-v="team">My Team (${drafted().length})</span>
    <span class="chip${state.open.taken ? ' on' : ''}" style="--chip-color:#5a5040" data-act="panel" data-v="taken">Taken (${nPicks})</span>
    <span class="chip${state.hideGone ? ' on' : ''}" style="--chip-color:#5a5040" data-act="hide-gone">Hide Taken</span>
    <span class="chip${state.open.filters ? ' on' : filtersOn ? ' attn' : ''}" data-act="panel" data-v="filters">Filters</span>
    <button class="theme-btn" data-act="theme" title="Toggle theme (T)">${light ? '☀️ Light' : '🌙 Dark'}</button>
    <a class="chip guide-link" href="${REPO_URL}/blob/main/draft-tool/GUIDE.md" target="_blank" rel="noopener">How to use</a>
    <input class="search" id="search" type="text" placeholder="Search..." aria-label="Search players" value="${esc(state.search)}">
    <span class="count" id="count"></span>`;
  updateCount();
}

function updateCount(n = visiblePlayers().length) {
  const total = state.players.length;
  $('count').innerHTML = `${n}/${total} <small>(${Math.round((n / total) * 100)}%)</small>`;
}

function dualRange(key, label, color) {
  const f = state.filters[key] || { lo: 0, hi: 100 };
  const active = f.lo > 0 || f.hi < 100;
  return `<div class="filter-row${active ? ' active' : ''}" style="--c:${color}" data-row="${key}">
    <span class="fl">${label}</span><span class="fv lo">${f.lo}</span>
    <div class="dual-range" style="--lo:${f.lo}%;--hi:${f.hi}%">
      <div class="dual-range-track"><div class="dual-range-fill"></div></div>
      <input type="range" min="0" max="100" value="${f.lo}" data-fkey="${key}" data-end="lo" aria-label="${label} minimum">
      <input type="range" min="0" max="100" value="${f.hi}" data-fkey="${key}" data-end="hi" aria-label="${label} maximum">
    </div><span class="fv hi">${f.hi}</span></div>`;
}

function renderFilters() {
  const leagues = ['AL', 'NL'].map((lg) => {
    const divs = Object.keys(DIVISIONS).filter((d) => d.startsWith(lg));
    const all = divs.flatMap((d) => DIVISIONS[d]);
    return `<div><div class="league-btn${all.every((t) => state.teams.has(t)) ? ' on' : ''}" data-act="league" data-v="${lg}">${lg}</div>
      ${divs.map((d) => `<div class="div-label${DIVISIONS[d].every((t) => state.teams.has(t)) ? ' on' : ''}" data-act="division" data-v="${d}">${d.replace(lg + ' ', '')}</div>
        <div class="team-row">${DIVISIONS[d].map((t) => `<div class="team-btn${state.teams.has(t) ? ' on' : ''}" style="--tc:${TEAM_COL[t]}" data-act="team" data-v="${t}">${t}</div>`).join('')}</div>`).join('')}</div>`;
  }).join('');
  $('panel-filters').innerHTML = `
    <div class="panel-head"><span class="panel-title">FILTERS</span><button class="btn-ghost" data-act="reset-filters">Reset All</button></div>
    <div class="filter-grid">
      <div class="filter-col"><div class="filter-head hit">BATTER</div>${SCORE_FILTERS.hitter.map((f) => dualRange(...f)).join('')}</div>
      <div class="filter-col"><div class="filter-head pit">PITCHER</div>${SCORE_FILTERS.sp.map((f) => dualRange(...f)).join('')}</div>
      <div class="filter-divider"></div>
      <div class="filter-col"><div class="league-grid">${leagues}</div>
        ${state.teams.size ? `<div class="team-showing">Showing: ${[...state.teams].join(', ')}<span data-act="clear-teams">✕ Clear</span></div>` : ''}</div>
    </div>`;
}

function pill(label, val, color, bar = true) {
  return `<div class="score-pill"><span class="sp-label">${label}</span><span class="sp-val" style="color:${color}">${val ?? '–'}</span>${bar ? `<div class="sp-bar"><div class="sp-bar-fill" style="width:${val || 0}%;background:${color}"></div></div>` : ''}</div>`;
}

// List cards use the short labels to leave room for the name; My Team rows use the full names.
function scorePills(p, sc, short = false) {
  if (!sc) return '';
  return ARCH[p.group].map((a) => pill(short ? a.short : a.label, sc[a.key].main, tierColor(sc[a.key].main, a.inverse))).join('');
}

function rosterRow(p, slot, badgeCol, over = false) {
  const pk = state.picks.findIndex((k) => k.uid === p.uid) + 1;
  const sc = scoresFor(p);
  return `<div class="roster-row${over ? ' over' : ''}" data-act="select" data-uid="${esc(p.uid)}">
    <span class="slot-badge" style="--bc:${badgeCol}">${slot}</span>
    <div style="flex:1;min-width:0"><div style="display:flex;gap:4px;align-items:baseline">
      <span class="roster-name">${esc(p.name)}</span>${pk ? `<span class="pick-tag">${pickLabel(pk)}</span>` : ''}</div>
      ${sc ? `<div class="mini-pills">${scorePills(p, sc)}</div>` : ''}</div>
    <button class="btn-x" data-act="draft" data-uid="${esc(p.uid)}" title="Remove">✕</button></div>`;
}

function renderTeam() {
  const mine = drafted();
  if (!mine.length) {
    $('panel-team').innerHTML = '<div class="empty-note">Click + on a player to draft them</div>';
    return;
  }
  const r = buildRoster();
  const avg = (list, f) => {
    const v = list.map(f).filter(isNum);
    return v.length ? Math.round(v.reduce((s, x) => s + x, 0) / v.length) : '–';
  };
  const hit = mine.filter((p) => p.group === 'hitter' && !p.unscored_reason);
  const sps = mine.filter((p) => p.group === 'sp' && !p.unscored_reason);
  const box = (cls, tag, col, items) => `<div class="team-box ${cls}"><span class="tb-tag" style="color:${col}">${tag}</span>
    ${items.map(([l, v]) => `<div class="tb-item"><div class="tb-l">${l}</div><div class="tb-v" style="color:${col}">${v}</div></div>`).join('')}</div>`;
  const col = (title, color, cls, slots, total) => {
    const filled = slots.filter((s) => s.player);
    const order = (s) => state.picks.findIndex((k) => k.uid === s.player.uid);
    return `<div class="team-col ${cls}"><div class="col-head" style="--hc:${color}"><span>${title}</span><span>${filled.length}/${total}</span></div>
      ${filled.sort((a, b) => order(a) - order(b)).map((s) => rosterRow(s.player, s.slot, s.slot === 'UTIL' ? '#8a8a8a' : POS_COL[s.slot] || POS_COL.RP)).join('')
        || `<div class="empty-note">No ${title.toLowerCase()}</div>`}</div>`;
  };
  $('panel-team').innerHTML = `
    <div class="panel-head"><span class="panel-title">MY TEAM (${mine.length}/${ROSTER.batters.length + ROSTER.starters.length + ROSTER.relievers.length + ROSTER.bench})</span>
      <button class="btn-ghost" data-act="clear-picks">Clear</button></div>
    <div class="team-summary-row">
      ${hit.length ? box('hit', 'HIT', '#3a7ca5', ARCH.hitter.map((a) => [a.label, avg(hit, (p) => scoresFor(p)[a.key].main)])) : ''}
      ${sps.length ? box('sp', 'SP', '#e0734a', ARCH.sp.map((a) => [a.label, avg(sps, (p) => scoresFor(p)[a.key].main)])) : ''}
    </div>
    <div class="team-columns">
      ${col('BATTERS', '#3a7ca5', 'w40', r.batters, ROSTER.batters.length)}
      ${col('STARTERS', '#e0734a', 'w40', r.starters, ROSTER.starters.length)}
      ${col('RELIEVERS', '#5a9a6a', 'w20', r.relievers, ROSTER.relievers.length)}
    </div>
    ${r.bench.length ? `<div style="margin-top:6px"><div class="col-head" style="--hc:#555"><span>BENCH</span><span>${r.bench.length}/${ROSTER.bench}</span></div>
      ${r.bench.map((p) => rosterRow(p, filterPos(p), POS_COL[filterPos(p)] || '#888')).join('')}</div>` : ''}
    ${r.overflow.length ? `<div style="margin-top:6px"><div class="col-head" style="--hc:#c05848"><span>OVER ROSTER</span><span>+${r.overflow.length}</span></div>
      ${r.overflow.map((p) => rosterRow(p, filterPos(p), POS_COL[filterPos(p)] || '#888', true)).join('')}</div>` : ''}`;
}

function renderTaken() {
  if (!state.picks.length) {
    $('panel-taken').innerHTML = '<div class="empty-note">No picks yet. Use + for your picks and − for players taken by others.</div>';
    return;
  }
  const rounds = new Map();
  state.picks.forEach((k, i) => {
    const r = Math.ceil((i + 1) / TEAMS_IN_LEAGUE);
    if (!rounds.has(r)) rounds.set(r, []);
    rounds.get(r).push({ ...k, n: i + 1 });
  });
  const roundHtml = [...rounds].map(([r, picks]) => `<div class="board-round"><div class="round-tag">Round ${r}</div>
    ${picks.map((k) => {
      const p = state.byUid.get(k.uid);
      const fp = filterPos(p);
      return `<div class="board-pick${k.type === 'draft' ? ' mine' : ''}" data-act="select" data-uid="${esc(p.uid)}">
        <span class="bp-num">${pickLabel(k.n)}</span><span class="slot-badge" style="--bc:${POS_COL[fp] || '#888'};min-width:24px;font-size:8px">${fp}</span>
        <span class="bp-name">${esc(p.name)}</span>
        <button class="btn-undo" data-act="${k.type}" data-uid="${esc(p.uid)}" title="Undo">↩</button></div>`;
    }).join('')}</div>`);
  const rows = [];
  for (let i = 0; i < roundHtml.length; i += 3) rows.push(`<div class="board-row">${roundHtml.slice(i, i + 3).join('')}${'<div class="board-round"></div>'.repeat(Math.max(0, 3 - roundHtml.slice(i, i + 3).length))}</div>`);
  $('panel-taken').innerHTML = `<div class="panel-head"><span class="panel-title">DRAFT BOARD (${state.picks.length})</span></div>${rows.join('')}`;
}

function renderPanels() {
  for (const k of ['filters', 'team', 'taken']) $('panel-' + k).hidden = !state.open[k];
  if (state.open.filters) renderFilters();
  if (state.open.team) renderTeam();
  if (state.open.taken) renderTaken();
}

// ---- Render: player list -----------------------------------------------------------------

function card(p) {
  const sc = scoresFor(p);
  const pk = pickOf(p.uid);
  const sel = state.selected === p.uid;
  const canCompare = state.selected && !sel && !p.unscored_reason;
  const fp = filterPos(p);
  const cls = ['player-card', 'type-' + GROUPS[p.group].type, sel && 'selected', state.compare === p.uid && 'comparing',
    pk?.type === 'draft' && 'drafted', pk?.type === 'gone' && 'gone'].filter(Boolean).join(' ');
  let pills;
  if (p.unscored_reason) pills = '<div class="no-score">No MLB history to project</div>';
  else if (p.group === 'relievers') pills = pill('ERA', fD(p.proj_era, 2), 'var(--text-value)', false) + pill('K', fI(p.proj_so), 'var(--text-value)', false);
  else pills = pill('REL', p.reliability, 'var(--accent-rel)') + '<div class="pill-divider"></div>' + scorePills(p, sc, true);
  return `<div class="${cls}" data-act="select" data-uid="${esc(p.uid)}">
    <div class="card-actions">
      <button class="btn-action btn-draft${pk?.type === 'draft' ? ' active' : ''}" data-act="draft" data-uid="${esc(p.uid)}" title="My pick">+</button>
      <button class="btn-action btn-gone${pk?.type === 'gone' ? ' active' : ''}" data-act="gone" data-uid="${esc(p.uid)}" title="Taken by someone else">−</button>
      ${canCompare ? `<button class="btn-action btn-compare${state.compare === p.uid ? ' active' : ''}" data-act="compare" data-uid="${esc(p.uid)}" title="Compare">⇄</button>` : ''}
    </div>
    <div class="card-badges"><span class="rank-badge" title="ADP rank">${p.rank}</span><span class="adp-tag" title="FantasyPros ADP">${Math.round(p.adp)}</span></div>
    <div class="card-info"><span class="player-name">${esc(p.name)}</span>
      <div class="player-meta"><span style="color:${POS_COL[fp] || 'inherit'};font-weight:600">${esc(p.position)}</span><span class="sep">·</span>
        <span style="color:${TEAM_COL[p.team] || 'inherit'};font-weight:600">${esc(p.team)}</span>${isNum(p.age) ? `<span class="sep">·</span><span class="muted">${p.age}</span>` : ''}</div></div>
    <div class="card-pills">${pills}</div></div>`;
}

function renderList() {
  const list = visiblePlayers();
  updateCount(list.length);
  if (!list.length) {
    $('list').innerHTML = '<div class="list-empty"><div>No players match your filters</div><div>Try adjusting your position, team, or score filters</div></div>';
    return;
  }
  // A divider wherever the draft round changes, so a filtered list keeps real rounds.
  $('list').innerHTML = list.map((p, i) => (i === 0 || p.round !== list[i - 1].round ? `<div class="round-div">Round ${p.round}</div>` : '') + card(p)).join('');
}

// ---- Render: player profile --------------------------------------------------------------

function oval(label, s, kind) {
  const c = kind === 'rel' ? 'var(--accent-rel)' : tierColor(s, kind === 'inverse');
  return `<span class="oval" style="border-color:${c};color:${c};background:color-mix(in srgb, ${c} 15%, transparent)">${label} ${s ?? '–'}</span>`;
}

function bar(label, s, color) {
  const w = Math.max(2, Math.min(100, s || 0));
  return `<div class="bar-row"><span class="bar-label">${label}</span>
    <div class="bar-stack"><div class="pbar"><div class="pbar-fill" style="width:${w}%;background:${color}"></div></div></div>
    <span class="bar-value">${s ?? '–'}</span></div>`;
}

function table(cls, heads, rows) {
  // Tables with row labels reserve a column wide enough for "2026 Marcel" in every layout.
  const cols = cls.includes('rows') ? `<colgroup><col class="labcol">${'<col>'.repeat(heads.length - 1)}</colgroup>` : '';
  return `<div class="table-wrap"><table class="dt ${cls}">${cols}<thead><tr>${heads.map((h) => `<th>${h}</th>`).join('')}</tr></thead>
    <tbody>${rows.map((r) => `<tr>${r.map((c, i) => `<td${i === 0 && cls.includes('rows') ? ' class="rowlab"' : ''}>${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function statsTables(p) {
  const y = season(p, STATS_YEAR);
  const k9 = (so, ip) => (isNum(so) && ip > 0 ? (9 * so) / ip : null);
  const noRow = (n) => [`${STATS_YEAR}`, ...Array(n).fill('–')];
  let html = `<div class="sec-label">${STATS_YEAR} Stats / 2026 Marcel Projections</div>`;
  if (p.group === 'hitter') {
    html += table('pop rows', ['', 'PA', 'HR', 'R', 'RBI', 'SB', 'AVG', 'OPS'], [
      y ? [STATS_YEAR, fI(y.pa), fI(y.hr), fI(y.r), fI(y.rbi), fI(y.sb), fA(y.avg), fA(y.ops)] : noRow(7),
      ['2026 Marcel', fI(p.proj_pa), fI(p.proj_hr), fI(p.proj_r), fI(p.proj_rbi), fI(p.proj_sb), fA(p.proj_avg), fA(p.proj_ops)],
    ]);
    html += `<div class="sec-label">Underlying Metrics <small>(Baseball Savant ${STATS_YEAR})</small></div>`;
    html += table('pop', ['EV', 'maxEV', 'Brl%', 'HH%', 'xBA', 'xSLG', 'Sprint', 'K%'], [[
      fD(p.avg_ev, 1), fD(p.max_ev, 1), fD(p.barrel_pct, 1), fD(p.hard_hit_pct, 1), fA(p.xba), fA(p.xslg), fD(p.sprint_speed, 1), fD(p.k_pct_2025, 1)]]);
  } else if (p.group === 'sp') {
    html += table('pop rows', ['', 'IP', 'QS', 'K', 'ERA', 'WHIP', 'K/9'], [
      y ? [STATS_YEAR, fI(y.ip), fI(y.qs), fI(y.so), fD(y.era, 2), fD(y.whip, 2), fD(k9(y.so, y.ip), 2)] : noRow(6),
      ['2026 Marcel', fI(p.proj_ip), fI(p.proj_qs), fI(p.proj_so), fD(p.proj_era, 2), fD(p.proj_whip, 2), fD(p.proj_k9, 2)],
    ]);
    html += `<div class="sec-label">Underlying Metrics <small>(Baseball Savant ${STATS_YEAR})</small></div>`;
    html += table('pop', ['FBv', 'Whiff%', 'K%', 'BB%', 'xERA', 'HH%', 'GB%'], [[
      fD(p.fb_velo, 1), fD(p.whiff_pct, 1), fD(p.k_pct_2025, 1), fD(p.bb_pct_2025, 1), fD(p.xera, 2), fD(p.hard_hit_pct, 1), fD(p.gb_pct, 1)]]);
  } else {
    html += table('pop rows', ['', 'IP', 'SV', 'K', 'ERA', 'WHIP', 'K/9'], [
      y ? [STATS_YEAR, fI(y.ip), fI(y.sv), fI(y.so), fD(y.era, 2), fD(y.whip, 2), fD(k9(y.so, y.ip), 2)] : noRow(6),
      ['2026 Marcel', fI(p.proj_ip), '–', fI(p.proj_so), fD(p.proj_era, 2), fD(p.proj_whip, 2), fD(p.proj_k9, 2)],
    ]);
  }
  return html;
}

// The seasons he actually played within 2023-25: "2025", "2024-25", "2023-25" or "2023, 2025".
function seasonsLabel(p) {
  const yrs = [...new Set((p.history || []).map((y) => y.season))].sort();
  if (!yrs.length) return '2023-25';
  const contiguous = yrs[yrs.length - 1] - yrs[0] === yrs.length - 1;
  if (yrs.length === 1) return String(yrs[0]);
  return contiguous ? `${yrs[0]}-${String(yrs[yrs.length - 1]).slice(-2)}` : yrs.join(', ');
}

function spanAndHistory(p) {
  let html = `<div class="sec-label">${seasonsLabel(p)} averages</div>`;
  if (p.group === 'hitter') {
    html += table('styled', ['HR/600', 'R/600', 'RBI/600', 'SB/600', 'AVG', 'OPS'], [[
      fI(p.y3_hr_600), fI(p.y3_r_600), fI(p.y3_rbi_600), fI(p.y3_sb_600), fA(p.y3_avg), fA(p.y3_ops)]]);
  } else {
    html += table('styled', ['ERA', 'WHIP', 'K/9', 'Brl%', 'HH%', 'FBv'], [[
      fD(p.y3_era, 2), fD(p.y3_whip, 2), fD(p.y3_k9, 2), fD(p.y3_barrel_pct, 1), fD(p.y3_hard_hit_pct, 1), fD(p.y3_fb_velo, 1)]]);
  }
  const hist = p.history || [];
  if (!hist.length) return html;
  html += `<button class="toggle-btn" data-act="toggle-hist">${state.showHist ? '▾ Hide' : '▸ Show'} Year-by-Year (${hist.length} season${hist.length > 1 ? 's' : ''})</button>`;
  if (!state.showHist) return html;
  const yr = (y) => `<span class="yr">'${String(y.season).slice(-2)}</span>`;
  const k9 = (y) => (y.ip > 0 ? fD((9 * y.so) / y.ip, 2) : '–');
  let t;
  if (p.group === 'hitter') {
    t = table('styled hist', ['Yr', 'Team', 'G', 'PA', 'HR', 'R', 'RBI', 'SB', 'AVG', 'OPS', 'EV', 'Brl%'], hist.map((y) => [
      yr(y), esc(y.team), y.g, y.pa, y.hr, y.r, y.rbi, y.sb, fA(y.avg), fA(y.ops), fD(y.avg_ev, 1), fD(y.barrel_pct, 1)]));
  } else if (p.group === 'sp') {
    t = table('styled hist', ['Yr', 'Team', 'G', 'GS', 'IP', 'QS', 'W', 'L', 'K', 'ERA', 'WHIP', 'K/9', 'FBv'], hist.map((y) => [
      yr(y), esc(y.team), y.g, y.gs, fI(y.ip), y.qs, y.w, y.l, y.so, fD(y.era, 2), fD(y.whip, 2), k9(y), fD(y.fb_velo, 1)]));
  } else {
    t = table('styled hist', ['Yr', 'Team', 'Role', 'G', 'IP', 'W', 'L', 'SV', 'K', 'ERA', 'WHIP', 'K/9', 'FBv'], hist.map((y) => [
      yr(y), esc(y.team), y.role, y.g, fI(y.ip), y.w, y.l, y.sv, y.so, fD(y.era, 2), fD(y.whip, 2), k9(y), fD(y.fb_velo, 1)]));
  }
  return html + `<div class="hist-wrap">${t}</div>`;
}

function archetypes(p, sc) {
  let html = `<div class="sec-label">Reliability</div>${bar('Score', p.reliability, tierColor(p.reliability))}
    <div class="sec-label">Archetype Scores</div>`;
  for (const a of ARCH[p.group].filter((x) => !x.inverse)) html += bar(a.label, sc[a.key].main, a.color);
  if (p.group === 'sp') {
    html += `<div class="sec-label">Volatility <small>(higher is riskier)</small></div>${bar('Volatility', sc.vol.main, tierColor(sc.vol.main, true))}`;
  }
  return html;
}

// Each archetype's 2025 Results score next to its 2025 Skills score; Speed and Volatility have no pair.
function resultsVsSkills(p, sc) {
  const flag = p.small_2025_sample ? ' <span class="flag" title="Fewer than 200 PA or 50 IP in 2025">small 2025 sample</span>' : '';
  const rows = ARCH[p.group].filter((a) => hasGap(p.group, a.key)).map((a) => {
    const { results, skills, gap } = sc[a.key];
    const g = gap == null ? '–' : `<span class="gap" style="color:${gapColor(gap)}">${gap > 0 ? '+' : ''}${gap}</span>`;
    return [a.label, results ?? '–', skills ?? '–', g + flag];
  });
  const note = p.group === 'hitter'
    ? "Speed isn't included: the skill side is sprint speed, already in the Speed score, and steals depend more on whether a player runs than on luck."
    : "Volatility isn't included: it's already built from Statcast contact numbers, so there's no separate results version to compare against.";
  return `<div class="sec-label">${STATS_YEAR} Results vs Skills</div>
    <div class="sec-note">How each archetype scored on ${STATS_YEAR} results versus ${STATS_YEAR} Statcast skills. A positive gap means the skills were better than the results.</div>
    ${table('pop rows gap-table', ['', 'Results', 'Skills', 'Gap'], rows)}
    <div class="sec-note">${note}</div>`;
}

function profile(p, compact = false) {
  if (!p) return '<div class="detail-empty">Select a player to view their profile</div>';
  const sc = scoresFor(p);
  const fp = filterPos(p);
  let html = `<div class="detail${compact ? ' compact' : ''}"><div class="detail-head">
    ${p.player_id ? `<img class="headshot" src="${headshot(p.player_id)}" alt="" loading="lazy" onerror="this.style.display='none'">` : ''}
    <div><h2>${esc(p.name)}</h2><div class="player-meta">
      <span style="color:${POS_COL[fp] || 'inherit'};font-weight:600">${esc(p.position)}</span> · <span style="color:${TEAM_COL[p.team] || 'inherit'};font-weight:600">${esc(p.team)}</span>
      <span class="muted"> · ${isNum(p.age) ? `Age ${p.age} · ` : ''}ADP ${fD(p.adp, 1)}</span></div>
      ${p.adp_note ? `<div class="adp-note">${esc(p.adp_note)}</div>` : ''}</div></div>`;
  if (p.unscored_reason) {
    return html + `<div class="note-box"><b>No MLB history to project.</b> He had no MLB time in 2023-25, so there's no Marcel projection or score. He's listed at his FantasyPros ADP.</div></div>`;
  }
  if (sc) {
    html += `<div class="ovals">${oval('REL', p.reliability, 'rel')}<span class="oval-divider"></span>
      ${ARCH[p.group].map((a) => oval(a.label, sc[a.key].main, a.inverse ? 'inverse' : '')).join('')}</div>`;
  } else {
    const role = season(p, STATS_YEAR)?.role ?? p.role;
    html += `<div class="note-box">No closer score: Marcel doesn't project saves.${role === 'CL' ? ` Closer in ${STATS_YEAR}.` : ''}</div>`;
  }
  html += statsTables(p);
  if (sc) html += archetypes(p, sc) + resultsVsSkills(p, sc);
  html += spanAndHistory(p);
  return html + '</div>';
}

function dictionary(p) {
  if (!p || compareActive() || !ARCH[p.group] || p.unscored_reason) return '';
  let html = `<div class="detail" style="padding-top:0"><button class="toggle-btn" data-act="toggle-dict">${state.showDict ? '▾ Hide' : '▸ Show'} Score Dictionary &amp; Weights</button>`;
  if (!state.showDict) return html + '</div>';
  const g = p.group;
  html += `<div class="dict"><button class="btn-ghost reset" data-act="reset-weights" data-v="${g}">Reset weights</button>
    <span class="cat">HOW THE SCORES WORK</span>
    Every input is a percentile (0-100) within the ${g === 'hitter' ? 'hitters' : 'starting pitchers'} of the draft pool (FantasyPros ADP 300 or better).
    Each score is a weighted mean of the inputs a player has; missing inputs are skipped.<br>
    <b>Score</b>: the archetype score shown throughout the tool. Its weights are the sliders below and update every score live.<br>
    <b>${STATS_YEAR} Results</b> and <b>${STATS_YEAR} Skills</b>: fixed weights for the two scores compared in "${STATS_YEAR} Results vs Skills" on the player page.
    Results uses ${STATS_YEAR} results as rates; Skills uses ${STATS_YEAR} Statcast skill measures. The gap is Skills minus Results.`;
  // One table per archetype: every input once, with its Score (slider), Results and Skills weight.
  for (const a of ARCH[g]) {
    const sets = state.weights[g][a.key];
    const main = state.mainW[g][a.key];
    const pair = hasGap(g, a.key);
    const keys = [...new Set([...Object.keys(main), ...Object.keys(sets.raw || {}), ...Object.keys(sets.und || {})])];
    const fixed = (w) => `<td>${w == null ? '' : `<span class="wv">${w}</span>`}</td>`;
    html += `<span class="cat">${a.label.toUpperCase()}${a.inverse ? ' (higher is riskier)' : ''}</span>
      <table class="wt-table${pair ? '' : ' score-only'}"><thead><tr><th>Input</th><th>Score</th>${pair ? `<th>${STATS_YEAR} Results</th><th>${STATS_YEAR} Skills</th>` : ''}</tr></thead><tbody>
      ${keys.map((k) => {
        const [label, def] = INPUTS[k] || [k, ''];
        const slider = k in main ? `<div class="wt-main"><input type="range" min="0" max="${SLIDER_MAX}" value="${main[k]}" aria-label="${esc(label)}: Score weight"
          data-wgroup="${g}" data-warch="${a.key}" data-wkey="${k}"><span class="wv">${main[k]}</span></div>` : '';
        return `<tr><td class="wt-name"><b>${label}</b><div class="wt-def">${def}</div></td><td>${slider}</td>${pair ? fixed(sets.raw[k]) + fixed(sets.und[k]) : ''}</tr>`;
      }).join('')}</tbody></table>`;
  }
  const rw = state.weights.reliability.weights;
  const relRows = [
    ['Recency', rw.recency, 'Games (or innings) per season in 2023-25, recent seasons weighted more'],
    ['Projected playing time', rw.proj, "Marcel's 2026 projected PA (or IP)"],
    ['Age', rw.age_rel, 'Full credit through 33, less each year after'],
  ];
  html += `<span class="cat">RELIABILITY (0-100)</span>
    Recency and projected playing time are percentiles within the player's group; age is a fixed scale.
    <table class="wt-table rel-table"><thead><tr><th>Input</th><th>Weight</th><th>What it measures</th></tr></thead><tbody>
      ${relRows.map(([name, w, what]) => `<tr><td class="wt-name"><b>${name}</b></td><td><span class="wv">${w}</span></td><td class="wt-what">${what}</td></tr>`).join('')}
    </tbody></table>`;
  const cols = ['#c05848', '#c09868', '#a89e8a', '#8ab87a', '#6aaa7a'];
  const tiers = ['Bad', 'Poor', 'Avg', 'Good', 'Elite'];
  html += `<span class="cat">RANGES IN THE DRAFT POOL (${STATS_YEAR})</span>10th, 25th, 50th, 75th and 90th percentile among scored ${g === 'hitter' ? 'hitters' : 'starters'}.
    <div class="range-strip range-legend">${['10th', '25th', '50th', '75th', '90th'].map((q, i) => `<span style="background:${cols[i]}">${q} = ${tiers[i]}</span>`).join('')}</div>`;
  for (const [f, label, unit, lowGood] of GLOSSARY[g]) {
    const q = state.ranges[g][f];
    if (!q) continue;
    const names = lowGood ? ['Elite', 'Good', 'Avg', 'Poor', 'Bad'] : ['Bad', 'Poor', 'Avg', 'Good', 'Elite'];
    const fmt = (v) => (v < 1 ? fA(v) : v >= 20 ? fD(v, 1) : fD(v, 2)) + unit;
    html += `<div class="def"><b>${label}</b></div><div class="range-strip">${q.map((v, i) => `<span style="background:${lowGood ? cols[4 - i] : cols[i]}">${names[i]} ${fmt(v)}</span>`).join('')}</div>`;
  }
  return html + '</div></div>';
}

const compareActive = () => state.compare && state.selected && state.compare !== state.selected;

function renderDetail() {
  const sel = state.byUid.get(state.selected);
  if (compareActive()) {
    $('detail').innerHTML = `<div class="compare-head"><span>⇄ COMPARING</span><button class="btn-close" data-act="close-compare">✕ Close</button></div>
      <div class="compare-cols"><div>${profile(sel, true)}</div><div>${profile(state.byUid.get(state.compare), true)}</div></div>`;
  } else {
    $('detail').innerHTML = `<div id="detail-body">${profile(sel)}</div><div id="detail-dict">${dictionary(sel)}</div>`;
  }
  renderSheet();
}

// Re-renders the profile but not the dictionary, so a slider being dragged keeps its place.
function renderDetailBody() {
  if (compareActive() || !$('detail-body')) return renderDetail();
  $('detail-body').innerHTML = profile(state.byUid.get(state.selected));
  renderSheet();
}

function renderSheet() {
  const sheet = $('mobile-sheet');
  const sel = state.byUid.get(state.selected);
  if (!state.mobileOpen || !sel || window.innerWidth > 768) { sheet.hidden = true; return; }
  sheet.hidden = false;
  sheet.innerHTML = `<div class="sheet-head"><span>${compareActive() ? '⇄ Comparing' : esc(sel.name)}</span><button class="btn-close" data-act="close-sheet">✕</button></div>
    <div class="sheet-body">${compareActive() ? `<div class="compare-cols"><div>${profile(sel, true)}</div><div>${profile(state.byUid.get(state.compare), true)}</div></div>` : profile(sel, true)}</div>`;
}

function renderAll() {
  renderHeader();
  renderPanels();
  renderList();
  renderDetail();
}

// ---- Actions -----------------------------------------------------------------------------

function togglePick(uid, type) {
  const i = state.picks.findIndex((k) => k.uid === uid);
  if (i === -1) state.picks.push({ uid, type });
  else if (state.picks[i].type === type) state.picks.splice(i, 1); // same button again: undo
  else state.picks[i].type = type; // switch between mine and taken, keeping the pick number
  saveDraft();
}

function toggleSet(set, values) {
  const all = values.every((v) => set.has(v));
  values.forEach((v) => (all ? set.delete(v) : set.add(v)));
}

function toggleTheme() {
  const light = document.documentElement.dataset.theme !== 'light';
  if (light) document.documentElement.dataset.theme = 'light';
  else delete document.documentElement.dataset.theme;
  try { localStorage.setItem('ds-theme', light ? 'light' : 'dark'); } catch (e) { /* storage blocked: theme lasts this visit */ }
  renderHeader();
}

const ACTIONS = {
  select: (uid) => {
    state.selected = uid;
    if (state.compare === uid) state.compare = null;
    state.mobileOpen = window.innerWidth <= 768;
    renderList();
    renderDetail();
  },
  draft: (uid) => { togglePick(uid, 'draft'); renderAll(); },
  gone: (uid) => { togglePick(uid, 'gone'); renderAll(); },
  compare: (uid) => { state.compare = state.compare === uid ? null : uid; state.mobileOpen = window.innerWidth <= 768; renderList(); renderDetail(); },
  'close-compare': () => { state.compare = null; renderList(); renderDetail(); },
  'close-sheet': () => { state.mobileOpen = false; state.compare = null; renderSheet(); renderList(); },
  pos: (_, v) => { toggleSet(state.pos, [v]); renderHeader(); renderList(); },
  'clear-pos': () => { state.pos.clear(); renderHeader(); renderList(); },
  panel: (_, v) => { state.open[v] = !state.open[v]; renderHeader(); renderPanels(); },
  'hide-gone': () => { state.hideGone = !state.hideGone; renderHeader(); renderList(); },
  theme: toggleTheme,
  team: (_, v) => { toggleSet(state.teams, [v]); renderFilters(); renderHeader(); renderList(); },
  division: (_, v) => { toggleSet(state.teams, DIVISIONS[v]); renderFilters(); renderHeader(); renderList(); },
  league: (_, v) => { toggleSet(state.teams, Object.keys(DIVISIONS).filter((d) => d.startsWith(v)).flatMap((d) => DIVISIONS[d])); renderFilters(); renderHeader(); renderList(); },
  'clear-teams': () => { state.teams.clear(); renderFilters(); renderHeader(); renderList(); },
  'reset-filters': () => { state.filters = {}; state.teams.clear(); renderFilters(); renderHeader(); renderList(); },
  'clear-picks': () => { state.picks = []; saveDraft(); renderAll(); },
  'toggle-hist': () => { state.showHist = !state.showHist; renderDetailBody(); },
  'toggle-dict': () => { state.showDict = !state.showDict; renderDetail(); },
  'reset-weights': (_, g) => {
    for (const [a, sets] of Object.entries(state.weights[g])) state.mainW[g][a] = { ...sets.main };
    saveDraft();
    renderAll();
  },
};

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || !ACTIONS[el.dataset.act]) return;
  if (el.tagName === 'BUTTON') e.stopPropagation();
  ACTIONS[el.dataset.act](el.dataset.uid, el.dataset.v);
});

document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.id === 'search') {
    state.search = t.value;
    renderList();
  } else if (t.dataset.wkey) { // a Score weight slider: rescore everything, keep the slider in place
    state.mainW[t.dataset.wgroup][t.dataset.warch][t.dataset.wkey] = Number(t.value);
    t.nextElementSibling.textContent = t.value;
    saveDraft();
    renderList();
    renderDetailBody();
    if (state.open.team) renderTeam();
  } else if (t.dataset.fkey) { // a score filter: update the slider in place, then the list
    const key = t.dataset.fkey;
    const f = { ...(state.filters[key] || { lo: 0, hi: 100 }) };
    f[t.dataset.end] = Number(t.value);
    if (f.lo > f.hi) { f[t.dataset.end] = t.dataset.end === 'lo' ? f.hi : f.lo; t.value = f[t.dataset.end]; }
    if (f.lo === 0 && f.hi === 100) delete state.filters[key];
    else state.filters[key] = f;
    const row = t.closest('.filter-row');
    row.classList.toggle('active', f.lo > 0 || f.hi < 100);
    row.querySelector('.dual-range').style.cssText = `--lo:${f.lo}%;--hi:${f.hi}%`;
    row.querySelector('.fv.lo').textContent = f.lo;
    row.querySelector('.fv.hi').textContent = f.hi;
    renderList();
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'T' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) toggleTheme();
});
window.addEventListener('resize', () => renderSheet());

// ---- Start -------------------------------------------------------------------------------

$('repo-link').href = REPO_URL;
load().then(() => { restoreDraft(); renderAll(); }).catch((err) => {
  $('list').innerHTML = `<div class="list-empty"><div>Couldn't load the player data</div><div>${esc(err.message)}. Serve this folder over HTTP (see README.md) rather than opening the file directly.</div></div>`;
  console.error(err);
});
