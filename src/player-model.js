// Articulated football player built from primitives, posed procedurally.
// Units are yards. The model faces +z in its local space.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import {
  jerseyTexture, sleeveTexture, pantsTexture, helmetTexture, faceTexture, SKIN_TONES, kitFor,
  fabricNormalTexture, knitNormalTexture,
} from './textures.js';
import { damp } from './util.js';

const THIGH = 0.46, SHIN = 0.46, ANKLE = 0.08;
const UPPER = 0.33, FORE = 0.3;
const HIP_Y = THIGH + SHIN + ANKLE;

// ---------------------------------------------------------------- geometry
// A limb turned on a lathe from a (radius, y) profile listed bottom to top, so
// thighs, calves, biceps and forearms have real muscle shape instead of tubes.
function limb(profile, segs = 16) {
  const g = new THREE.LatheGeometry(profile.map(([r, y]) => new THREE.Vector2(r, y)), segs);
  return g;
}

// Push vertices on one side of a limb outward over a height band (calf, biceps).
function bulge(g, side, y0, y1, amount) {
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i), z = p.getZ(i);
    if (y < y0 || y > y1 || Math.sign(z) !== side) continue;
    const t = Math.sin(((y - y0) / (y1 - y0)) * Math.PI);
    p.setZ(i, z * (1 + amount * t));
  }
  g.computeVertexNormals();
  return g;
}

let G = null;
function geometries() {
  if (G) return G;
  // Jersey over shoulder pads: narrow tucked waist flaring to a wide, flat-topped
  // pad line (the football V), deeper through the chest than the waist.
  const torsoProfile = [
    [0.118, -0.09], [0.122, -0.02], [0.13, 0.07], [0.148, 0.17], [0.172, 0.27], [0.192, 0.36],
    [0.206, 0.44], [0.212, 0.5], [0.205, 0.555], [0.178, 0.605], [0.12, 0.645], [0.066, 0.668],
  ].map(([r, y]) => new THREE.Vector2(r, y));
  const torso = new THREE.LatheGeometry(torsoProfile, 44, Math.PI / 2);
  {
    const p = torso.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const y = p.getY(i);
      const k = THREE.MathUtils.smoothstep(y, 0.0, 0.5);
      p.setX(i, p.getX(i) * (1.3 + 0.36 * k));
      const z = p.getZ(i);
      // Chest pushes forward, the back stays flatter.
      p.setZ(i, z * (z > 0 ? 0.98 + 0.12 * k : 0.9 + 0.05 * k));
    }
    torso.computeVertexNormals();
  }

  // Tapered pelvis that tucks under the jersey hem (no boxy "skirt").
  const hips = new THREE.LatheGeometry([
    [0.104, -0.13], [0.124, -0.08], [0.13, 0.0], [0.124, 0.07], [0.116, 0.11],
  ].map(([r, y]) => new THREE.Vector2(r, y)), 24, Math.PI / 2);
  hips.scale(1.3, 1, 1.0);

  // Thigh in game pants: full at the hip, tapering to the knee, with a knee pad.
  const thigh = limb([
    [0.001, -0.49], [0.058, -0.478], [0.066, -0.44], [0.075, -0.38], [0.087, -0.28],
    [0.097, -0.17], [0.104, -0.07], [0.101, 0.0], [0.075, 0.04], [0.001, 0.055],
  ], 18);
  thigh.scale(1, 1, 1.1);
  bulge(thigh, 1, -0.36, -0.04, 0.12); // quads
  const kneePad = new THREE.SphereGeometry(0.06, 14, 10);
  kneePad.scale(1.05, 1.15, 0.62);
  kneePad.translate(0, -THIGH + 0.03, 0.048);
  const thighFull = mergeGeometries([thigh, kneePad]);

  // Lower leg in socks: calf muscle at the back, slim ankle.
  const shin = limb([
    [0.001, -0.485], [0.038, -0.475], [0.041, -0.42], [0.046, -0.34], [0.058, -0.23],
    [0.068, -0.13], [0.066, -0.05], [0.058, 0.0], [0.001, 0.03],
  ], 16);
  bulge(shin, -1, -0.3, -0.03, 0.35);

  // Cleat: rounded upper, tapered toe, contrasting sole.
  const foot = new RoundedBoxGeometry(0.105, 0.072, 0.3, 3, 0.03);
  const fp = foot.attributes.position;
  for (let i = 0; i < fp.count; i++) {
    const z = fp.getZ(i), y = fp.getY(i);
    if (z > 0.04) {
      const k = (z - 0.04) / 0.11;
      fp.setX(i, fp.getX(i) * (1 - 0.28 * k));
      if (y > 0) fp.setY(i, y * (1 - 0.55 * k));
    }
  }
  foot.computeVertexNormals();
  foot.translate(0, -0.035, 0.06);
  const sole = new RoundedBoxGeometry(0.11, 0.022, 0.305, 2, 0.008);
  sole.translate(0, -0.075, 0.06);

  // Upper arm with a biceps/triceps shape.
  const upper = limb([
    [0.001, -0.35], [0.052, -0.338], [0.056, -0.3], [0.066, -0.21], [0.076, -0.13],
    [0.076, -0.05], [0.07, 0.0], [0.001, 0.04],
  ], 14);
  bulge(upper, 1, -0.26, -0.06, 0.16);
  const sleeve = new THREE.CylinderGeometry(0.098, 0.088, 0.15, 16, 1, true);
  sleeve.translate(0, -0.06, 0);
  // Shoulder pad caps: flat epaulets, not balls.
  const shoulderCap = new THREE.SphereGeometry(0.115, 18, 10);
  shoulderCap.scale(1.12, 0.6, 1.0);
  // Forearm: thick below the elbow, narrow at the wrist.
  const fore = limb([
    [0.001, -0.31], [0.036, -0.302], [0.039, -0.27], [0.05, -0.18], [0.06, -0.09],
    [0.056, -0.02], [0.001, 0.02],
  ], 14);
  fore.scale(1.12, 1, 0.95);
  const tape = new THREE.CylinderGeometry(0.039, 0.041, 0.055, 14, 1, true);
  tape.translate(0, -FORE + 0.03, 0);

  // Glove: palm, curled fingers and a thumb.
  const palm = new RoundedBoxGeometry(0.07, 0.085, 0.034, 2, 0.014);
  palm.translate(0, -FORE - 0.04, 0.004);
  const fingers = new RoundedBoxGeometry(0.066, 0.062, 0.028, 2, 0.012);
  fingers.rotateX(0.55);
  fingers.translate(0, -FORE - 0.1, 0.02);
  const thumb = new RoundedBoxGeometry(0.022, 0.05, 0.022, 2, 0.009);
  thumb.rotateZ(0.5);
  thumb.translate(0.038, -FORE - 0.05, 0.016);
  const hand = mergeGeometries([palm, fingers, thumb]);

  const neck = new THREE.CylinderGeometry(0.064, 0.074, 0.13, 14);
  neck.translate(0, 0.05, 0);
  const face = new THREE.SphereGeometry(0.108, 24, 16, Math.PI * 1.5);
  face.scale(0.9, 1.1, 1.0);

  // Helmet shell with the face opening cut out (UVs stay global).
  const shellSrc = new THREE.SphereGeometry(0.148, 40, 28, Math.PI * 1.5);
  shellSrc.scale(0.96, 1.0, 1.12);
  const pos = shellSrc.attributes.position;
  const idx = shellSrc.index.array;
  const keep = [];
  for (let i = 0; i < idx.length; i += 3) {
    let cx = 0, cy = 0, cz = 0;
    for (let k = 0; k < 3; k++) {
      cx += pos.getX(idx[i + k]); cy += pos.getY(idx[i + k]); cz += pos.getZ(idx[i + k]);
    }
    cx /= 3; cy /= 3; cz /= 3;
    const open = cz > 0.03 && cy < 0.022 && Math.abs(cx) < 0.088 && cy > -0.2;
    const bottom = cy < -0.105 && !(Math.abs(cx) > 0.09 && cz > -0.05);
    if (!open && !bottom) keep.push(idx[i], idx[i + 1], idx[i + 2]);
  }
  shellSrc.setIndex(keep);
  const shell = shellSrc;
  const liner = shell.clone();
  liner.scale(0.965, 0.965, 0.965);

  // Facemask: arcs + center bar, merged.
  const bars = [];
  const arc = (y, r, span, tube) => {
    const t = new THREE.TorusGeometry(r, tube, 6, 24, span);
    t.rotateX(Math.PI / 2);
    t.rotateY(-Math.PI / 2 - span / 2 + Math.PI);
    t.translate(0, y, 0.0);
    return t;
  };
  bars.push(arc(0.012, 0.155, 2.2, 0.008));
  bars.push(arc(-0.045, 0.158, 2.0, 0.0075));
  bars.push(arc(-0.098, 0.15, 1.7, 0.0075));
  const vbar = new THREE.CylinderGeometry(0.007, 0.007, 0.12, 6);
  vbar.translate(0, -0.045, 0.165);
  bars.push(vbar);
  for (const s of [-1, 1]) {
    const side = new THREE.CylinderGeometry(0.007, 0.007, 0.13, 6);
    side.rotateX(0.25);
    side.translate(s * 0.095, -0.05, 0.125);
    bars.push(side);
  }
  const mask = mergeGeometries(bars.map((b) => b.toNonIndexed()));
  const visor = new THREE.SphereGeometry(0.15, 24, 6, Math.PI * 1.5 + 1.0, Math.PI - 2.0, Math.PI / 2 - 0.02, 0.1);
  visor.scale(0.96, 1, 1.12);
  const chin = new RoundedBoxGeometry(0.07, 0.04, 0.05, 2, 0.015);
  chin.translate(0, -0.13, 0.11);
  // Jaw pads inside the shell frame the face like a real helmet.
  const padL = new THREE.SphereGeometry(0.05, 12, 8);
  padL.scale(0.55, 1.1, 1.1);
  padL.translate(0.085, -0.055, 0.075);
  const padR = padL.clone();
  padR.translate(-0.17, 0, 0);
  const jawPads = mergeGeometries([padL, padR]);
  const towel = new THREE.PlaneGeometry(0.11, 0.24);
  towel.translate(0, -0.12, 0);

  G = { torso, hips, thigh: thighFull, shin, foot, sole, upper, sleeve, shoulderCap, fore, tape, hand, neck, face, shell, liner, mask, visor, chin, towel, jawPads };
  return G;
}

// ---------------------------------------------------------------- materials
const teamMatCache = new Map();
function teamMaterials(team, role) {
  const key = team.id + role;
  if (teamMatCache.has(key)) return teamMatCache.get(key);
  const kit = kitFor(team, role);
  const knit = knitNormalTexture();
  const fabric = (map, color = '#ffffff') => new THREE.MeshPhysicalMaterial({
    map, color, roughness: 0.78, sheen: 0.5, sheenRoughness: 0.6, sheenColor: new THREE.Color('#ffffff'),
    normalMap: knit, normalScale: new THREE.Vector2(0.35, 0.35),
  });
  const m = {
    kit,
    sleeve: fabric(sleeveTexture(kit)),
    shoulder: fabric(null, kit.jersey),
    // Game pants are stretchy and a little shiny.
    pants: new THREE.MeshPhysicalMaterial({
      map: pantsTexture(kit), roughness: 0.5, sheen: 0.8, sheenRoughness: 0.35, sheenColor: new THREE.Color('#ffffff'),
      normalMap: knit, normalScale: new THREE.Vector2(0.2, 0.2), clearcoat: 0.08,
    }),
    socks: new THREE.MeshPhysicalMaterial({ color: kit.socks, roughness: 0.88, sheen: 0.4, sheenColor: new THREE.Color('#ffffff'), normalMap: knit, normalScale: new THREE.Vector2(0.5, 0.5) }),
    glove: new THREE.MeshPhysicalMaterial({ color: kit.glove, roughness: 0.38, clearcoat: 0.3, clearcoatRoughness: 0.4 }),
    cleat: new THREE.MeshPhysicalMaterial({ color: kit.cleat, roughness: 0.35, clearcoat: 0.6, clearcoatRoughness: 0.2 }),
    sole: new THREE.MeshStandardMaterial({ color: kit.cleat === '#111111' ? '#e9e9e6' : '#1a1a1c', roughness: 0.7 }),
    tape: new THREE.MeshStandardMaterial({ color: '#f2f2ee', roughness: 0.85 }),
    helmet: new THREE.MeshPhysicalMaterial({
      map: helmetTexture(team), roughness: 0.32, metalness: team.helmet === '#d8a637' || team.helmet === '#c9a46a' ? 0.45 : 0.05,
      clearcoat: 1, clearcoatRoughness: 0.06,
    }),
    liner: new THREE.MeshStandardMaterial({ color: '#16161a', roughness: 0.9, side: THREE.BackSide }),
    liner2: new THREE.MeshStandardMaterial({ color: '#1c1c20', roughness: 0.85 }),
    mask: new THREE.MeshStandardMaterial({ color: team.mask, roughness: 0.38, metalness: 0.25 }),
    visor: new THREE.MeshPhysicalMaterial({ color: '#0c0d10', roughness: 0.05, metalness: 0.6, transparent: true, opacity: 0.88, side: THREE.DoubleSide }),
    chin: new THREE.MeshStandardMaterial({ color: '#e8e8e8', roughness: 0.6 }),
    towel: new THREE.MeshStandardMaterial({ color: '#f4f4f0', roughness: 0.95, side: THREE.DoubleSide }),
    armSleeve: {
      black: new THREE.MeshStandardMaterial({ color: '#141416', roughness: 0.6 }),
      white: new THREE.MeshStandardMaterial({ color: '#efefef', roughness: 0.6 }),
    },
  };
  teamMatCache.set(key, m);
  return m;
}

const skinCache = [];
function skinMaterials(i) {
  if (!skinCache[i]) {
    skinCache[i] = {
      skin: new THREE.MeshPhysicalMaterial({ color: SKIN_TONES[i], roughness: 0.55, sheen: 0.25, sheenColor: new THREE.Color('#ffd7c2') }),
      face: new THREE.MeshStandardMaterial({ map: faceTexture(SKIN_TONES[i]), roughness: 0.5 }),
    };
  }
  return skinCache[i];
}

// ---------------------------------------------------------------- poses
const POSE_KEYS = [
  'pelvisY', 'pelvisYaw', 'spineX', 'spineY', 'spineZ', 'headX', 'headY',
  'hipXL', 'hipXR', 'hipZL', 'hipZR', 'kneeL', 'kneeR',
  'shXL', 'shXR', 'shZL', 'shZR', 'elbL', 'elbR', 'rootX', 'rootZ', 'rootY',
];

function basePose() {
  return {
    pelvisY: HIP_Y - 0.01, pelvisYaw: 0, spineX: 0.05, spineY: 0, spineZ: 0, headX: -0.05, headY: 0,
    hipXL: -0.03, hipXR: 0.03, hipZL: 0.05, hipZR: -0.05, kneeL: 0.08, kneeR: 0.08,
    shXL: 0.05, shXR: 0.05, shZL: 0.16, shZR: -0.16, elbL: -0.35, elbR: -0.35, rootX: 0, rootZ: 0, rootY: 0,
  };
}

// ---------------------------------------------------------------- model
export class PlayerModel {
  constructor(team, role, info) {
    const g = geometries();
    const tm = teamMaterials(team, role);
    const sk = skinMaterials(info.skin ?? 0);
    this.info = info;
    this.size = info.rat?.size ?? 1;

    // Mesh jersey fabric: fine perforated knit in the normal map.
    this.jerseyMat = new THREE.MeshPhysicalMaterial({
      map: jerseyTexture(tm.kit, info.num, info.last), roughness: 0.72,
      sheen: 0.6, sheenRoughness: 0.5, sheenColor: new THREE.Color('#ffffff'),
      normalMap: fabricNormalTexture(), normalScale: new THREE.Vector2(0.45, 0.45),
    });

    const mesh = (geo, mat, parent, shadow = true) => {
      const m = new THREE.Mesh(geo, mat);
      m.castShadow = shadow;
      m.receiveShadow = true;
      parent.add(m);
      return m;
    };

    this.root = new THREE.Group();
    this.body = new THREE.Group(); // scaled by player size
    this.root.add(this.body);
    const s = this.size;
    // Big men are wider more than taller.
    this.body.scale.set(0.9 + 0.1 * s + (s - 1) * 0.55, 0.96 + 0.04 * s + (s - 1) * 0.1, 0.9 + 0.1 * s + (s - 1) * 0.45);

    this.pelvis = new THREE.Group();
    this.body.add(this.pelvis);
    mesh(g.hips, tm.pants, this.pelvis).position.y = 0.0;

    this.spine = new THREE.Group();
    this.spine.position.y = 0.075;
    this.pelvis.add(this.spine);
    mesh(g.torso, this.jerseyMat, this.spine);
    if (info.towel) {
      const t = mesh(g.towel, tm.towel, this.pelvis, false);
      t.position.set(-0.12, 0.05, 0.17);
      t.rotation.x = 0.15;
    }

    this.neck = new THREE.Group();
    this.neck.position.y = 0.625;
    this.spine.add(this.neck);
    mesh(g.neck, sk.skin, this.neck);
    this.head = new THREE.Group();
    this.head.position.y = 0.16;
    this.head.scale.setScalar(1.12); // helmets are big next to the body
    this.neck.add(this.head);
    const face = mesh(g.face, sk.face, this.head);
    face.position.set(0, -0.016, -0.006);
    face.scale.setScalar(0.94);
    const shell = mesh(g.shell, tm.helmet, this.head);
    shell.position.set(0, 0.02, -0.005);
    const liner = mesh(g.liner, tm.liner, this.head, false);
    liner.position.copy(shell.position);
    const mask = mesh(g.mask, tm.mask, this.head);
    mask.position.set(0, 0.0, 0.0);
    mesh(g.chin, tm.chin, this.head, false);
    mesh(g.jawPads, tm.liner2, this.head, false);
    if (info.visor) {
      const v = mesh(g.visor, tm.visor, this.head, false);
      v.position.set(0, 0.0, 0.0);
    }

    const armMat = info.sleeves === 'black' ? tm.armSleeve.black : info.sleeves === 'white' ? tm.armSleeve.white : sk.skin;
    const limbs = {};
    for (const side of ['L', 'R']) {
      const sx = side === 'L' ? 1 : -1;
      const sh = new THREE.Group();
      sh.position.set(sx * 0.29, 0.52, -0.01);
      this.spine.add(sh);
      const cap = mesh(g.shoulderCap, tm.shoulder, this.spine);
      cap.position.set(sx * 0.262, 0.54, 0.005);
      cap.rotation.z = sx * -0.28;
      mesh(g.upper, armMat, sh);
      mesh(g.sleeve, tm.sleeve, sh);
      const elbow = new THREE.Group();
      elbow.position.y = -UPPER;
      sh.add(elbow);
      mesh(g.fore, armMat, elbow);
      mesh(g.hand, tm.glove, elbow);
      if ((info.num + (side === 'L' ? 1 : 0)) % 3 !== 0) mesh(g.tape, tm.tape, elbow, false);

      const hip = new THREE.Group();
      hip.position.set(sx * 0.105, -0.02, 0);
      this.pelvis.add(hip);
      mesh(g.thigh, tm.pants, hip);
      const knee = new THREE.Group();
      knee.position.y = -THIGH;
      hip.add(knee);
      mesh(g.shin, tm.socks, knee);
      const ankle = new THREE.Group();
      ankle.position.y = -SHIN;
      knee.add(ankle);
      mesh(g.foot, tm.cleat, ankle);
      mesh(g.sole, tm.sole, ankle);
      limbs[side] = { sh, elbow, hip, knee, ankle };
    }
    this.limbs = limbs;

    // Ball carry anchor: right forearm, ball cradled against the chest.
    this.carryAnchor = new THREE.Group();
    this.carryAnchor.position.set(0.03, -0.17, 0.06);
    this.carryAnchor.rotation.set(0.1, 0, -0.15);
    limbs.R.elbow.add(this.carryAnchor);
    this.handAnchor = new THREE.Group();
    this.handAnchor.position.set(0, -FORE - 0.06, 0.04);
    limbs.R.elbow.add(this.handAnchor);

    this.pose = basePose();
    this.target = basePose();
    this.phase = Math.random() * Math.PI * 2;
    this.breath = Math.random() * 10;
    this.ground = true;
    this._v = new THREE.Vector3();
  }

  // anim: { mode, speed (yd/s along facing, can be negative), maxSpeed, t, accel, carry, lean }
  animate(anim, dt) {
    const p = this.target;
    Object.assign(p, basePose());
    const mode = anim.mode || 'idle';
    let rate = 14;
    this.ground = true;
    this.breath += dt;
    p.spineX += Math.sin(this.breath * 1.6) * 0.012;

    const speed = anim.speed || 0;
    const sr = Math.min(1, Math.abs(speed) / 9.5);
    if (mode === 'run' || mode === 'carry' || mode === 'block' || mode === 'backpedal') {
      const stride = 1.7 + 3.2 * sr;
      this.phase += (speed * dt / stride) * Math.PI * 2;
      const ph = this.phase;
      if (Math.abs(speed) > 0.25) {
        const s = sr;
        const A = 0.22 + 0.6 * s;
        const sw = Math.sin(ph);
        p.hipXL = -A * sw - 0.12 * s;
        p.hipXR = A * sw - 0.12 * s;
        const kl = Math.max(0, Math.cos(ph)), kr = Math.max(0, -Math.cos(ph));
        p.kneeL = 0.18 + (0.35 + 1.35 * s) * Math.pow(kl, 1.3) + 0.15 * s;
        p.kneeR = 0.18 + (0.35 + 1.35 * s) * Math.pow(kr, 1.3) + 0.15 * s;
        const arm = 0.25 + 0.75 * s;
        p.shXL = arm * sw;
        p.shXR = -arm * sw;
        p.elbL = p.elbR = -(1.15 + 0.35 * s);
        p.spineX = 0.08 + 0.26 * s + (anim.accel || 0) * 0.02;
        p.spineY = -0.14 * s * sw;
        p.pelvisYaw = 0.1 * s * sw;
        p.pelvisY = HIP_Y - 0.04 - 0.07 * s + 0.045 * s * Math.cos(2 * ph);
        p.headX = -p.spineX * 0.7;
        rate = 26;
      } else {
        p.kneeL = p.kneeR = 0.2;
        p.pelvisY = HIP_Y - 0.05;
      }
      if (mode === 'backpedal') {
        p.spineX = 0.32;
        p.pelvisY -= 0.1;
        p.kneeL += 0.3; p.kneeR += 0.3;
        p.hipXL -= 0.35; p.hipXR -= 0.35;
        p.shXL = p.shXR = -0.3;
        p.elbL = p.elbR = -1.3;
        p.headX = -0.3;
      }
      if (mode === 'carry') {
        p.shXR = -0.22; p.elbR = -1.7; p.shZR = 0.16;
      }
      if (mode === 'block') {
        p.spineX = 0.5;
        p.pelvisY -= 0.14;
        p.kneeL += 0.45; p.kneeR += 0.45;
        p.hipXL -= 0.45; p.hipXR -= 0.45;
        p.shXL = p.shXR = -1.25;
        p.shZL = 0.35; p.shZR = -0.35;
        p.elbL = p.elbR = -0.75;
        p.headX = -0.45;
        rate = 20;
      }
    } else if (mode === 'stance3') {
      p.pelvisY = 0.7; p.spineX = 1.3; p.headX = -1.0;
      p.hipXL = -1.25; p.hipXR = -1.45; p.kneeL = 1.85; p.kneeR = 2.15;
      p.hipZL = 0.18; p.hipZR = -0.18;
      p.shXR = -1.32; p.elbR = -0.05; p.shZR = -0.05;
      p.shXL = -0.85; p.elbL = -1.4; p.shZL = 0.3;
      this.ground = true;
    } else if (mode === 'stance2') {
      p.pelvisY = 0.84; p.spineX = 0.62; p.headX = -0.55;
      p.hipXL = -0.85; p.hipXR = -0.4; p.kneeL = 1.05; p.kneeR = 0.85;
      p.shXL = p.shXR = -0.55; p.elbL = p.elbR = -0.9; p.shZL = 0.25; p.shZR = -0.25;
    } else if (mode === 'lbStance') {
      p.pelvisY = 0.82; p.spineX = 0.5; p.headX = -0.45;
      p.hipXL = p.hipXR = -0.75; p.kneeL = p.kneeR = 1.05;
      p.hipZL = 0.22; p.hipZR = -0.22;
      p.shXL = p.shXR = -0.9; p.elbL = p.elbR = -0.6; p.shZL = 0.3; p.shZR = -0.3;
    } else if (mode === 'qbGun') {
      p.pelvisY = 0.94; p.spineX = 0.32; p.headX = -0.3;
      p.hipXL = p.hipXR = -0.38; p.kneeL = p.kneeR = 0.6;
      p.hipZL = 0.12; p.hipZR = -0.12;
      p.shXL = p.shXR = -0.9; p.elbL = p.elbR = -0.9; p.shZL = 0.2; p.shZR = -0.2;
    } else if (mode === 'qbUnder') {
      p.pelvisY = 0.86; p.spineX = 0.55; p.headX = -0.5;
      p.hipXL = p.hipXR = -0.55; p.kneeL = p.kneeR = 0.95;
      p.hipZL = 0.15; p.hipZR = -0.15;
      p.shXL = p.shXR = -1.2; p.elbL = p.elbR = -0.35; p.shZL = 0.1; p.shZR = -0.1;
    } else if (mode === 'center') {
      p.pelvisY = 0.72; p.spineX = 1.25; p.headX = -1.0;
      p.hipXL = p.hipXR = -1.35; p.kneeL = p.kneeR = 2.0; p.hipZL = 0.3; p.hipZR = -0.3;
      p.shXR = -1.3; p.elbR = -0.1; p.shXL = -1.0; p.elbL = -1.0; p.shZL = 0.3;
    } else if (mode === 'throw') {
      const t = anim.t;
      p.pelvisY = HIP_Y - 0.06;
      p.hipXL = -0.35; p.hipXR = 0.18; p.kneeL = 0.25; p.kneeR = 0.3;
      if (t < 0.55) {
        const k = t / 0.55;
        p.shZR = -1.45 * k; p.shXR = 0.35 * k; p.elbR = -1.75;
        p.shXL = -1.2 * k; p.elbL = -0.5;
        p.spineY = 0.55 * k; p.spineX = 0.0;
        p.headY = -0.45 * k;
      } else {
        const k = (t - 0.55) / 0.45;
        p.shZR = -1.45 + 0.4 * k; p.shXR = 0.35 - 1.7 * k; p.elbR = -1.75 + 1.5 * k;
        p.shXL = -1.2 + 0.9 * k; p.shZL = 0.3 + 0.4 * k; p.elbL = -1.4;
        p.spineY = 0.55 - 1.05 * k; p.spineX = 0.3 * k;
        p.headY = -0.45 + 0.45 * k;
      }
      rate = 40;
    } else if (mode === 'catch') {
      p.shXL = p.shXR = -2.6; p.elbL = p.elbR = -0.45; p.shZL = 0.15; p.shZR = -0.15;
      p.spineX = -0.05; p.headX = -0.4;
      rate = 22;
    } else if (mode === 'down' || mode === 'dive') {
      const t = Math.min(1, anim.t);
      const k = 1 - Math.pow(1 - t, 2.2);
      p.rootX = (anim.backward ? -1 : 1) * (Math.PI / 2 - 0.08) * k;
      p.rootZ = (anim.roll || 0) * k;
      p.shXL = p.shXR = -2.4 * k; p.elbL = p.elbR = -0.6;
      p.hipXL = p.hipXR = -0.1; p.kneeL = 0.5 * k; p.kneeR = 0.8 * k;
      p.headX = -0.6 * k;
      if (anim.carry) { p.shXR = -0.22; p.elbR = -1.7; }
      this.ground = false;
      rate = 18;
    } else if (mode === 'kneel') {
      p.pelvisY = 0.6; p.spineX = 0.2;
      p.hipXL = -1.45; p.kneeL = 1.5; p.hipXR = 0.25; p.kneeR = 1.85;
      p.shXL = p.shXR = -1.1; p.elbL = p.elbR = -0.6;
      this.ground = false;
    } else if (mode === 'kick') {
      const t = Math.min(1, anim.t);
      p.pelvisY = HIP_Y - 0.03;
      const sw = Math.sin(t * Math.PI);
      p.hipXR = 0.8 - 2.4 * t; p.kneeR = 1.4 * (1 - t) + 0.1;
      p.hipXL = -0.2; p.kneeL = 0.3;
      p.shZL = 1.1 * sw + 0.2; p.shZR = -0.6 * sw - 0.2;
      p.spineX = -0.2 * sw;
      rate = 30;
    } else if (mode === 'celebrate') {
      const t = this.breath * 6;
      p.shXL = p.shXR = -2.9 + Math.sin(t) * 0.15;
      p.shZL = 0.35; p.shZR = -0.35;
      p.elbL = p.elbR = -0.3;
      p.pelvisY = HIP_Y - 0.03 + Math.max(0, Math.sin(t * 0.5)) * 0.12;
      this.ground = false;
      p.rootY = Math.max(0, Math.sin(t * 0.5)) * 0.18;
    } else if (mode === 'handsKnees') {
      p.pelvisY = 0.9; p.spineX = 0.75; p.hipXL = p.hipXR = -0.6; p.kneeL = p.kneeR = 0.7;
      p.shXL = p.shXR = -0.4; p.elbL = p.elbR = -0.2; p.shZL = 0.1; p.shZR = -0.1; p.headX = -0.6;
    } else if (mode === 'hold') {
      p.pelvisY = 0.6; p.spineX = 0.45;
      p.hipXL = -1.45; p.kneeL = 1.55; p.hipXR = 0.3; p.kneeR = 1.9;
      p.shXR = -1.4; p.elbR = -0.2; p.shXL = -1.1; p.elbL = -0.4;
      this.ground = false;
    } else if (mode === 'stiffarm') {
      p.shXL = -1.5; p.elbL = 0; p.shZL = 0.2;
      p.shXR = -0.22; p.elbR = -1.7; p.shZR = 0.16;
      p.spineX = 0.3; p.pelvisY = HIP_Y - 0.08;
      rate = 30;
    }
    if (anim.carry && mode !== 'down' && mode !== 'dive') {
      p.shXR = -0.22; p.elbR = -1.7; p.shZR = 0.16;
    }
    if (anim.lookYaw) p.headY += anim.lookYaw;

    for (const k of POSE_KEYS) this.pose[k] = damp(this.pose[k], p[k], rate, dt);
    this.apply();
  }

  apply() {
    const q = this.pose;
    this.pelvis.position.y = q.pelvisY;
    this.pelvis.rotation.y = q.pelvisYaw;
    this.spine.rotation.set(q.spineX, q.spineY - q.pelvisYaw, q.spineZ);
    this.head.rotation.set(q.headX, q.headY, 0);
    const L = this.limbs.L, Rr = this.limbs.R;
    L.hip.rotation.set(q.hipXL, 0, q.hipZL);
    Rr.hip.rotation.set(q.hipXR, 0, q.hipZR);
    L.knee.rotation.x = q.kneeL;
    Rr.knee.rotation.x = q.kneeR;
    L.ankle.rotation.x = -(q.hipXL + q.kneeL) * 0.6;
    Rr.ankle.rotation.x = -(q.hipXR + q.kneeR) * 0.6;
    L.sh.rotation.set(q.shXL, 0, q.shZL);
    Rr.sh.rotation.set(q.shXR, 0, q.shZR);
    L.elbow.rotation.x = q.elbL;
    Rr.elbow.rotation.x = q.elbR;
    this.body.rotation.set(q.rootX, 0, q.rootZ);
    this.body.position.y = q.rootY;
    // Pull the lowest foot onto the turf for planted poses.
    if (this.ground && Math.abs(q.rootX) < 0.05) {
      this.root.updateMatrixWorld(true);
      const yl = L.ankle.getWorldPosition(this._v).y;
      const yr = Rr.ankle.getWorldPosition(this._v).y;
      const low = Math.min(yl, yr) - this.root.position.y;
      const want = 0.075 * this.body.scale.y;
      this.body.position.y += Math.max(-0.2, Math.min(0.12, want - low)) * 0.6;
    }
  }

  setTransform(x, z, heading) {
    this.root.position.set(x, 0, z);
    // heading is the world angle of travel in the xz plane (atan2(z, x)).
    this.root.rotation.y = Math.atan2(Math.cos(heading), Math.sin(heading));
  }

  dispose() {
    this.jerseyMat.map?.dispose();
    this.jerseyMat.dispose();
  }
}

export function headingToYaw(h) {
  return Math.atan2(Math.cos(h), Math.sin(h));
}
