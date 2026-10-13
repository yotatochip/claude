// Small math + randomness helpers shared across the game.

export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smooth = (t) => t * t * (3 - 2 * t);
export const damp = (a, b, rate, dt) => lerp(a, b, 1 - Math.exp(-rate * dt));
export const sign = (v) => (v < 0 ? -1 : 1);

export function angleDiff(a, b) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

export function dampAngle(a, b, rate, dt) {
  return a + angleDiff(a, b) * (1 - Math.exp(-rate * dt));
}

// Deterministic PRNG so rosters are stable between sessions.
export function mulberry32(seed) {
  let s = seed >>> 0;
  return function () {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashString(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export const rand = (lo = 0, hi = 1) => lo + Math.random() * (hi - lo);
export const randInt = (lo, hi) => Math.floor(rand(lo, hi + 1));
export const pick = (arr, r = Math.random) => arr[Math.floor(r() * arr.length)];
export const chance = (p) => Math.random() < p;

export function gaussian() {
  let u = 0, v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

export function weightedPick(items, weightFn) {
  let total = 0;
  for (const it of items) total += Math.max(0, weightFn(it));
  let r = Math.random() * total;
  for (const it of items) {
    r -= Math.max(0, weightFn(it));
    if (r <= 0) return it;
  }
  return items[items.length - 1];
}

// Hex "#rrggbb" → {r,g,b} 0..255
export function hexToRgb(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

export function shade(hex, amt) {
  const { r, g, b } = hexToRgb(hex);
  const f = (c) => clamp(Math.round(amt < 0 ? c * (1 + amt) : c + (255 - c) * amt), 0, 255);
  return '#' + [f(r), f(g), f(b)].map((c) => c.toString(16).padStart(2, '0')).join('');
}

export function luminance(hex) {
  const { r, g, b } = hexToRgb(hex);
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

// Field geometry, in yards. x runs end line to end line, z sideline to sideline.
export const FIELD = {
  halfLength: 60,
  goal: 50,
  halfWidth: 160 / 6, // 53⅓ yards wide
  hash: 160 / 6 - 20, // college hashes sit 20 yards in from each sideline
};

// Convert a world x to the "own 25" style yard line text for the team attacking in `dir`.
export function yardLineLabel(x, dir) {
  const fromOwnGoal = (x + FIELD.goal * dir) * dir; // 0..100
  const yl = Math.round(fromOwnGoal);
  if (yl === 50) return '50';
  if (yl < 50) return `OWN ${Math.max(1, yl)}`;
  return `OPP ${Math.max(1, 100 - yl)}`;
}

export function yardsToGoal(x, dir) {
  return FIELD.goal - x * dir;
}
