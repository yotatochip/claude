// Procedural canvas textures. Everything the game shows is generated here at
// load time so the build stays a single self-contained file.
import * as THREE from 'three';
import { mulberry32, shade, clamp } from './util.js';

export const DISPLAY_FONT = '"Big Shoulders Display", "Arial Narrow", Impact, sans-serif';
export const BLOCK_FONT = '"Big Shoulders Display", Impact, "Arial Black", sans-serif';

let maxAniso = 8;
export function setMaxAnisotropy(n) { maxAniso = n; }

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function tex(c, { srgb = true, repeat = false, aniso = true } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  if (aniso) t.anisotropy = maxAniso;
  t.needsUpdate = true;
  return t;
}

// Tileable value noise used for grass, leather and concrete.
function tileNoise(size, octaves, seed) {
  const rnd = mulberry32(seed);
  const out = new Float32Array(size * size);
  let amp = 1, total = 0;
  for (let o = 0; o < octaves; o++) {
    const cells = 4 << o;
    const grid = new Float32Array(cells * cells).map(() => rnd());
    const step = size / cells;
    for (let y = 0; y < size; y++) {
      const gy = y / step, y0 = Math.floor(gy), fy = gy - y0;
      const sy = fy * fy * (3 - 2 * fy);
      for (let x = 0; x < size; x++) {
        const gx = x / step, x0 = Math.floor(gx), fx = gx - x0;
        const sx = fx * fx * (3 - 2 * fx);
        const a = grid[(y0 % cells) * cells + (x0 % cells)];
        const b = grid[(y0 % cells) * cells + ((x0 + 1) % cells)];
        const c = grid[((y0 + 1) % cells) * cells + (x0 % cells)];
        const d = grid[((y0 + 1) % cells) * cells + ((x0 + 1) % cells)];
        out[y * size + x] += amp * ((a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy);
      }
    }
    total += amp;
    amp *= 0.55;
  }
  for (let i = 0; i < out.length; i++) out[i] /= total;
  return out;
}

function normalFromHeight(h, size, strength) {
  const c = canvas(size, size);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const l = h[y * size + ((x - 1 + size) % size)], r = h[y * size + ((x + 1) % size)];
      const u = h[((y - 1 + size) % size) * size + x], d = h[((y + 1) % size) * size + x];
      let nx = (l - r) * strength, ny = (u - d) * strength, nz = 1;
      const len = Math.hypot(nx, ny, nz);
      nx /= len; ny /= len; nz /= len;
      const i = (y * size + x) * 4;
      img.data[i] = (nx * 0.5 + 0.5) * 255;
      img.data[i + 1] = (ny * 0.5 + 0.5) * 255;
      img.data[i + 2] = (nz * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

// Grass close-up detail: blade speckle (color multiplier around 0.5 gray) + normal map.
export function grassDetailTextures() {
  const size = 512;
  const rnd = mulberry32(7);
  const low = tileNoise(size, 5, 11);
  const h = new Float32Array(size * size);
  const c = canvas(size, size);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < size * size; i++) h[i] = low[i] * 0.4;
  // Scatter thousands of short blades as height spikes.
  for (let b = 0; b < 38000; b++) {
    const x = Math.floor(rnd() * size), y = Math.floor(rnd() * size);
    const len = 2 + Math.floor(rnd() * 5);
    const ang = rnd() * Math.PI;
    const v = 0.4 + rnd() * 0.6;
    for (let k = 0; k < len; k++) {
      const px = (x + Math.round(Math.cos(ang) * k) + size) % size;
      const py = (y + Math.round(Math.sin(ang) * k) + size) % size;
      h[py * size + px] = Math.max(h[py * size + px], v * (1 - k / (len + 1)) + 0.2);
    }
  }
  for (let i = 0; i < size * size; i++) {
    const v = clamp(h[i], 0, 1);
    // Color multiplier: darker in the crevices, bright tips, slight yellow-green shift.
    const base = 0.38 + v * 0.26 + (low[i] - 0.5) * 0.12;
    img.data[i * 4] = clamp(base * 255 * 0.98, 0, 255);
    img.data[i * 4 + 1] = clamp(base * 255 * 1.02, 0, 255);
    img.data[i * 4 + 2] = clamp(base * 255 * 0.94, 0, 255);
    img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  const color = tex(c, { srgb: false, repeat: true });
  const normal = tex(normalFromHeight(h, size, 3.2), { srgb: false, repeat: true });
  return { color, normal };
}

// Perforated jersey mesh: a staggered grid of tiny holes. Tiles many times
// across the torso.
let fabricNormalCache = null;
export function fabricNormalTexture() {
  if (fabricNormalCache) return fabricNormalCache;
  const size = 64;
  const h = new Float32Array(size * size).fill(1);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const row = Math.floor(y / 8), ox = row % 2 ? 4 : 0;
      const dx = ((x + ox) % 8) - 3.5, dy = (y % 8) - 3.5;
      const d = Math.hypot(dx, dy);
      if (d < 2.4) h[y * size + x] = 0.35 + d * 0.27;
    }
  }
  const t = tex(normalFromHeight(h, size, 2.2), { srgb: false, repeat: true });
  t.repeat.set(48, 22);
  fabricNormalCache = t;
  return t;
}

// Knit/spandex weave for pants, socks and sleeves.
let knitNormalCache = null;
export function knitNormalTexture() {
  if (knitNormalCache) return knitNormalCache;
  const size = 64;
  const h = new Float32Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const rib = Math.sin((x / size) * Math.PI * 2 * 16) * 0.5 + 0.5;
      const loop = Math.sin(((y + (x % 8 < 4 ? 2 : 0)) / size) * Math.PI * 2 * 16) * 0.5 + 0.5;
      h[y * size + x] = rib * 0.6 + loop * 0.4;
    }
  }
  const t = tex(normalFromHeight(h, size, 1.2), { srgb: false, repeat: true });
  t.repeat.set(10, 10);
  knitNormalCache = t;
  return t;
}

// The painted field: 130 x 64 yards (field + white border + team area).
export const FIELD_TEX = { w: 130, h: 64, ppy: 32 };

export function fieldTexture(home) {
  const { w, h, ppy } = FIELD_TEX;
  const W = w * ppy, H = h * ppy;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  const X = (x) => (x + w / 2) * ppy;
  const Z = (z) => (z + h / 2) * ppy;
  const HW = 160 / 6;

  // Base turf beyond the field (team areas), slightly duller.
  ctx.fillStyle = '#3b6a2a';
  ctx.fillRect(0, 0, W, H);

  // Mowing stripes, 5 yards wide, across the playing field and end zones.
  for (let i = -12; i < 12; i++) {
    const x0 = i * 5;
    ctx.fillStyle = (i & 1) ? '#40702f' : '#3b692c';
    ctx.fillRect(X(x0), Z(-HW), 5 * ppy + 1, HW * 2 * ppy);
  }

  // End zones: solid, matte home-color paint.
  for (const s of [-1, 1]) {
    const x0 = s < 0 ? -60 : 50;
    ctx.fillStyle = shade(home.primary, -0.08);
    ctx.fillRect(X(x0), Z(-HW), 10 * ppy, HW * 2 * ppy);
    // End zone lettering reads along the end line.
    const word = s < 0 ? home.school.toUpperCase() : home.name.toUpperCase();
    ctx.save();
    ctx.translate(X(x0 + 5), Z(0));
    ctx.rotate(s < 0 ? -Math.PI / 2 : Math.PI / 2);
    let size = 5.6 * ppy;
    ctx.font = `900 ${size}px ${BLOCK_FONT}`;
    const maxW = 44 * ppy;
    const m = ctx.measureText(word).width;
    if (m > maxW) { size *= maxW / m; ctx.font = `900 ${size}px ${BLOCK_FONT}`; }
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round';
    ctx.lineWidth = 0.55 * ppy;
    ctx.strokeStyle = home.secondary === '#ffffff' ? home.trim : home.secondary;
    ctx.strokeText(word, 0, 0);
    ctx.fillStyle = '#ffffff';
    ctx.fillText(word, 0, 0);
    ctx.restore();
  }

  // Pixel-level turf variation: wear near the hashes, patchy color everywhere.
  const img = ctx.getImageData(0, 0, W, H);
  const d = img.data;
  const rnd = mulberry32(42);
  const big = tileNoise(256, 4, 5);
  for (let y = 0; y < H; y++) {
    const zW = y / ppy - h / 2;
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      const xW = x / ppy - w / 2;
      const n = big[((y >> 3) & 255) * 256 + ((x >> 3) & 255)];
      let f = 0.9 + n * 0.2 + (rnd() - 0.5) * 0.12;
      // Wear between the hashes in the middle of the field.
      if (Math.abs(zW) < 8 && Math.abs(xW) < 45) f *= 0.97 + 0.03 * Math.abs(zW) / 8;
      d[i] = clamp(d[i] * f * (1 + (n - 0.5) * 0.1), 0, 255);
      d[i + 1] = clamp(d[i + 1] * f, 0, 255);
      d[i + 2] = clamp(d[i + 2] * f * 0.98, 0, 255);
    }
  }
  ctx.putImageData(img, 0, 0);

  // Paint: slightly translucent white so grass texture reads through.
  const paint = 'rgba(246,246,240,0.93)';
  ctx.fillStyle = paint;
  const line = (x0, z0, x1, z1) => ctx.fillRect(X(x0), Z(z0), (x1 - x0) * ppy, (z1 - z0) * ppy);
  // Boundary: 2-yard white border outside sidelines and end lines.
  line(-62, -HW - 2, 62, -HW);
  line(-62, HW, 62, HW + 2);
  line(-62, -HW - 2, -60, HW + 2);
  line(60, -HW - 2, 62, HW + 2);
  // Coaching box / restraining lines.
  ctx.fillStyle = 'rgba(240,200,40,0.9)';
  for (const s of [-1, 1]) {
    const zz = s * (HW + 6);
    for (let x = -25; x < 25; x += 1.6) line(x, zz - 0.07, x + 0.9, zz + 0.07);
  }
  ctx.fillStyle = paint;
  // Yard lines every 5 yards, goal lines doubled width.
  for (let yl = -50; yl <= 50; yl += 5) {
    const lw = Math.abs(yl) === 50 ? 0.22 : 0.12;
    line(yl - lw / 2, -HW, yl + lw / 2, HW);
  }
  // One-yard ticks at sidelines, near the numbers and at the hashes.
  const hz = HW - 20;
  for (let yl = -49; yl <= 49; yl++) {
    if (yl % 5 === 0) continue;
    for (const s of [-1, 1]) {
      line(yl - 0.06, s > 0 ? HW - 0.9 : -HW + 0.2, yl + 0.06, s > 0 ? HW - 0.2 : -HW + 0.9);
      line(yl - 0.06, s * hz - 0.33, yl + 0.06, s * hz + 0.33);
      line(yl - 0.06, s > 0 ? HW - 11.8 : -HW + 11.2, yl + 0.06, s > 0 ? HW - 11.2 : -HW + 11.8);
    }
  }
  // Try lines (the 3-yard PAT mark).
  for (const s of [-1, 1]) line(s * 47 - 0.06, -0.5, s * 47 + 0.06, 0.5);

  // Yard numbers: 2 yards tall, tops 9 yards in from each sideline.
  const numH = 2 * ppy;
  ctx.font = `800 ${numH * 1.18}px ${BLOCK_FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  for (let n = 10; n <= 50; n += 10) {
    for (const s of [-1, 1]) {
      const xl = s * (50 - n);
      if (n === 50 && s > 0) continue;
      for (const side of [-1, 1]) {
        ctx.save();
        const zc = side * (HW - 8);
        ctx.translate(X(xl), Z(zc));
        if (side < 0) ctx.rotate(Math.PI);
        const label = String(n);
        // Split digits around the yard line like a real field.
        ctx.fillStyle = paint;
        ctx.textBaseline = 'middle';
        ctx.fillText(label[0], -0.95 * ppy, 0.05 * ppy);
        ctx.fillText(label[1], 0.95 * ppy, 0.05 * ppy);
        if (n !== 50) {
          // Arrow points toward the nearer goal line.
          const toGoal = (xl < 0 ? -1 : 1) * (side < 0 ? -1 : 1);
          ctx.beginPath();
          const ax = toGoal * 2.15 * ppy, ay = -0.55 * ppy;
          ctx.moveTo(ax + toGoal * 0.55 * ppy, ay);
          ctx.lineTo(ax, ay - 0.28 * ppy);
          ctx.lineTo(ax, ay + 0.28 * ppy);
          ctx.closePath();
          ctx.fill();
        }
        ctx.restore();
      }
    }
  }

  // Midfield logo.
  ctx.save();
  ctx.translate(X(0), Z(0));
  ctx.globalAlpha = 0.95;
  ctx.beginPath();
  ctx.arc(0, 0, 5.2 * ppy, 0, Math.PI * 2);
  ctx.fillStyle = home.secondary === '#ffffff' ? '#f4f4f2' : home.secondary;
  ctx.fill();
  ctx.beginPath();
  ctx.arc(0, 0, 4.6 * ppy, 0, Math.PI * 2);
  ctx.fillStyle = home.primary;
  ctx.fill();
  ctx.font = `900 ${6.4 * ppy}px ${BLOCK_FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineWidth = 0.4 * ppy;
  ctx.strokeStyle = home.trim;
  ctx.strokeText(home.letter, 0, 0.3 * ppy);
  ctx.fillStyle = home.secondary === '#ffffff' ? '#ffffff' : home.secondary;
  ctx.fillText(home.letter, 0, 0.3 * ppy);
  ctx.restore();

  // Paint grain: knock a little alpha out of the lines.
  const t = tex(c);
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  return t;
}

// Jersey texture for the lathe torso. u=0.25 is the back, u=0.75 the front.
export function jerseyTexture(kit, number, lastName) {
  const W = 512, H = 256;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = kit.jersey;
  ctx.fillRect(0, 0, W, H);
  // Fabric mesh texture.
  const rnd = mulberry32(number * 31 + 7);
  for (let i = 0; i < 2500; i++) {
    ctx.fillStyle = `rgba(${rnd() < 0.5 ? '0,0,0' : '255,255,255'},${0.025 + rnd() * 0.03})`;
    ctx.fillRect(rnd() * W, rnd() * H, 1.5, 1.5);
  }
  // Side panels and yoke stripes.
  ctx.fillStyle = kit.panel;
  for (const u of [0, 0.5, 1]) ctx.fillRect(u * W - W * 0.033, H * 0.28, W * 0.066, H * 0.72);
  ctx.fillStyle = kit.stripe;
  ctx.fillRect(0, H * 0.1, W, H * 0.03);
  ctx.fillStyle = kit.stripe2;
  ctx.fillRect(0, H * 0.135, W, H * 0.015);
  // Collar.
  ctx.fillStyle = kit.stripe;
  ctx.fillRect(0, 0, W, H * 0.035);

  // Baked shading: fabric falls into shadow at the sides and where it tucks in.
  for (const u of [0, 0.5, 1]) {
    const g = ctx.createLinearGradient(u * W - W * 0.16, 0, u * W + W * 0.16, 0);
    g.addColorStop(0, 'rgba(0,0,0,0)');
    g.addColorStop(0.5, 'rgba(0,0,0,0.22)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(u * W - W * 0.16, 0, W * 0.32, H);
  }
  const tuck = ctx.createLinearGradient(0, H * 0.82, 0, H);
  tuck.addColorStop(0, 'rgba(0,0,0,0)');
  tuck.addColorStop(1, 'rgba(0,0,0,0.3)');
  ctx.fillStyle = tuck;
  ctx.fillRect(0, H * 0.82, W, H * 0.18);
  // A few soft creases across the belly and back.
  const rnd2 = mulberry32(number * 7 + 3);
  for (let i = 0; i < 7; i++) {
    const y = H * (0.6 + rnd2() * 0.3), x = rnd2() * W;
    const g = ctx.createLinearGradient(0, y - 6, 0, y + 6);
    g.addColorStop(0, 'rgba(255,255,255,0)');
    g.addColorStop(0.5, 'rgba(0,0,0,0.12)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(x - 40, y - 6, 80, 12);
  }

  const stretch = 0.62; // compensate for the torso being wider than tall in UV space
  const drawNum = (cx, cy, size) => {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.scale(stretch, 1);
    ctx.font = `800 ${size}px ${BLOCK_FONT}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineJoin = 'round';
    ctx.lineWidth = size * 0.11;
    ctx.strokeStyle = kit.numOutline;
    ctx.strokeText(String(number), 0, 0);
    ctx.fillStyle = kit.num;
    ctx.fillText(String(number), 0, 0);
    ctx.restore();
  };
  drawNum(W * 0.75, H * 0.5, H * 0.48);
  drawNum(W * 0.25, H * 0.55, H * 0.52);
  // Nameplate across the shoulders on the back.
  ctx.save();
  ctx.translate(W * 0.25, H * 0.235);
  ctx.scale(stretch * 0.9, 1);
  ctx.font = `700 ${H * 0.085}px ${DISPLAY_FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = kit.num;
  ctx.fillText(lastName.toUpperCase().split('').join(String.fromCharCode(8202)), 0, 0);
  ctx.restore();
  return tex(c);
}

export function sleeveTexture(kit) {
  const c = canvas(128, 128);
  const ctx = c.getContext('2d');
  ctx.fillStyle = kit.jersey;
  ctx.fillRect(0, 0, 128, 128);
  ctx.fillStyle = kit.stripe;
  ctx.fillRect(0, 74, 128, 14);
  ctx.fillStyle = kit.stripe2;
  ctx.fillRect(0, 92, 128, 6);
  return tex(c);
}

export function pantsTexture(kit) {
  const c = canvas(256, 256);
  const ctx = c.getContext('2d');
  ctx.fillStyle = kit.pants;
  ctx.fillRect(0, 0, 256, 256);
  const rnd = mulberry32(3);
  for (let i = 0; i < 3000; i++) {
    ctx.fillStyle = `rgba(0,0,0,${rnd() * 0.04})`;
    ctx.fillRect(rnd() * 256, rnd() * 256, 2, 2);
  }
  // Side stripe down the outside of the leg (u ~ 0.25 / 0.75 on the cylinders).
  ctx.fillStyle = kit.pantStripe;
  for (const u of [0.25, 0.75]) ctx.fillRect(u * 256 - 9, 0, 18, 256);
  ctx.fillStyle = kit.stripe2;
  for (const u of [0.25, 0.75]) ctx.fillRect(u * 256 - 3, 0, 6, 256);
  return tex(c);
}

// Helmet shell texture. Sphere UV with phiStart = 3π/2: u=0.5 front, u=0/1 back,
// u=0.25 / 0.75 the sides.
export function helmetTexture(team) {
  const W = 1024, H = 512;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = team.helmet;
  ctx.fillRect(0, 0, W, H);
  const stripeCol = team.helmet === team.secondary ? team.primary : team.secondary;
  // Center stripe over the crown (front and back meridians).
  for (const u of [0, 0.5, 1]) {
    ctx.fillStyle = stripeCol;
    ctx.fillRect(u * W - 14, 0, 28, H * 0.62);
    ctx.fillStyle = team.trim;
    ctx.fillRect(u * W - 22, 0, 5, H * 0.62);
    ctx.fillRect(u * W + 17, 0, 5, H * 0.62);
  }
  // Side logos.
  for (const u of [0.25, 0.75]) {
    ctx.save();
    ctx.translate(u * W, H * 0.47);
    ctx.scale(0.62, 1);
    ctx.beginPath();
    ctx.arc(0, 0, 70, 0, Math.PI * 2);
    ctx.fillStyle = stripeCol;
    ctx.fill();
    ctx.lineWidth = 9;
    ctx.strokeStyle = team.trim;
    ctx.stroke();
    ctx.font = `900 112px ${BLOCK_FONT}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = team.helmet === stripeCol ? team.primary : team.helmet;
    ctx.fillText(team.letter, 0, 6);
    ctx.restore();
  }
  return tex(c);
}

export const SKIN_TONES = ['#f1c7a5', '#d9a07a', '#b97850', '#8d5636', '#6a3d24', '#4a2a19'];

export function faceTexture(tone) {
  const W = 256, H = 128;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = tone;
  ctx.fillRect(0, 0, W, H);
  // Sphere u=0.5 is the front of the head (same convention as the helmet).
  const cx = W * 0.5;
  // Soft shading: darker toward the sides and under the brow, warmer cheeks.
  const side = ctx.createLinearGradient(cx - 64, 0, cx + 64, 0);
  side.addColorStop(0, 'rgba(0,0,0,0.35)');
  side.addColorStop(0.3, 'rgba(0,0,0,0)');
  side.addColorStop(0.7, 'rgba(0,0,0,0)');
  side.addColorStop(1, 'rgba(0,0,0,0.35)');
  ctx.fillStyle = side;
  ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = 'rgba(160,60,40,0.12)';
  for (const s of [-1, 1]) { ctx.beginPath(); ctx.ellipse(cx + s * 17, H * 0.62, 9, 6, 0, 0, Math.PI * 2); ctx.fill(); }
  // Brow ridge shadow and eye sockets.
  ctx.fillStyle = 'rgba(0,0,0,0.28)';
  ctx.fillRect(cx - 30, H * 0.4, 60, 7);
  for (const s of [-1, 1]) {
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.beginPath(); ctx.ellipse(cx + s * 12, H * 0.48, 8, 5, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#e8e2d8';
    ctx.beginPath(); ctx.ellipse(cx + s * 12, H * 0.48, 4.2, 2.2, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#2a1a10';
    ctx.beginPath(); ctx.arc(cx + s * 12, H * 0.48, 1.9, 0, Math.PI * 2); ctx.fill();
    // Eye black.
    ctx.fillStyle = 'rgba(12,12,12,0.92)';
    ctx.beginPath(); ctx.ellipse(cx + s * 13, H * 0.565, 7.5, 2.4, s * 0.12, 0, Math.PI * 2); ctx.fill();
    // Brows.
    ctx.fillStyle = shade(tone, -0.6);
    ctx.fillRect(cx + s * 12 - 6, H * 0.41, 12, 2);
  }
  // Nose and mouth.
  ctx.fillStyle = 'rgba(0,0,0,0.22)';
  ctx.fillRect(cx - 3.5, H * 0.5, 2.5, 12);
  ctx.fillStyle = shade(tone, -0.25);
  ctx.beginPath(); ctx.ellipse(cx, H * 0.6, 4.5, 2.6, 0, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = shade(tone, -0.45);
  ctx.fillRect(cx - 7, H * 0.69, 14, 2);
  ctx.fillStyle = 'rgba(0,0,0,0.18)';
  ctx.fillRect(cx - 9, H * 0.72, 18, 3);
  return tex(c);
}

export function footballTexture() {
  const W = 512, H = 256;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#6b3519';
  ctx.fillRect(0, 0, W, H);
  const rnd = mulberry32(9);
  // Pebbled leather.
  for (let i = 0; i < 14000; i++) {
    const v = rnd();
    ctx.fillStyle = v < 0.5 ? `rgba(30,12,4,${0.15 + rnd() * 0.2})` : `rgba(160,90,50,${0.08 + rnd() * 0.12})`;
    ctx.beginPath();
    ctx.arc(rnd() * W, rnd() * H, 0.8 + rnd() * 1.2, 0, Math.PI * 2);
    ctx.fill();
  }
  // Seams along four panels.
  ctx.strokeStyle = 'rgba(25,10,3,0.8)';
  ctx.lineWidth = 2;
  for (let k = 0; k < 4; k++) {
    ctx.beginPath();
    ctx.moveTo((k / 4) * W, 0);
    ctx.lineTo((k / 4) * W, H);
    ctx.stroke();
  }
  // College stripes near both tips (v ~ 0.17 and 0.83 → y ~ 0.17H / 0.83H).
  ctx.fillStyle = '#f4f2ea';
  ctx.fillRect(0, H * 0.18, W, H * 0.045);
  ctx.fillRect(0, H * 0.775, W, H * 0.045);
  // Laces on top (u ~ 0.5).
  ctx.fillStyle = '#f2f0e8';
  ctx.fillRect(W * 0.5 - 3, H * 0.33, 6, H * 0.34);
  for (let i = 0; i < 8; i++) ctx.fillRect(W * 0.5 - 12, H * 0.35 + i * H * 0.04, 24, 5);
  return tex(c);
}

// Crowd fill for the stands: dense speckle of shirt colors.
export function crowdFillTexture(colors) {
  const W = 512, H = 256;
  const c = canvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#26262a';
  ctx.fillRect(0, 0, W, H);
  const rnd = mulberry32(17);
  for (let i = 0; i < 9000; i++) {
    ctx.fillStyle = colors[Math.floor(rnd() * colors.length)];
    const x = rnd() * W, y = rnd() * H;
    ctx.fillRect(x, y, 3 + rnd() * 3, 4 + rnd() * 4);
    ctx.fillStyle = SKIN_TONES[Math.floor(rnd() * SKIN_TONES.length)];
    ctx.fillRect(x + 1, y - 2, 2.5, 2.5);
  }
  return tex(c, { repeat: true });
}

export function concreteTexture() {
  const size = 256;
  const n = tileNoise(size, 5, 23);
  const c = canvas(size, size);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < size * size; i++) {
    const v = 120 + n[i] * 70;
    img.data[i * 4] = v; img.data[i * 4 + 1] = v; img.data[i * 4 + 2] = v * 1.02; img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return tex(c, { repeat: true });
}

export function blobShadowTexture() {
  const c = canvas(128, 128);
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(64, 64, 4, 64, 64, 64);
  g.addColorStop(0, 'rgba(0,0,0,0.55)');
  g.addColorStop(0.5, 'rgba(0,0,0,0.25)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 128, 128);
  return tex(c, { srgb: false });
}

export function glowTexture() {
  const c = canvas(64, 64);
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.25, 'rgba(255,250,235,0.6)');
  g.addColorStop(1, 'rgba(255,240,220,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  return tex(c);
}

// Kits for a team in a given role ('home' wears color, 'away' wears white).
export function kitFor(team, role) {
  const lightSecondary = team.secondary === '#ffffff' || team.secondary === '#c9c9d1';
  if (role === 'home') {
    return {
      jersey: team.primary,
      panel: shade(team.primary, -0.12),
      num: lightSecondary ? '#ffffff' : team.secondary,
      numOutline: team.trim === '#ffffff' && !lightSecondary ? '#ffffff' : shade(team.primary, -0.5),
      stripe: team.secondary,
      stripe2: team.trim,
      pants: lightSecondary ? '#f2f2f0' : team.secondary,
      pantStripe: team.primary,
      socks: team.primary,
      glove: team.secondary === '#ffffff' ? '#f2f2f2' : team.secondary,
      cleat: '#111111',
    };
  }
  return {
    jersey: '#f4f4f2',
    panel: '#e6e6e4',
    num: team.primary,
    numOutline: team.secondary === '#ffffff' ? team.trim : team.secondary,
    stripe: team.primary,
    stripe2: team.secondary === '#ffffff' ? team.trim : team.secondary,
    pants: team.primary,
    pantStripe: '#f4f4f2',
    socks: '#f4f4f2',
    glove: '#f2f2f2',
    cleat: '#f2f2f2',
  };
}
