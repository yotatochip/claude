// The bowl: stands, crowd, light rigs, video board, LED ribbons and sideline life.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { crowdFillTexture, concreteTexture, SKIN_TONES, DISPLAY_FONT, glowTexture, kitFor } from './textures.js';
import { mulberry32, FIELD, shade } from './util.js';

const A = 73, B = 43, RC = 24; // inner wall of the bowl (half extents + corner radius)

// Rounded-rectangle path with outward normals. Starts at the middle of the +z side.
function basePath() {
  const pts = [];
  const push = (x, z, nx, nz) => pts.push({ x, z, nx, nz });
  const sx = A - RC, sz = B - RC;
  const corners = [
    { cx: sx, cz: sz, a0: Math.PI / 2, a1: 0 },
    { cx: sx, cz: -sz, a0: 0, a1: -Math.PI / 2 },
    { cx: -sx, cz: -sz, a0: -Math.PI / 2, a1: -Math.PI },
    { cx: -sx, cz: sz, a0: Math.PI, a1: Math.PI / 2 },
  ];
  // +z side from x=0 to x=sx
  const straight = (x0, z0, x1, z1, nx, nz) => {
    const len = Math.hypot(x1 - x0, z1 - z0);
    const n = Math.max(1, Math.round(len / 2));
    for (let i = 0; i < n; i++) {
      const t = i / n;
      push(x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, nx, nz);
    }
  };
  const arc = (c) => {
    const n = 18;
    for (let i = 0; i < n; i++) {
      const a = c.a0 + (c.a1 - c.a0) * (i / n);
      push(c.cx + Math.cos(a) * RC, c.cz + Math.sin(a) * RC, Math.cos(a), Math.sin(a));
    }
  };
  straight(0, B, sx, B, 0, 1);
  arc(corners[0]);
  straight(A, sz, A, -sz, 1, 0);
  arc(corners[1]);
  straight(sx, -B, -sx, -B, 0, -1);
  arc(corners[2]);
  straight(-A, -sz, -A, sz, -1, 0);
  arc(corners[3]);
  straight(-sx, B, 0, B, 0, 1);
  pts.push({ ...pts[0] });
  let acc = 0;
  for (let i = 0; i < pts.length; i++) {
    if (i > 0) acc += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z);
    pts[i].s = acc;
  }
  return pts;
}

// Sweep a 2D profile [(offset, height, materialIndex)] along a path.
function sweep(path, profile, uScale = 1 / 6) {
  const positions = [], uvs = [], indices = [];
  const groups = new Map();
  const segIndex = [];
  for (let k = 0; k < profile.length - 1; k++) {
    const [o0, h0] = profile[k], [o1, h1, mat = 0] = profile[k + 1];
    const base = positions.length / 3;
    const led = mat === 2 || mat === 3;
    for (let i = 0; i < path.length; i++) {
      const p = path[i];
      let end = 0;
      for (const [o, h] of [[o0, h0], [o1, h1]]) {
        positions.push(p.x + p.nx * o, h, p.z + p.nz * o);
        // LED faces get a 0..1 band and mirrored u so text reads from the field.
        uvs.push(led ? -p.s * uScale : p.s * uScale, led ? end : (h + o) * 0.25);
        end = 1;
      }
    }
    const tri = [];
    for (let i = 0; i < path.length - 1; i++) {
      const a = base + i * 2, b = a + 1, c = a + 2, d = a + 3;
      tri.push(a, b, c, b, d, c);
    }
    segIndex.push({ mat, tri });
  }
  // Order indices by material so we can use geometry groups.
  const byMat = [...new Set(segIndex.map((s) => s.mat))].sort();
  for (const m of byMat) {
    const start = indices.length;
    for (const s of segIndex) if (s.mat === m) indices.push(...s.tri);
    groups.set(m, [start, indices.length - start]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  g.setIndex(indices);
  for (const [m, [start, count]] of groups) g.addGroup(start, count, m);
  g.computeVertexNormals();
  return g;
}

function straightPath(x0, x1, z, nz) {
  const pts = [];
  const n = Math.round(Math.abs(x1 - x0) / 2);
  for (let i = 0; i <= n; i++) {
    const x = x0 + (x1 - x0) * (i / n);
    pts.push({ x, z, nx: 0, nz, s: Math.abs(x - x0) });
  }
  return pts;
}

// Walk an offset path placing seats.
function seatsAlong(path, offset, spacing, cb) {
  let carry = spacing * 0.5;
  for (let i = 0; i < path.length - 1; i++) {
    const p = path[i], q = path[i + 1];
    const ax = p.x + p.nx * offset, az = p.z + p.nz * offset;
    const bx = q.x + q.nx * offset, bz = q.z + q.nz * offset;
    const len = Math.hypot(bx - ax, bz - az);
    let d = carry;
    while (d < len) {
      const t = d / len;
      cb(ax + (bx - ax) * t, az + (bz - az) * t, p.nx + (q.nx - p.nx) * t, p.nz + (q.nz - p.nz) * t, p.s + (q.s - p.s) * t);
      d += spacing;
    }
    carry = d - len;
  }
}

// Fans: shaped bodies with shirts, pants, hair and arms that go up on big plays.
// Part ids: 0 shirt, 1 skin, 2 hair (or helmet), 3 pants.
const CROWD_VERT = /* glsl */`
  attribute vec3 aShirt;
  attribute vec3 aSkin;
  attribute vec3 aPants;
  attribute vec3 aHelmet;
  attribute vec2 aAnim; // phase, energy
  attribute float aPart;
  attribute float aArm;
  uniform float uTime;
  uniform float uExcite;
  uniform float uHelmets;
  uniform vec3 uLightDir;
  uniform vec3 uLightCol;
  uniform vec3 uAmbient;
  varying vec3 vCol;
  varying float vFog;
  float hash(float n) { return fract(sin(n * 91.345) * 47453.5453); }
  void main() {
    vec3 p = position;
    float id = aAnim.x;
    float e = clamp(uExcite * aAnim.y, 0.0, 1.5);
    // Arms: a share of the crowd throws them up when the stadium gets loud.
    if (aArm != 0.0) {
      float lift = clamp((e - 0.3) * 1.8, 0.0, 1.0) * step(0.4, hash(id * 13.0));
      float idle = hash(id * 5.0) > 0.86 ? 0.35 : 0.0; // a few clap or hold phones up
      float a = aArm * (max(lift * 2.75, idle * (1.6 + sin(uTime * 3.0 + id * 40.0) * 0.2)) + lift * sin(uTime * 7.0 + id * 60.0) * 0.18);
      vec2 pivot = vec2(aArm * 0.235, 1.43);
      vec2 d = p.xy - pivot;
      float c = cos(a), s = sin(a);
      p.xy = pivot + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
    }
    float bounce = max(0.0, sin(uTime * (7.0 + id * 3.0) + id * 40.0));
    p.y += bounce * e * 0.26 + sin(uTime * 1.3 + id * 30.0) * 0.015;
    p.x += sin(uTime * 0.7 + id * 17.0) * 0.03;
    vec4 wp = modelMatrix * instanceMatrix * vec4(p, 1.0);
    vec3 n = normalize(mat3(modelMatrix * instanceMatrix) * normal);
    float diff = max(dot(n, uLightDir), 0.0);
    // Hair: black, dark brown, brown, blonde, gray, or a hat in the shirt color.
    float h = hash(id * 3.0);
    vec3 hair = h < 0.35 ? vec3(0.02, 0.018, 0.016) : h < 0.6 ? vec3(0.07, 0.04, 0.025) : h < 0.75 ? vec3(0.16, 0.09, 0.05)
              : h < 0.85 ? vec3(0.45, 0.33, 0.16) : h < 0.92 ? vec3(0.32, 0.31, 0.3) : aShirt;
    vec3 base = aPart < 0.5 ? aShirt : aPart < 1.5 ? aSkin : aPart < 2.5 ? hair : aPants;
    // Players on the sideline wear their helmets.
    if (uHelmets > 0.5 && position.y > 1.47) base = aHelmet;
    // Lower body sits in the shadow of the row in front.
    float occ = mix(0.45, 1.0, smoothstep(0.35, 1.3, position.y));
    float jitter = 0.78 + 0.3 * hash(id * 17.0);
    float sky = 0.65 + 0.35 * n.y;
    vCol = base * (uAmbient * sky + uLightCol * diff) * occ * jitter;
    // Phone and camera flashes pop around the bowl, more when it's loud.
    float flashSeed = hash(id * 7.0 + floor(uTime * 12.0));
    float flash = step(1.0 - (0.0006 + e * 0.004), flashSeed) * step(0.5, abs(aArm)) * step(0.5, aPart);
    vCol += vec3(4.0) * flash;
    vec4 mv = viewMatrix * wp;
    vFog = smoothstep(140.0, 360.0, -mv.z);
    gl_Position = projectionMatrix * mv;
  }
`;
const CROWD_FRAG = /* glsl */`
  uniform vec3 uFogColor;
  varying vec3 vCol;
  varying float vFog;
  void main() {
    gl_FragColor = vec4(mix(vCol, uFogColor, vFog * 0.45), 1.0);
  }
`;

function tag(g, part, arm = 0) {
  g = g.index ? g.toNonIndexed() : g;
  g.deleteAttribute('uv');
  const n = g.attributes.position.count;
  g.setAttribute('aPart', new THREE.Float32BufferAttribute(new Float32Array(n).fill(part), 1));
  g.setAttribute('aArm', new THREE.Float32BufferAttribute(new Float32Array(n).fill(arm), 1));
  return g;
}

// ~80 triangles: legs, tapered torso, round head with hair, two-piece arms.
function personGeometry(height = 1.0) {
  const parts = [];
  const legs = new THREE.BoxGeometry(0.3, 0.86, 0.17);
  legs.translate(0, 0.43, 0);
  parts.push(tag(legs, 3));
  const torso = new THREE.CylinderGeometry(0.2, 0.155, 0.6, 6, 1, false);
  torso.scale(1, 1, 0.62);
  torso.translate(0, 0.86 + 0.3 * height, 0);
  parts.push(tag(torso, 0));
  const head = new THREE.SphereGeometry(0.105, 6, 4);
  head.scale(0.95, 1.1, 1);
  head.translate(0, 1.6 * height, 0.01);
  const hg = head.toNonIndexed();
  hg.deleteAttribute('uv');
  const hp = hg.attributes.position;
  const part = new Float32Array(hp.count);
  for (let i = 0; i < hp.count; i += 3) {
    const cy = (hp.getY(i) + hp.getY(i + 1) + hp.getY(i + 2)) / 3 - 1.6 * height;
    const cz = (hp.getZ(i) + hp.getZ(i + 1) + hp.getZ(i + 2)) / 3;
    const isHair = cy > 0.035 || (cz < -0.03 && cy > -0.04);
    part[i] = part[i + 1] = part[i + 2] = isHair ? 2 : 1;
  }
  hg.setAttribute('aPart', new THREE.BufferAttribute(part, 1));
  hg.setAttribute('aArm', new THREE.Float32BufferAttribute(new Float32Array(hp.count), 1));
  parts.push(hg);
  for (const side of [-1, 1]) {
    const sleeve = new THREE.BoxGeometry(0.085, 0.26, 0.09);
    sleeve.translate(side * 0.235, 1.43 - 0.13, 0);
    parts.push(tag(sleeve, 0, side));
    const fore = new THREE.BoxGeometry(0.07, 0.34, 0.075);
    fore.translate(side * 0.235, 1.43 - 0.26 - 0.17, 0.02);
    parts.push(tag(fore, 1, side));
  }
  // Flat-shade the boxy parts so they read as cloth folds at a distance.
  return mergeGeometries(parts);
}

export class Stadium {
  constructor(scene, home, away, quality) {
    this.scene = scene;
    this.home = home;
    this.away = away;
    this.group = new THREE.Group();
    scene.add(this.group);
    this.crowdMats = [];
    this.lightPanels = [];
    this.time = 0;
    this.excite = 0.15;
    this.flash = 0;

    this.buildBowl();
    this.buildUpperDecks();
    this.buildCrowd(quality);
    this.buildSideline();
    this.buildBoards();
    this.buildLights();
    this.buildSurroundings();
  }

  buildBowl() {
    const path = basePath();
    this.path = path;
    const prof = [[0, 0], [0, 1.9, 2]];
    const d = 0.95, r = 0.42, H0 = 1.9, rows = 32;
    this.lower = { d, r, H0, rows };
    for (let k = 0; k < rows; k++) {
      prof.push([(k + 1) * d, H0 + k * r, 1]); // tread (crowd)
      prof.push([(k + 1) * d, H0 + (k + 1) * r, 0]); // riser
    }
    const top = rows * d;
    this.lowerTop = { o: top, h: H0 + rows * r };
    prof.push([top, H0 + rows * r + 1.8, 3]); // ribbon board face
    prof.push([top + 4, H0 + rows * r + 1.8, 0]);
    prof.push([top + 4, 0, 0]);
    const geo = sweep(path, prof);
    const concrete = concreteTexture();
    const crowdCols = this.crowdPalette();
    const fill = crowdFillTexture(crowdCols.map((c) => c.getStyle()));
    fill.repeat.set(1, 1);
    this.ribbonTex = this.makeRibbonTexture();
    this.wallTex = this.makeWallTexture();
    const mats = [
      new THREE.MeshStandardMaterial({ map: concrete, color: '#8a8a90', roughness: 0.95 }),
      new THREE.MeshStandardMaterial({ map: fill, roughness: 0.95 }),
      new THREE.MeshBasicMaterial({ map: this.wallTex, toneMapped: true }),
      new THREE.MeshBasicMaterial({ map: this.ribbonTex, toneMapped: true }),
    ];
    this.ribbonMat = mats[3];
    this.wallMat = mats[2];
    const bowl = new THREE.Mesh(geo, mats);
    bowl.castShadow = true;
    bowl.receiveShadow = true;
    this.group.add(bowl);
  }

  buildUpperDecks() {
    const prof = [];
    const o0 = 24, H0 = 22.5, d = 0.9, r = 0.6, rows = 22;
    this.upper = { o0, H0, d, r, rows };
    prof.push([o0, H0 - 2.2], [o0, H0, 3]);
    for (let k = 0; k < rows; k++) {
      prof.push([o0 + (k + 1) * d, H0 + k * r, 1]);
      prof.push([o0 + (k + 1) * d, H0 + (k + 1) * r, 0]);
    }
    const top = o0 + rows * d;
    prof.push([top, H0 + rows * r + 3, 0], [top + 3, H0 + rows * r + 3, 0], [top + 3, 18, 0], [o0, H0 - 2.2, 0]);
    this.upperTop = { o: top, h: H0 + rows * r };
    const mats = this.group.children[0].material;
    for (const s of [-1, 1]) {
      const path = straightPath(-58 * s, 58 * s, s * B, s);
      const geo = sweep(path, prof);
      const deck = new THREE.Mesh(geo, mats);
      deck.castShadow = true;
      deck.receiveShadow = true;
      this.group.add(deck);
      // End caps.
      const shape = new THREE.Shape();
      shape.moveTo(prof[0][0], prof[0][1]);
      for (const [o, h] of prof.slice(1)) shape.lineTo(o, h);
      const capGeo = new THREE.ShapeGeometry(shape);
      for (const ex of [-58, 58]) {
        const cap = new THREE.Mesh(capGeo, mats[0]);
        cap.rotation.y = s > 0 ? -Math.PI / 2 : Math.PI / 2;
        cap.position.set(ex, 0, s * B);
        cap.material = new THREE.MeshStandardMaterial({ color: '#55565c', roughness: 0.9, side: THREE.DoubleSide });
        cap.castShadow = true;
        this.group.add(cap);
      }
    }
    this.buildCanopies();
    // Press box on the -z side.
    const pb = new THREE.Group();
    const shell = new THREE.Mesh(new THREE.BoxGeometry(80, 7, 7), new THREE.MeshStandardMaterial({ color: '#3a3b40', roughness: 0.7 }));
    shell.castShadow = true;
    pb.add(shell);
    this.windowMat = new THREE.MeshStandardMaterial({ color: '#202833', emissive: '#ffe6b8', emissiveIntensity: 0.2, roughness: 0.15, metalness: 0.4 });
    const win = new THREE.Mesh(new THREE.PlaneGeometry(78, 3.2), this.windowMat);
    win.position.set(0, 0.3, 3.51);
    pb.add(win);
    pb.position.set(0, this.upperTop.h + 3 + 3.5, -(B + this.upperTop.o + 1.5));
    this.group.add(pb);
  }

  // Cantilevered steel roofs over both upper decks, with the light rigs hung
  // along their front edge like a modern college stadium.
  buildCanopies() {
    const front = 27.5, back = this.upperTop.o + 3.2;
    this.canopy = { front, y: 44 };
    const shape = new THREE.Shape();
    shape.moveTo(front, 43.3);
    shape.lineTo(front, 44.6);
    shape.lineTo(back, 41.9);
    shape.lineTo(back, 40.8);
    shape.closePath();
    const roofGeo = new THREE.ExtrudeGeometry(shape, { depth: 124, bevelEnabled: false });
    const roofMat = new THREE.MeshStandardMaterial({ color: '#555860', roughness: 0.75, metalness: 0.35, emissive: '#3a3d44', emissiveIntensity: 0 });
    const steel = new THREE.MeshStandardMaterial({ color: '#34363c', roughness: 0.6, metalness: 0.6, emissive: '#2a2c31', emissiveIntensity: 0 });
    this.roofMats = [roofMat, steel];
    // Underside girders front to back, plus a deep front truss.
    const beams = [];
    for (let x = 0; x <= 124; x += 7.75) {
      const b = new THREE.BoxGeometry(0.5, 1.4, back - front);
      b.rotateX(Math.atan2(44.6 - 41.9, back - front));
      b.translate(x, 0, 0);
      beams.push(b);
    }
    const girderGeo = mergeGeometries(beams);
    for (const sgn of [-1, 1]) {
      const roof = new THREE.Mesh(roofGeo, roofMat);
      roof.rotation.y = sgn > 0 ? -Math.PI / 2 : Math.PI / 2;
      roof.position.set(sgn * 62, 0, sgn * B);
      roof.castShadow = true;
      roof.receiveShadow = true;
      this.group.add(roof);
      const girders = new THREE.Mesh(girderGeo, steel);
      girders.position.set(-62, 42.6, sgn * (B + (front + back) / 2));
      girders.castShadow = true;
      this.group.add(girders);
      const truss = new THREE.Mesh(new THREE.BoxGeometry(124, 2.2, 0.8), steel);
      truss.position.set(0, 42.7, sgn * (B + front + 0.4));
      truss.castShadow = true;
      this.group.add(truss);
      // Support columns behind the upper deck.
      for (let x = -55; x <= 55; x += 22) {
        const col = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.9, 42, 10), steel);
        col.position.set(x, 21, sgn * (B + back - 0.5));
        col.castShadow = true;
        this.group.add(col);
      }
    }
  }

  crowdPalette() {
    const h = this.home;
    return [h.primary, h.primary, h.primary, h.secondary, h.secondary, '#f4f4f2', '#202024', '#5c6066', h.primary]
      .map((c) => new THREE.Color(c));
  }

  buildCrowd(quality) {
    if (quality === 'low') return;
    const spacing = quality === 'high' ? 0.66 : 0.88;
    const rowStep = quality === 'high' ? 1 : 2;
    const rnd = mulberry32(99);
    const homeP = new THREE.Color(this.home.primary), homeS = new THREE.Color(this.home.secondary);
    const awayP = new THREE.Color(this.away.primary), awayS = new THREE.Color(this.away.secondary);
    const neutral = [new THREE.Color('#f2f2f0'), new THREE.Color('#1e1e22'), new THREE.Color('#6a6e74'), new THREE.Color('#2a3a5a')];
    const skins = SKIN_TONES.map((c) => new THREE.Color(c));
    const seats = [];
    const totalLen = this.path[this.path.length - 1].s;
    const place = (x, y, z, nx, nz, section, rowFrac, region) => {
      // Stripe-out: alternate sections in primary/secondary, visitors in one corner, students jump hardest.
      let shirt;
      const roll = rnd();
      if (region === 'away') shirt = roll < 0.6 ? awayP : roll < 0.85 ? awayS : neutral[Math.floor(rnd() * 4)];
      else if (region === 'student') shirt = roll < 0.85 ? homeP : roll < 0.95 ? homeS : neutral[0];
      else if (region === 'band') shirt = rowFrac < 0.5 ? homeS : homeP;
      else {
        const main = section % 2 === 0 ? homeP : homeS;
        shirt = roll < 0.66 ? main : roll < 0.8 ? (main === homeP ? homeS : homeP) : neutral[Math.floor(rnd() * 4)];
      }
      seats.push({
        x, y, z, yaw: Math.atan2(-nx, -nz), shirt,
        skin: skins[Math.floor(rnd() * skins.length)],
        phase: rnd(),
        energy: region === 'student' ? 1.3 : region === 'away' ? 0.5 : 0.5 + rnd() * 0.6,
        scale: 0.92 + rnd() * 0.16,
      });
    };
    const L = this.lower;
    for (let k = 0; k < L.rows; k += rowStep) {
      const off = (k + 0.55) * L.d, y = L.H0 + k * L.r;
      let seatIdx = 0;
      seatsAlong(this.path, off, spacing, (x, z, nx, nz, s) => {
        seatIdx++;
        if (seatIdx % 26 === 0 || seatIdx % 26 === 1) return; // aisles
        if (rnd() < 0.04) return; // empty seats
        const frac = s / totalLen;
        const section = Math.floor(s / 16);
        let region = 'home';
        if (frac > 0.36 && frac < 0.44) region = 'away';
        else if (frac > 0.84 || frac < 0.0) region = 'student';
        else if (frac > 0.6 && frac < 0.66 && k < 14) region = 'band';
        place(x, y, z, nx, nz, section, k / L.rows, region);
      });
    }
    const U = this.upper;
    for (const sgn of [-1, 1]) {
      const path = straightPath(-57, 57, sgn * B, sgn);
      for (let k = 0; k < U.rows; k += rowStep) {
        const off = U.o0 + (k + 0.55) * U.d, y = U.H0 + k * U.r;
        let seatIdx = 0;
        seatsAlong(path, off, spacing, (x, z, nx, nz, s) => {
          seatIdx++;
          if (seatIdx % 24 === 0) return;
          if (rnd() < 0.05) return;
          place(x, y, z, nx, nz, Math.floor((s + 200) / 14), k / U.rows, 'home');
        });
      }
    }
    this.crowdMesh = this.makeCrowdMesh(personGeometry(), seats);
    this.group.add(this.crowdMesh);
  }

  makeCrowdMesh(geo, seats, helmets = false) {
    const g = new THREE.InstancedBufferGeometry();
    g.index = geo.index;
    for (const k of Object.keys(geo.attributes)) g.setAttribute(k, geo.attributes[k]);
    const n = seats.length;
    const shirt = new Float32Array(n * 3), skin = new Float32Array(n * 3), pants = new Float32Array(n * 3), anim = new Float32Array(n * 2);
    const helm = new Float32Array(n * 3);
    const denim = [new THREE.Color('#1d2533'), new THREE.Color('#2b3346'), new THREE.Color('#141416'), new THREE.Color('#6b6150'), new THREE.Color('#3a3a3e')];
    seats.forEach((s, i) => {
      shirt.set([s.shirt.r, s.shirt.g, s.shirt.b], i * 3);
      skin.set([s.skin.r, s.skin.g, s.skin.b], i * 3);
      const pc = s.pants || denim[Math.floor(s.phase * 977) % denim.length];
      pants.set([pc.r, pc.g, pc.b], i * 3);
      const hc = s.helmet || s.shirt;
      helm.set([hc.r, hc.g, hc.b], i * 3);
      anim.set([s.phase, s.energy], i * 2);
    });
    g.setAttribute('aShirt', new THREE.InstancedBufferAttribute(shirt, 3));
    g.setAttribute('aSkin', new THREE.InstancedBufferAttribute(skin, 3));
    g.setAttribute('aPants', new THREE.InstancedBufferAttribute(pants, 3));
    g.setAttribute('aAnim', new THREE.InstancedBufferAttribute(anim, 2));
    g.setAttribute('aHelmet', new THREE.InstancedBufferAttribute(helm, 3));
    const mat = new THREE.ShaderMaterial({
      vertexShader: CROWD_VERT,
      fragmentShader: CROWD_FRAG,
      uniforms: {
        uTime: { value: 0 }, uExcite: { value: 0.2 }, uHelmets: { value: helmets ? 1 : 0 },
        uLightDir: { value: new THREE.Vector3(0.3, 0.8, 0.2).normalize() },
        uLightCol: { value: new THREE.Color(1, 0.97, 0.9) },
        uAmbient: { value: new THREE.Color(0.35, 0.38, 0.45) },
        uFogColor: { value: new THREE.Color(0.5, 0.6, 0.75) },
      },
    });
    this.crowdMats.push(mat);
    const mesh = new THREE.InstancedMesh(g, mat, n);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), sc = new THREE.Vector3(), p = new THREE.Vector3();
    seats.forEach((s, i) => {
      e.set(0, s.yaw, 0);
      q.setFromEuler(e);
      sc.setScalar(s.scale);
      p.set(s.x, s.y, s.z);
      m.compose(p, q, sc);
      mesh.setMatrixAt(i, m);
    });
    mesh.frustumCulled = false;
    return mesh;
  }

  buildSideline() {
    // Team areas: benches plus a crowd of players and staff behind the coaching box.
    const rnd = mulberry32(5);
    const seats = [];
    const hw = FIELD.halfWidth;
    const teams = [[this.home, hw + 7.5, 1], [this.away, -(hw + 7.5), -1]];
    const benchMatH = new THREE.MeshStandardMaterial({ color: this.home.primary, roughness: 0.6 });
    const benchMatA = new THREE.MeshStandardMaterial({ color: this.away.primary, roughness: 0.6 });
    for (const [team, z, s] of teams) {
      const bench = new THREE.Mesh(new THREE.BoxGeometry(36, 0.9, 1.2), s > 0 ? benchMatH : benchMatA);
      bench.position.set(0, 0.45, z + s * 3.2);
      bench.castShadow = true;
      bench.receiveShadow = true;
      this.group.add(bench);
      const kit = kitFor(team, s > 0 ? 'home' : 'away');
      const kitShirt = new THREE.Color(kit.jersey);
      const kitPants = new THREE.Color(kit.pants);
      const helmet = new THREE.Color(team.helmet);
      for (let i = 0; i < 70; i++) {
        const staff = rnd() < 0.18;
        const skin = new THREE.Color(SKIN_TONES[Math.floor(rnd() * 6)]);
        seats.push({
          x: -24 + rnd() * 48, y: 0, z: z + s * (rnd() * 2.6),
          yaw: s > 0 ? Math.PI + (rnd() - 0.5) * 0.8 : (rnd() - 0.5) * 0.8,
          shirt: staff ? new THREE.Color(rnd() < 0.5 ? '#222326' : team.primary) : kitShirt,
          skin,
          pants: staff ? new THREE.Color('#3a3530') : kitPants,
          helmet: staff ? new THREE.Color('#1e1a16') : helmet,
          phase: rnd(), energy: 0.7, scale: 1.12 + rnd() * 0.12,
        });
      }
    }
    this.sidelineMesh = this.makeCrowdMesh(personGeometry(1.05), seats, true);
    this.group.add(this.sidelineMesh);

    // Field wall pads + cameras on the far sideline.
    const camMat = new THREE.MeshStandardMaterial({ color: '#18181b', roughness: 0.5, metalness: 0.4 });
    for (const x of [-30, 0, 30]) {
      const cam = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.5, 1.0), camMat);
      cam.position.set(x, 2.1, -(hw + 11));
      const tri = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.4, 1.8, 3), camMat);
      tri.position.set(x, 0.9, -(hw + 11));
      cam.castShadow = tri.castShadow = true;
      this.group.add(cam, tri);
    }
  }

  makeRibbonTexture() {
    const c = document.createElement('canvas');
    c.width = 2048; c.height = 96;
    this.ribbonCanvas = c;
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = THREE.RepeatWrapping;
    t.repeat.set(0.155, 1);
    this.drawRibbon(`${this.home.school.toUpperCase()} ${this.home.name.toUpperCase()}`);
    return t;
  }

  drawRibbon(text, flash = false) {
    const c = this.ribbonCanvas, ctx = c.getContext('2d');
    const h = this.home;
    const g = ctx.createLinearGradient(0, 0, 0, c.height);
    g.addColorStop(0, shade(h.primary, flash ? 0.2 : -0.1));
    g.addColorStop(1, shade(h.primary, flash ? -0.1 : -0.45));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, c.width, c.height);
    ctx.font = `800 64px ${DISPLAY_FONT}`;
    ctx.textBaseline = 'middle';
    ctx.fillStyle = flash ? '#ffffff' : (h.secondary === '#ffffff' ? '#ffffff' : h.secondary);
    const items = [text, h.letter, text, '★'];
    let x = 30;
    for (let i = 0; i < 6; i++) {
      const s = items[i % items.length];
      ctx.fillText(s, x, c.height / 2 + 4);
      x += ctx.measureText(s).width + 70;
    }
    // LED pixel grid.
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    for (let y = 0; y < c.height; y += 4) ctx.fillRect(0, y, c.width, 1);
    if (this.ribbonTex) this.ribbonTex.needsUpdate = true;
  }

  makeWallTexture() {
    const c = document.createElement('canvas');
    c.width = 2048; c.height = 64;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#121418';
    ctx.fillRect(0, 0, c.width, c.height);
    const words = [this.home.school.toUpperCase(), 'GAMEDAY', this.home.name.toUpperCase(), 'RIVALRY WEEK'];
    ctx.font = `700 40px ${DISPLAY_FONT}`;
    ctx.textBaseline = 'middle';
    const cols = ['#ffffff', this.home.secondary === '#ffffff' ? shade(this.home.primary, 0.45) : this.home.secondary];
    let x = 20;
    for (let i = 0; i < 8; i++) {
      ctx.fillStyle = cols[i % 2];
      ctx.fillText(words[i % words.length], x, 34);
      x += ctx.measureText(words[i % words.length]).width + 60;
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = THREE.RepeatWrapping;
    t.repeat.set(0.1, 1);
    return t;
  }

  buildBoards() {
    // Main video board over the +x end zone.
    const c = document.createElement('canvas');
    c.width = 1280; c.height = 560;
    this.boardCanvas = c;
    this.boardTex = new THREE.CanvasTexture(c);
    this.boardTex.colorSpace = THREE.SRGBColorSpace;
    const frame = new THREE.Mesh(new THREE.BoxGeometry(3, 22, 49), new THREE.MeshStandardMaterial({ color: '#141519', roughness: 0.6 }));
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(46, 20), new THREE.MeshBasicMaterial({ map: this.boardTex, toneMapped: false }));
    screen.rotation.y = -Math.PI / 2;
    screen.position.x = -1.55;
    const board = new THREE.Group();
    board.add(frame, screen);
    const legMat = new THREE.MeshStandardMaterial({ color: '#2a2b30', roughness: 0.7 });
    for (const z of [-14, 14]) {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(2, 30, 2), legMat);
      leg.position.set(2, -24, z);
      leg.castShadow = true;
      board.add(leg);
    }
    board.position.set(A + 34, this.lowerTop.h + 20, 0);
    frame.castShadow = true;
    this.group.add(board);
    this.drawBoard({ home: 0, away: 0, quarter: 1, clock: '8:00', down: '1st & 10', text: '' });
  }

  drawBoard({ home, away, quarter, clock, down, text, possession }) {
    const c = this.boardCanvas, ctx = c.getContext('2d');
    const H = this.home, Aw = this.away;
    ctx.fillStyle = '#07080b';
    ctx.fillRect(0, 0, c.width, c.height);
    const half = (team, x, score, hasBall) => {
      const g = ctx.createLinearGradient(x, 0, x + 600, 0);
      g.addColorStop(0, team.primary);
      g.addColorStop(1, shade(team.primary, -0.55));
      ctx.fillStyle = g;
      ctx.fillRect(x, 20, 600, 300);
      ctx.fillStyle = '#ffffff';
      ctx.font = `800 72px ${DISPLAY_FONT}`;
      ctx.textAlign = 'left';
      ctx.fillText(team.school.toUpperCase(), x + 30, 110);
      ctx.font = `600 40px ${DISPLAY_FONT}`;
      ctx.fillStyle = 'rgba(255,255,255,0.8)';
      ctx.fillText(team.name.toUpperCase(), x + 32, 160);
      ctx.font = `900 170px ${DISPLAY_FONT}`;
      ctx.textAlign = 'right';
      ctx.fillStyle = '#ffffff';
      ctx.fillText(String(score), x + 570, 300);
      if (hasBall) {
        ctx.fillStyle = '#ffd21a';
        ctx.beginPath();
        ctx.ellipse(x + 50, 250, 22, 13, 0, 0, Math.PI * 2);
        ctx.fill();
      }
    };
    half(Aw, 20, away, possession === 'away');
    half(H, 660, home, possession === 'home');
    ctx.fillStyle = '#111317';
    ctx.fillRect(20, 340, 1240, 200);
    ctx.textAlign = 'center';
    ctx.fillStyle = '#ffd21a';
    ctx.font = `800 64px ${DISPLAY_FONT}`;
    ctx.fillText(`Q${quarter > 4 ? 'OT' : quarter}   ${clock}`, 330, 460);
    ctx.fillStyle = '#ffffff';
    ctx.fillText(text || down || '', 930, 460);
    // LED texture.
    ctx.fillStyle = 'rgba(0,0,0,0.18)';
    for (let y = 0; y < c.height; y += 5) ctx.fillRect(0, y, c.width, 2);
    this.boardTex.needsUpdate = true;
  }

  buildLights() {
    // Banks of luminaires on top of the upper decks and four corner masts.
    const panelGeo = new THREE.BoxGeometry(1.1, 1.1, 0.5);
    const count = 2 * 12 * 18 + 4 * 30;
    this.panelMat = new THREE.MeshStandardMaterial({ color: '#d9d9d6', emissive: '#fff6e8', emissiveIntensity: 0, roughness: 0.3 });
    const panels = new THREE.InstancedMesh(panelGeo, this.panelMat, count);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3(1, 1, 1);
    const target = new THREE.Vector3();
    const look = new THREE.Object3D();
    let i = 0;
    this.lightSpots = [];
    const addBank = (cx, cy, cz, cols, rows) => {
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          p.set(cx + (c - (cols - 1) / 2) * 1.3, cy + r * 1.3, cz);
          look.position.copy(p);
          target.set(cx * 0.4, 0, 0);
          look.lookAt(target);
          q.copy(look.quaternion);
          m.compose(p, q, s);
          panels.setMatrixAt(i++, m);
        }
      }
      this.lightSpots.push(new THREE.Vector3(cx, cy + rows * 0.65, cz));
    };
    // Rigs hang under the canopy's front edge.
    for (const sz of [-1, 1]) {
      for (let b = 0; b < 12; b++) {
        addBank(-55 + b * 10, this.canopy.y - 3.6, sz * (B + this.canopy.front - 0.6), 6, 3);
      }
    }
    const mastMat = new THREE.MeshStandardMaterial({ color: '#4a4b50', roughness: 0.6, metalness: 0.5 });
    for (const sx of [-1, 1]) {
      for (const sz of [-1, 1]) {
        const x = sx * (A + 30), z = sz * (B + 30);
        const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 1.0, 48, 8), mastMat);
        mast.position.set(x, 24, z);
        mast.castShadow = true;
        this.group.add(mast);
        addBank(x, 48, z, 6, 5);
      }
    }
    panels.count = i;
    this.group.add(panels);
    // Glow sprites for night.
    const glow = glowTexture();
    this.glows = new THREE.Group();
    for (const sp of this.lightSpots) {
      // A tight halo only: big additive glows read as fog over the stands.
      const spr = new THREE.Sprite(new THREE.SpriteMaterial({ map: glow, color: '#fff3dc', blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, opacity: 0.32 }));
      spr.position.copy(sp);
      spr.scale.setScalar(6.5);
      this.glows.add(spr);
    }
    this.group.add(this.glows);
  }

  buildSurroundings() {
    // Ground outside the stadium and a ring of distant campus silhouettes.
    const ground = new THREE.Mesh(new THREE.CircleGeometry(900, 48), new THREE.MeshStandardMaterial({ color: '#2b3a24', roughness: 1 }));
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.05;
    ground.receiveShadow = true;
    this.group.add(ground);
    const rnd = mulberry32(12);
    const mats = [new THREE.MeshStandardMaterial({ color: '#58524c', roughness: 0.9 }), new THREE.MeshStandardMaterial({ color: '#6b5f55', roughness: 0.9 })];
    const treeMat = new THREE.MeshStandardMaterial({ color: '#2a4022', roughness: 1 });
    const treeGeo = new THREE.IcosahedronGeometry(1, 1);
    for (let i = 0; i < 70; i++) {
      const a = rnd() * Math.PI * 2, r = 210 + rnd() * 260;
      if (rnd() < 0.55) {
        const t = new THREE.Mesh(treeGeo, treeMat);
        t.scale.set(6 + rnd() * 6, 7 + rnd() * 8, 6 + rnd() * 6);
        t.position.set(Math.cos(a) * r, t.scale.y * 0.8, Math.sin(a) * r);
        this.group.add(t);
      } else {
        const h = 10 + rnd() * 30;
        const b = new THREE.Mesh(new THREE.BoxGeometry(15 + rnd() * 25, h, 15 + rnd() * 25), mats[i % 2]);
        b.position.set(Math.cos(a) * r, h / 2, Math.sin(a) * r);
        b.rotation.y = rnd() * Math.PI;
        this.group.add(b);
      }
    }
  }

  setLighting({ night, sunDir, sunColor, ambient, fog }) {
    this.panelMat.emissiveIntensity = night ? 5 : 0.0;
    // Spill from the rigs lights the underside of the roofs at night.
    for (const m of this.roofMats || []) m.emissiveIntensity = night ? 1.6 : 0;
    this.glows.visible = night;
    this.windowMat.emissiveIntensity = night ? 1.2 : 0.15;
    for (const mat of this.crowdMats) {
      mat.uniforms.uLightDir.value.copy(sunDir).normalize();
      mat.uniforms.uLightCol.value.copy(sunColor);
      mat.uniforms.uAmbient.value.copy(ambient);
      mat.uniforms.uFogColor.value.copy(fog);
    }
  }

  cheer(level, ms = 2500) {
    this.excite = Math.max(this.excite, level);
    this.exciteHold = ms / 1000;
  }

  update(dt) {
    this.time += dt;
    if (this.exciteHold > 0) this.exciteHold -= dt;
    else this.excite += (0.15 - this.excite) * Math.min(1, dt * 0.8);
    for (const mat of this.crowdMats) {
      mat.uniforms.uTime.value = this.time;
      mat.uniforms.uExcite.value = this.excite;
    }
    this.ribbonTex.offset.x = (this.time * 0.02) % 1;
    this.wallTex.offset.x = (-this.time * 0.015) % 1;
  }
}
