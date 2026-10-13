// Teams, rosters and the playbook.
import { mulberry32, hashString, pick } from './util.js';

export const TEAMS = [
  { id: 'ash', school: 'Ashford State', name: 'Stallions', abbr: 'ASH', letter: 'A',
    primary: '#9e1b32', secondary: '#ffffff', trim: '#1b1b1f', helmet: '#9e1b32', mask: '#e9e9ec',
    ovr: 89, off: 90, def: 87, city: 'Ashford, AL' },
  { id: 'lkt', school: 'Lakeshore Tech', name: 'Hurricanes', abbr: 'LTU', letter: 'L',
    primary: '#0c2a5c', secondary: '#d8a637', trim: '#ffffff', helmet: '#d8a637', mask: '#0c2a5c',
    ovr: 86, off: 84, def: 89, city: 'Port Huron, MI' },
  { id: 'pvl', school: 'Pine Valley', name: 'Rangers', abbr: 'PVU', letter: 'P',
    primary: '#124d2e', secondary: '#f0c84d', trim: '#ffffff', helmet: '#124d2e', mask: '#f0c84d',
    ovr: 84, off: 86, def: 81, city: 'Eugene Falls, OR' },
  { id: 'sum', school: 'Summit', name: 'Thunder', abbr: 'SUM', letter: 'S',
    primary: '#cf5a1e', secondary: '#ffffff', trim: '#2a2a2e', helmet: '#ffffff', mask: '#cf5a1e',
    ovr: 87, off: 88, def: 85, city: 'Knoxridge, TN' },
  { id: 'irw', school: 'Ironwood', name: 'Knights', abbr: 'IWU', letter: 'K',
    primary: '#4b2a85', secondary: '#c9c9d1', trim: '#ffffff', helmet: '#c9c9d1', mask: '#4b2a85',
    ovr: 82, off: 80, def: 84, city: 'Baton Ridge, LA' },
  { id: 'bay', school: 'Bayport', name: 'Mariners', abbr: 'BAY', letter: 'B',
    primary: '#00727a', secondary: '#101418', trim: '#ffffff', helmet: '#101418', mask: '#00727a',
    ovr: 80, off: 83, def: 78, city: 'Bayport, FL' },
  { id: 'crk', school: 'Cedar Rock', name: 'Bison', abbr: 'CRU', letter: 'C',
    primary: '#1d3f8f', secondary: '#c8102e', trim: '#ffffff', helmet: '#ffffff', mask: '#1d3f8f',
    ovr: 85, off: 83, def: 87, city: 'Lincoln Plains, NE' },
  { id: 'msa', school: 'Mesa A&M', name: 'Scorpions', abbr: 'MAM', letter: 'M',
    primary: '#5a0f1c', secondary: '#c9a46a', trim: '#ffffff', helmet: '#c9a46a', mask: '#5a0f1c',
    ovr: 83, off: 85, def: 82, city: 'Red Mesa, TX' },
];

const FIRST = ['Jaylen', 'Marcus', 'Caleb', 'Tre', 'Devin', 'Malik', 'Drew', 'Bryce', 'Cole', 'Isaiah', 'Xavier', 'Jalen',
  'Kendrick', 'Tyler', 'Ryan', 'Darius', 'Quinn', 'Jordan', 'Mason', 'Elijah', 'Cam', 'Trey', 'Andre', 'Jamal', 'Nico',
  'Brady', 'Luke', 'Zion', 'Deshawn', 'Carson', 'Micah', 'Keon', 'Austin', 'Rashad', 'Owen', 'Jace', 'Tavion', 'Eli'];
const LAST = ['Carter', 'Brooks', 'Whitfield', 'Dawson', 'Okafor', 'Reeves', 'Holloway', 'Pruitt', 'Vance', 'Sutton',
  'Bishop', 'Coleman', 'Mercer', 'Grant', 'Langford', 'Ellison', 'Moody', 'Fairley', 'Battle', 'Kincaid', 'Rowe',
  'Hargrove', 'Tillman', 'Akers', 'Mabry', 'Stroud', 'Lockett', 'Pope', 'Gaines', 'Whitaker', 'Boone', 'Nwosu',
  'Castillo', 'Harlan', 'Jessup', 'Odom', 'Fontenot', 'McCrae', 'Sanford', 'Tate'];

// Positional ratings template (0..1). Speed is top speed in yards per second.
const POS_BASE = {
  QB: { spd: 8.3, str: 0.55, cat: 0.55, tak: 0.3, blk: 0.3, awr: 0.85, thp: 0.85, tha: 0.86, size: 1.0 },
  RB: { spd: 9.5, str: 0.7, cat: 0.72, tak: 0.35, blk: 0.55, awr: 0.75, size: 0.98 },
  FB: { spd: 8.0, str: 0.82, cat: 0.65, tak: 0.5, blk: 0.8, awr: 0.7, size: 1.06 },
  WR: { spd: 9.9, str: 0.48, cat: 0.86, tak: 0.25, blk: 0.4, awr: 0.75, size: 0.95 },
  TE: { spd: 8.7, str: 0.74, cat: 0.78, tak: 0.35, blk: 0.72, awr: 0.75, size: 1.1 },
  OL: { spd: 6.9, str: 0.86, cat: 0.2, tak: 0.3, blk: 0.84, awr: 0.75, size: 1.28 },
  DL: { spd: 7.6, str: 0.85, cat: 0.25, tak: 0.78, blk: 0.3, awr: 0.72, size: 1.2 },
  LB: { spd: 8.7, str: 0.75, cat: 0.55, tak: 0.86, blk: 0.4, awr: 0.78, size: 1.08 },
  CB: { spd: 9.8, str: 0.5, cat: 0.62, tak: 0.66, blk: 0.3, awr: 0.76, size: 0.94 },
  S: { spd: 9.3, str: 0.62, cat: 0.62, tak: 0.8, blk: 0.35, awr: 0.8, size: 0.99 },
  K: { spd: 7.0, str: 0.4, cat: 0.3, tak: 0.2, blk: 0.2, awr: 0.6, kpw: 0.85, kac: 0.85, size: 0.95 },
  P: { spd: 7.2, str: 0.4, cat: 0.4, tak: 0.2, blk: 0.2, awr: 0.6, kpw: 0.85, kac: 0.8, size: 0.97 },
};

const NUM_RANGES = {
  QB: [1, 19], RB: [1, 39], FB: [30, 49], WR: [1, 19], TE: [80, 89], OL: [50, 79], DL: [90, 99],
  LB: [30, 59], CB: [1, 29], S: [1, 39], K: [90, 99], P: [10, 49],
};

// Starting lineup slots. Offense uses 11 personnel; formations decide who plays.
const ROSTER_SLOTS = [
  ['QB', 'QB'], ['RB', 'RB'], ['FB', 'FB'], ['WR', 'X'], ['WR', 'Z'], ['WR', 'SL'], ['WR', 'SL2'], ['TE', 'TE'],
  ['OL', 'LT'], ['OL', 'LG'], ['OL', 'C'], ['OL', 'RG'], ['OL', 'RT'],
  ['DL', 'LE'], ['DL', 'DT1'], ['DL', 'DT2'], ['DL', 'RE'], ['LB', 'WILL'], ['LB', 'MIKE'],
  ['CB', 'CB1'], ['CB', 'CB2'], ['CB', 'NB'], ['S', 'FS'], ['S', 'SS'], ['K', 'K'], ['P', 'P'],
];

export function buildRoster(team) {
  const r = mulberry32(hashString(team.id + team.school));
  const used = new Set();
  const roster = {};
  const offAdj = (team.off - 85) / 100;
  const defAdj = (team.def - 85) / 100;
  for (const [pos, slot] of ROSTER_SLOTS) {
    const base = POS_BASE[pos];
    const [lo, hi] = NUM_RANGES[pos];
    let num;
    let guard = 0;
    do { num = lo + Math.floor(r() * (hi - lo + 1)); guard++; } while (used.has(num) && guard < 50);
    used.add(num);
    const isOff = ['QB', 'RB', 'FB', 'WR', 'TE', 'OL'].includes(pos);
    const adj = isOff ? offAdj : defAdj;
    const jitter = () => (r() - 0.5) * 0.08 + adj;
    const rat = {};
    for (const [k, v] of Object.entries(base)) {
      if (k === 'spd') rat.spd = v * (1 + (r() - 0.5) * 0.06 + adj * 0.4);
      else if (k === 'size') rat.size = v * (1 + (r() - 0.5) * 0.05);
      else rat[k] = Math.min(0.99, Math.max(0.2, v + jitter()));
    }
    roster[slot] = {
      pos, slot, num,
      first: FIRST[Math.floor(r() * FIRST.length)],
      last: LAST[Math.floor(r() * LAST.length)],
      rat,
      skin: Math.floor(r() * 6),
      visor: r() < 0.3,
      sleeves: r() < 0.45 ? (r() < 0.5 ? 'black' : 'white') : 'none',
      towel: r() < 0.35,
    };
  }
  return roster;
}

export function shortName(p) {
  return `${p.first[0]}. ${p.last}`;
}

// ---------------------------------------------------------------------------
// Playbook. Offensive positions are given as (u, v): u = yards downfield from the
// line of scrimmage (negative = backfield), v = yards to the offense's right.
// Routes are lists of [du, dOut] waypoints relative to the alignment, where
// dOut is measured toward the receiver's own sideline (mirrors automatically).

const OL_SET = { LT: [-0.75, -2.7], LG: [-0.75, -1.35], C: [-0.55, 0], RG: [-0.75, 1.35], RT: [-0.75, 2.7] };

export const FORMATIONS = {
  gunTrips: { name: 'Shotgun Trips TE', qb: [-5, 0], spots: { RB: [-5, -1.4], X: [-0.9, -13], Z: [-0.9, 14], SL: [-1.3, 8.5], TE: [-0.9, 4] } },
  gunDoubles: { name: 'Shotgun Doubles', qb: [-5, 0], spots: { RB: [-5, 1.4], X: [-0.9, -13], SL2: [-1.3, -7.5], SL: [-1.3, 7.5], Z: [-0.9, 13] } },
  gunBunch: { name: 'Shotgun Bunch', qb: [-5, 0], spots: { RB: [-5, -1.4], X: [-0.9, -13], Z: [-0.9, 8], SL: [-1.9, 9.2], TE: [-1.5, 7] } },
  singleback: { name: 'Singleback Ace', qb: [-1.2, 0], spots: { RB: [-6.5, 0], X: [-0.9, -12], Z: [-0.9, 12], SL: [-1.3, -6.5], TE: [-0.9, 4] } },
  iForm: { name: 'I-Form Pro', qb: [-1.2, 0], spots: { FB: [-4.2, 0], RB: [-6.8, 0], X: [-0.9, -12], Z: [-0.9, 12], TE: [-0.9, 4] } },
  pistol: { name: 'Pistol Strong', qb: [-3.8, 0], spots: { RB: [-6.8, 0], X: [-0.9, -12], Z: [-0.9, 12], SL: [-1.3, 7], TE: [-0.9, -4] } },
};

const R = {
  go: [[2, 0.6], [45, 1.2]],
  fade: [[3, 1.4], [45, 3.5]],
  seam: [[6, -0.6], [45, -1]],
  slant: [[3, 0], [12, -7], [30, -18]],
  quickOut: [[5, 0], [5, 12]],
  out: [[10, 0], [9.5, 12]],
  in: [[12, 0], [12, -18]],
  dig: [[14, 0], [14, -20]],
  post: [[11, 0], [35, -12]],
  corner: [[11, 0], [30, 11]],
  curl: [[11, 0], [9.5, -1.2]],
  hitch: [[6, 0], [5, -0.4]],
  comeback: [[15, 0], [13, 3]],
  drag: [[2, -1], [5, -14], [6, -30]],
  shallow: [[1.5, -1], [3.5, -12], [4, -28]],
  flat: [[1.5, 2], [3.5, 9], [4, 18]],
  swing: [[-1, 3], [1, 9], [3, 18]],
  wheel: [[0, 4], [3, 9], [30, 11]],
  angle: [[1, 3], [5, 2], [8, -6]],
  stick: [[6, 0], [6, -0.5]],
  block: null,
};

export const ROUTE_NAMES = Object.fromEntries(Object.keys(R).map((k) => [k, k]));

// type: 'pass' | 'run' | 'pa' (play-action) ; runTo for runs: v target of the hole
export const OFF_PLAYS = [
  { id: 'mesh', name: 'Mesh Spot', formation: 'gunTrips', type: 'pass', tag: 'Quick',
    routes: { X: 'go', Z: 'corner', SL: 'drag', TE: 'shallow', RB: 'flat' },
    blurb: 'Crossers underneath, corner behind it.' },
  { id: 'fourverts', name: 'Four Verticals', formation: 'gunDoubles', type: 'pass', tag: 'Deep',
    routes: { X: 'go', Z: 'go', SL: 'seam', SL2: 'seam', RB: 'swing' },
    blurb: 'Stretch the safeties deep.' },
  { id: 'slants', name: 'Bunch Slants', formation: 'gunBunch', type: 'pass', tag: 'Quick',
    routes: { X: 'slant', Z: 'slant', SL: 'out', TE: 'stick', RB: 'flat' },
    blurb: 'Fast inside throws versus man.' },
  { id: 'curlflat', name: 'Curl Flats', formation: 'gunDoubles', type: 'pass', tag: 'Short',
    routes: { X: 'curl', Z: 'curl', SL: 'flat', SL2: 'flat', RB: 'angle' },
    blurb: 'High-low the flat defender.' },
  { id: 'papost', name: 'PA Post', formation: 'singleback', type: 'pa', tag: 'Play Action',
    routes: { X: 'post', Z: 'comeback', SL: 'drag', TE: 'corner', RB: 'block' },
    blurb: 'Fake the zone, hit the post.' },
  { id: 'dagger', name: 'Dagger', formation: 'gunTrips', type: 'pass', tag: 'Deep',
    routes: { X: 'dig', Z: 'go', SL: 'seam', TE: 'dig', RB: 'swing' },
    blurb: 'Seam clears, dig sits under.' },
  { id: 'izone', name: 'Inside Zone', formation: 'pistol', type: 'run', tag: 'Run', runTo: 1.6,
    routes: { X: 'block', Z: 'block', SL: 'block', TE: 'block' },
    blurb: 'Press the A-gap and cut back.' },
  { id: 'power', name: 'Power O', formation: 'iForm', type: 'run', tag: 'Run', runTo: 3.6, lead: true,
    routes: { X: 'block', Z: 'block', TE: 'block' },
    blurb: 'Fullback leads off tackle.' },
  { id: 'stretch', name: 'Outside Stretch', formation: 'singleback', type: 'run', tag: 'Run', runTo: 7.5,
    routes: { X: 'block', Z: 'block', SL: 'block', TE: 'block' },
    blurb: 'Bounce it to the boundary.' },
  { id: 'hbdive', name: 'HB Dive', formation: 'iForm', type: 'run', tag: 'Short Yardage', runTo: -0.6, lead: true,
    routes: { X: 'block', Z: 'block', TE: 'block' },
    blurb: 'Lean on them for the sticks.' },
];

export function routeFor(name) { return R[name] || null; }

export const DEF_PLAYS = [
  { id: 'c3', name: 'Cover 3 Sky', coverage: 'cover3', blitz: [], tag: 'Zone', blurb: 'Three deep, four under.' },
  { id: 'c2', name: 'Cover 2 Sink', coverage: 'cover2', blitz: [], tag: 'Zone', blurb: 'Two deep halves, corners squat.' },
  { id: 'c1', name: 'Cover 1 Robber', coverage: 'cover1', blitz: [], tag: 'Man', blurb: 'Man under, free safety high.' },
  { id: 'c4', name: 'Quarters', coverage: 'cover4', blitz: [], tag: 'Zone', blurb: 'Four deep, take away the long ball.' },
  { id: 'c0', name: 'Cover 0 Blitz', coverage: 'cover0', blitz: ['MIKE', 'NB'], tag: 'Blitz', blurb: 'Send six. All-out man.' },
  { id: 'fire', name: 'Fire Zone 3', coverage: 'cover3', blitz: ['WILL'], tag: 'Blitz', blurb: 'Weak-side linebacker comes.' },
];

export function randomName(r = Math.random) {
  return `${pick(FIRST, r)} ${pick(LAST, r)}`;
}
