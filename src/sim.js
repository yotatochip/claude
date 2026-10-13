// Live-play simulation: 22 athletes, blocking, routes, coverage, passing and tackling.
import * as THREE from 'three';
import { FORMATIONS, routeFor } from './data.js';
import { clamp, lerp, angleDiff, dampAngle, rand, chance, gaussian, FIELD } from './util.js';
import { GRAVITY } from './ball.js';

const HW = FIELD.halfWidth;
const OFF_SLOTS = ['QB', 'RB', 'FB', 'X', 'Z', 'SL', 'SL2', 'TE', 'LT', 'LG', 'C', 'RG', 'RT'];
const DEF_SLOTS = ['LE', 'DT1', 'DT2', 'RE', 'WILL', 'MIKE', 'CB1', 'CB2', 'NB', 'FS', 'SS'];
const ELIGIBLE = ['RB', 'FB', 'X', 'Z', 'SL', 'SL2', 'TE'];
const GLYPH_PREF = { X: 'tri', Z: 'circle', SL: 'square', TE: 'cross', SL2: 'cross', RB: 'r1', FB: 'square' };
const GLYPHS = ['tri', 'circle', 'square', 'cross', 'r1'];

const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
const KICK_REC = {
  kickoff: ['LE', 'DT1', 'RE', 'MIKE', 'WILL', 'TE', 'FB', 'NB', 'SS', 'CB1', 'RB'],
  punt: ['LE', 'DT1', 'DT2', 'RE', 'MIKE', 'WILL', 'CB1', 'CB2', 'NB', 'SS', 'FS'],
  fg: ['LE', 'DT1', 'DT2', 'RE', 'MIKE', 'WILL', 'NB', 'SS', 'CB1', 'CB2', 'FS'],
};
KICK_REC.pat = KICK_REC.fg;

export class Athlete {
  constructor(info, team, teamKey, model) {
    this.info = info;
    this.slot = info.slot;
    this.pos = info.pos;
    this.team = team;
    this.teamKey = teamKey; // 'home' | 'away'
    this.model = model;
    this.p = { x: 0, z: 0 };
    this.v = { x: 0, z: 0 };
    this.h = 0;
    this.r = { ...info.rat };
    this.reset();
  }
  reset() {
    this.job = null;
    this.side = null;
    this.active = false;
    this.engaged = null;
    this.shed = 0;
    this.immune = null;
    this.immuneT = 0;
    this.stun = 0;
    this.down = false;
    this.downT = 0;
    this.downDur = 0;
    this.anim = 'idle';
    this.animT = 0;
    this.lookYaw = 0;
    this.tackleCd = 0;
    this.juke = 0;
    this.stiff = 0;
    this.moveCd = 0;
    this.user = false;
    this.celebrate = false;
    this.estV = { x: 0, z: 0 };
    this.want = { x: 0, z: 0 };
    this.sprint = true;
    this.speedCap = 1;
    this.facingLock = null;
  }
  get maxSpeed() { return this.r.spd * this.speedCap; }
  get accel() { return 8 + (this.r.spd - 7) * 1.6; }
}

export class PlaySim {
  constructor(world) {
    this.world = world; // { scene, ball, field }
    this.athletes = [];
    this.byTeam = { home: {}, away: {} };
    this.listeners = [];
    this.phase = 'idle';
    this.t = 0;
    this._tmp = new THREE.Vector3();
    this.icons = [];
  }

  on(fn) { this.listeners.push(fn); }
  emit(type, data = {}) { for (const fn of this.listeners) fn(type, data); }

  addAthlete(a) {
    this.athletes.push(a);
    this.byTeam[a.teamKey][a.slot] = a;
    this.world.scene.add(a.model.root);
    a.model.root.visible = false;
  }

  // ------------------------------------------------------------ helpers
  W(u, v) { return { x: this.los + this.dir * u, z: this.ballZ + this.dir * v }; }
  L(p) { return { u: (p.x - this.los) * this.dir, v: (p.z - this.ballZ) * this.dir }; }
  goalU() { return FIELD.goal - this.los * this.dir; } // yards from LOS to the goal line

  // ------------------------------------------------------------ setup
  // Assign who is on the field and where they line up. Players jog from where they are.
  setupPlay({ offKey, defKey, los, dir, ballZ, play, defPlay, userKey, firstDownX }) {
    this.offKey = offKey; this.defKey = defKey;
    this.los = los; this.dir = dir; this.ballZ = ballZ;
    this.play = play; this.defPlay = defPlay;
    this.userKey = userKey;
    this.firstDownX = firstDownX;
    this.phase = 'align';
    this.t = 0;
    this.alignT = 0;
    this.result = null;
    this.carrier = null;
    this.passTarget = null;
    this.thrown = false;
    this.handedOff = false;
    this.crossedLos = false;
    this.runRead = false;
    this.ballState = 'center';
    this.kick = null;
    this.userAthlete = null;
    this.turnover = false;
    this.catchSpot = null;
    this.fakeT = 0;
    this.cpuNextLook = 0;
    this.pass = null;
    this.passT = 0;
    this.huddle = null;
    const wasActive = new Set(this.athletes.filter((a) => a.active));

    const formation = FORMATIONS[play.formation];
    const off = this.byTeam[offKey], def = this.byTeam[defKey];
    for (const a of this.athletes) { a.reset(); }
    this.off = [];
    this.def = [];
    const offSlots = ['QB', 'LT', 'LG', 'C', 'RG', 'RT', ...Object.keys(formation.spots)];
    const spots = { LT: [-0.75, -2.7], LG: [-0.75, -1.35], C: [-0.55, 0], RG: [-0.75, 1.35], RT: [-0.75, 2.7], QB: formation.qb, ...formation.spots };
    for (const slot of offSlots) {
      const a = off[slot];
      a.side = 'off'; a.active = true; a.align = { u: spots[slot][0], v: spots[slot][1] };
      this.off.push(a);
    }
    for (const slot of DEF_SLOTS) {
      const a = def[slot];
      a.side = 'def'; a.active = true;
      this.def.push(a);
    }
    for (const a of this.athletes) {
      a.model.root.visible = a.active;
      if (a.active && !wasActive.has(a)) {
        // Substitutes jog in from their own sideline.
        const benchZ = (a.teamKey === 'home' ? 1 : -1) * (HW + 5);
        a.p.x = los + rand(-8, 8);
        a.p.z = benchZ;
        a.v.x = a.v.z = 0;
      }
    }
    this.qb = off.QB;
    this.center = off.C;
    this.receivers = this.off.filter((a) => ELIGIBLE.includes(a.slot));
    this.alignDefense();
    this.assignIcons();
    // Offense on the ball first: positions to jog to.
    for (const a of [...this.off, ...this.def]) {
      const w = this.W(a.align.u, a.align.v);
      a.target = w;
      a.anim = 'run';
      // Units coming on from far away start their jog from a sensible distance.
      const d = dist(a.p, w);
      if (d > 12) {
        const k = 9 / d;
        a.p.x = w.x + (a.p.x - w.x) * k;
        a.p.z = w.z + (a.p.z - w.z) * k;
      }
    }
    this.world.ball.place(this.los + this.dir * 0.15, 0.12, this.ballZ, this.dir > 0 ? Math.PI / 2 : -Math.PI / 2);
    // The user starts on the quarterback, or the middle linebacker on defense.
    const start = userKey === offKey ? off.QB : def.MIKE;
    start.user = true;
    this.userAthlete = start;
  }

  // First appearance (kickoff, start of a game): drop everyone straight on their spots.
  snapToAlignment() {
    for (const a of [...this.off, ...this.def]) {
      const w = this.W(a.align.u, a.align.v);
      a.p.x = w.x; a.p.z = w.z;
      a.v.x = a.v.z = 0;
      a.h = a.side === 'off' ? (this.dir > 0 ? 0 : Math.PI) : (this.dir > 0 ? Math.PI : 0);
    }
  }

  assignIcons() {
    const used = new Set();
    const order = ['X', 'Z', 'SL', 'TE', 'SL2', 'RB', 'FB'];
    this.icons = [];
    for (const slot of order) {
      const a = this.receivers.find((r) => r.slot === slot);
      if (!a) continue;
      let g = GLYPH_PREF[slot];
      if (used.has(g)) g = GLYPHS.find((x) => !used.has(x));
      used.add(g);
      a.glyph = g;
    }
    // Keyboard numbers: left to right as seen from behind the offense.
    const sorted = [...this.receivers].sort((a, b) => a.align.v - b.align.v);
    sorted.forEach((a, i) => { a.key = i + 1; });
    this.icons = sorted;
  }

  alignDefense() {
    const d = this.byTeam[this.defKey];
    const dp = this.defPlay;
    const cov = dp.coverage;
    const recs = [...this.receivers].sort((a, b) => a.align.v - b.align.v);
    const wide = recs.filter((r) => r.slot !== 'RB' && r.slot !== 'FB');
    const left = wide.filter((r) => r.align.v < 0), right = wide.filter((r) => r.align.v >= 0);
    const strongRight = right.length >= left.length;
    const s = strongRight ? 1 : -1;
    const press = cov === 'cover0' || cov === 'cover1';
    // Front four.
    d.LE.align = { u: 1.0, v: -3.7 };
    d.DT1.align = { u: 0.9, v: -1.0 };
    d.DT2.align = { u: 0.9, v: 1.1 };
    d.RE.align = { u: 1.0, v: 3.8 };
    // Linebackers.
    d.WILL.align = { u: 4.8, v: -2.4 * s };
    d.MIKE.align = { u: 5.0, v: 1.4 * s };
    // Corners on the outside receivers.
    const outL = left[0] || { align: { u: 0, v: -11 } };
    const outR = right[right.length - 1] || { align: { u: 0, v: 11 } };
    d.CB1.align = { u: press ? 1.6 : 6.5, v: outL.align.v + 0.9 };
    d.CB2.align = { u: press ? 1.6 : 6.5, v: outR.align.v - 0.9 };
    // Nickel over the slot to the strong side.
    const strongSide = strongRight ? right : left;
    const slot = strongSide.length > 1 ? strongSide[strongRight ? strongSide.length - 2 : 1] : null;
    d.NB.align = slot ? { u: press ? 2.2 : 5, v: slot.align.v - s * 0.8 } : { u: 4.5, v: 5 * s };
    // Safeties.
    if (cov === 'cover2' || cov === 'cover4') {
      d.FS.align = { u: 12.5, v: -8 }; d.SS.align = { u: 12.5, v: 8 };
    } else if (cov === 'cover0') {
      d.FS.align = { u: 7, v: -3 * s }; d.SS.align = { u: 6, v: 4 * s };
    } else {
      d.FS.align = { u: 13.5, v: 0 }; d.SS.align = { u: 7.5, v: 6 * s };
    }
    // Man assignments.
    const man = {};
    const pool = [...recs];
    const take = (slotName, rec) => { if (rec && pool.includes(rec)) { man[slotName] = rec; pool.splice(pool.indexOf(rec), 1); } };
    take('CB1', outL.slot ? outL : null);
    take('CB2', outR.slot ? outR : null);
    take('NB', slot);
    const te = pool.find((r) => r.slot === 'TE') || pool.find((r) => r.slot !== 'RB' && r.slot !== 'FB');
    take('SS', te);
    const back = pool.find((r) => r.slot === 'RB') || pool[0];
    take('MIKE', back);
    if (pool.length) take('WILL', pool[0]);
    if (pool.length) take('FS', pool[0]);
    this.man = man;
    this.zones = this.zoneMap(cov, s);
    this.blitzers = new Set(dp.blitz);
    if (cov === 'cover0' && !this.blitzers.has('WILL') && !man.WILL) this.blitzers.add('WILL');
  }

  zoneMap(cov, s) {
    const goalU = this.goalU();
    const deep = (u) => Math.min(u, goalU + 2);
    if (cov === 'cover3') return {
      CB1: { u: deep(16), v: -13, r: 9 }, FS: { u: deep(18), v: 0, r: 10 }, CB2: { u: deep(16), v: 13, r: 9 },
      NB: { u: 6, v: 11 * s, r: 7 }, SS: { u: 6, v: -11 * s, r: 7 }, MIKE: { u: 7, v: 3 * s, r: 6 }, WILL: { u: 7, v: -3 * s, r: 6 },
    };
    if (cov === 'cover2') return {
      FS: { u: deep(18), v: -10, r: 11 }, SS: { u: deep(18), v: 10, r: 11 }, CB1: { u: 4, v: -13, r: 7 }, CB2: { u: 4, v: 13, r: 7 },
      MIKE: { u: deep(13), v: 0, r: 8 }, WILL: { u: 7, v: -5 * s, r: 6 }, NB: { u: 7, v: 5 * s, r: 6 },
    };
    if (cov === 'cover4') return {
      CB1: { u: deep(16), v: -14, r: 8 }, CB2: { u: deep(16), v: 14, r: 8 }, FS: { u: deep(16), v: -5, r: 8 }, SS: { u: deep(16), v: 5, r: 8 },
      NB: { u: 5, v: 10 * s, r: 7 }, MIKE: { u: 7, v: 2 * s, r: 6 }, WILL: { u: 6, v: -9 * s, r: 7 },
    };
    if (cov === 'cover1') return { FS: { u: deep(18), v: 0, r: 14 } };
    return {};
  }

  // ------------------------------------------------------------ snap
  snap() {
    if (this.phase !== 'set') return;
    this.phase = 'live';
    this.t = 0;
    this.ballState = 'snap';
    const play = this.play;
    const qbU = FORMATIONS[play.formation].qb[0];
    this.shotgun = qbU < -2.5;
    const ball = this.world.ball;
    if (this.shotgun) {
      const from = new THREE.Vector3(this.center.p.x, 0.4, this.center.p.z);
      const to = new THREE.Vector3(this.qb.p.x, 1.25, this.qb.p.z);
      ball.launch(from, to, 0.32, 'spiral');
      this.snapT = 0.32;
    } else {
      this.snapT = 0.05;
    }
    this.assignJobs();
    this.emit('snap');
  }

  assignJobs() {
    const play = this.play;
    const run = play.type === 'run';
    const pa = play.type === 'pa';
    // Offense
    for (const a of this.off) {
      a.anim = 'run';
      if (['LT', 'LG', 'C', 'RG', 'RT'].includes(a.slot)) a.job = { type: 'ol', run, target: null };
    }
    const qb = this.qb;
    const dropU = this.shotgun ? -6.6 : (pa ? -8 : -7.2);
    if (run || pa) {
      const rb = this.byTeam[this.offKey].RB;
      const hole = run ? play.runTo : 1.2;
      const mesh = this.shotgun ? { u: -5.0, v: 0.6 * Math.sign(hole || 1) } : { u: -3.6, v: 0.4 * Math.sign(hole || 1) };
      qb.job = { type: 'qb', phase: 'mesh', mesh, dropU, keep: pa };
      rb.job = { type: 'rbRun', mesh, hole: { u: 1.0, v: hole }, fake: pa };
    } else {
      qb.job = { type: 'qb', phase: 'drop', dropU };
    }
    for (const a of this.receivers) {
      if (a.job) continue;
      const rname = play.routes[a.slot];
      const route = rname ? routeFor(rname) : null;
      if (a.slot === 'FB' && play.lead) { a.job = { type: 'lead', hole: play.runTo }; continue; }
      if (!route) {
        if (run) a.job = { type: 'stalk', target: null };
        else a.job = { type: 'protect' };
        continue;
      }
      const side = a.align.v === 0 ? 1 : Math.sign(a.align.v);
      const maxU = this.goalU() + 8;
      const pts = route.map(([du, dOut]) => {
        const u = Math.min(du, maxU);
        let v = a.align.v + side * dOut;
        const w = this.W(u, v);
        w.z = clamp(w.z, -HW + 1.2, HW - 1.2);
        return w;
      });
      const last = route[route.length - 1], prev = route[route.length - 2] || [0, 0];
      const settle = Math.hypot(last[0] - prev[0], last[1] - prev[1]) < 3;
      a.job = { type: 'route', pts, i: 0, settle, name: rname, depth: Math.max(...route.map((r) => r[0])) };
    }
    // Defense
    const run2 = run;
    for (const a of this.def) {
      const dl = ['LE', 'DT1', 'DT2', 'RE'].includes(a.slot);
      if (dl || this.blitzers.has(a.slot)) { a.job = { type: 'rush', lane: a.align.v * 0.5 }; continue; }
      const cov = this.defPlay.coverage;
      if (this.man[a.slot] && (cov === 'cover1' || cov === 'cover0')) {
        a.job = { type: 'man', target: this.man[a.slot] };
      } else if (this.zones[a.slot]) {
        const z = this.zones[a.slot];
        a.job = { type: 'zone', zone: this.W(z.u, z.v), r: z.r, zu: z.u };
      } else if (this.man[a.slot]) {
        a.job = { type: 'man', target: this.man[a.slot] };
      } else {
        a.job = { type: 'zone', zone: this.W(6, a.align.v), r: 6, zu: 6 };
      }
      a.react = 0.15 + (1 - a.r.awr) * 0.9 + rand(0, 0.15);
    }
    this.assignBlocks(run2);
  }

  assignBlocks(run) {
    const ol = this.off.filter((a) => a.job?.type === 'ol');
    const rushers = this.def.filter((a) => a.job?.type === 'rush');
    const front = run
      ? this.def.filter((d) => { const l = this.L(d.p); return l.u < 7.5 && Math.abs(l.v) < 7; })
      : rushers;
    // Greedy matching on lateral distance so every rusher gets a blocker before anyone doubles.
    const pairs = [];
    for (const o of ol) {
      const ov = this.L(o.p).v;
      for (const d of front) {
        const l = this.L(d.p);
        pairs.push({ o, d, cost: Math.abs(l.v - ov) + Math.max(0, l.u - 2) * 0.45 });
      }
    }
    pairs.sort((a, b) => a.cost - b.cost);
    const usedO = new Set(), usedD = new Set();
    for (const { o, d } of pairs) {
      if (usedO.has(o) || usedD.has(d)) continue;
      o.job.target = d;
      usedO.add(o); usedD.add(d);
    }
    // Spare linemen help on the nearest rusher.
    for (const o of ol) {
      if (o.job.target) continue;
      o.job.target = this.nearestTo(o, front.length ? front : this.def);
    }
    // Backs / tight ends left in to protect pick up any free rusher.
    for (const p of this.off.filter((a) => a.job?.type === 'protect')) {
      const free = rushers.find((r) => !usedD.has(r));
      if (free) { p.job.target = free; usedD.add(free); }
    }
  }

  // ------------------------------------------------------------ update
  update(dt, ctrl) {
    if (this.phase === 'idle') return;
    if (this.phase === 'align' || this.phase === 'set') this.updateAlign(dt);
    else if (this.phase === 'live') this.updateLive(dt, ctrl);
    else if (this.phase === 'post') this.updatePost(dt);
    else if (this.phase === 'kick') this.updateKick(dt);
    this.integrateModels(dt);
  }

  updateAlign(dt) {
    this.alignT += dt;
    let allSet = true;
    for (const a of [...this.off, ...this.def]) {
      const d = dist(a.p, a.target);
      const faceH = a.side === 'off' ? (this.dir > 0 ? 0 : Math.PI) : (this.dir > 0 ? Math.PI : 0);
      if (d > 0.15) {
        allSet = false;
        if (this.alignT > 7) {
          // Stragglers: put them on their mark so the play can start.
          a.p.x = a.target.x; a.p.z = a.target.z;
          continue;
        }
        const sp = Math.min(a.maxSpeed * 0.8, 2 + d * 1.5);
        this.steer(a, (a.target.x - a.p.x) / d * sp, (a.target.z - a.p.z) / d * sp, dt, 10);
        if (d < 1.5) a.h = dampAngle(a.h, faceH, 6, dt);
        a.anim = 'run';
      } else {
        a.v.x *= 0.8; a.v.z *= 0.8;
        a.p.x = lerp(a.p.x, a.target.x, 0.2);
        a.p.z = lerp(a.p.z, a.target.z, 0.2);
        a.h = dampAngle(a.h, faceH, 8, dt);
        a.anim = this.stanceFor(a);
      }
    }
    if (allSet || this.alignT > 7.1) {
      if (this.phase === 'align') {
        this.phase = 'set';
        this.emit('set');
      }
    }
  }

  stanceFor(a) {
    if (a.side === 'off') {
      if (a.slot === 'C') return 'center';
      if (['LT', 'LG', 'RG', 'RT'].includes(a.slot)) return 'stance3';
      if (a.slot === 'QB') return this.shotgunAlign() ? 'qbGun' : 'qbUnder';
      if (a.slot === 'RB' || a.slot === 'FB') return 'handsKnees';
      if (a.slot === 'TE') return 'stance3';
      return 'stance2';
    }
    if (['LE', 'DT1', 'DT2', 'RE'].includes(a.slot)) return 'stance3';
    if (a.slot === 'MIKE' || a.slot === 'WILL') return 'lbStance';
    return 'stance2';
  }

  shotgunAlign() { return FORMATIONS[this.play.formation].qb[0] < -2.5; }

  steer(a, vx, vz, dt, accelOverride) {
    const acc = (accelOverride || a.accel) * dt;
    let dx = vx - a.v.x, dz = vz - a.v.z;
    const dl = Math.hypot(dx, dz);
    if (dl > acc) { dx *= acc / dl; dz *= acc / dl; }
    a.v.x += dx; a.v.z += dz;
    const sp = Math.hypot(a.v.x, a.v.z);
    const cap = a.maxSpeed * (a.stun > 0 ? 0.45 : 1);
    if (sp > cap) { a.v.x *= cap / sp; a.v.z *= cap / sp; }
    a.p.x += a.v.x * dt;
    a.p.z += a.v.z * dt;
  }

  seek(a, tx, tz, dt, speedFrac = 1, arrive = 1.2) {
    const dx = tx - a.p.x, dz = tz - a.p.z;
    const d = Math.hypot(dx, dz);
    if (d < 0.05) { this.steer(a, 0, 0, dt); return d; }
    let sp = a.maxSpeed * speedFrac;
    if (d < arrive) sp *= d / arrive;
    this.steer(a, (dx / d) * sp, (dz / d) * sp, dt);
    return d;
  }

  updateLive(dt, ctrl) {
    this.t += dt;
    const ball = this.world.ball;
    for (const a of this.athletes) {
      if (!a.active) continue;
      a.stun = Math.max(0, a.stun - dt);
      a.tackleCd = Math.max(0, a.tackleCd - dt);
      a.juke = Math.max(0, a.juke - dt);
      a.stiff = Math.max(0, a.stiff - dt);
      a.moveCd = Math.max(0, a.moveCd - dt);
      if (a.immuneT > 0) { a.immuneT -= dt; if (a.immuneT <= 0) a.immune = null; }
      if (a.down) {
        a.downT += dt;
        a.v.x *= 0.9; a.v.z *= 0.9;
        a.p.x += a.v.x * dt; a.p.z += a.v.z * dt;
        if (a.downDur > 0 && a.downT > a.downDur) { a.down = false; a.stun = 0.5; }
      }
    }

    // Snap travel.
    if (this.ballState === 'snap') {
      ball.update(dt);
      if (this.t >= this.snapT) {
        this.ballState = 'qb';
        this.giveBall(this.qb, false);
      }
    }

    this.updateUserSelection(ctrl);

    // Ball in the air.
    if (this.ballState === 'air') {
      ball.update(dt);
      this.passT += dt;
      if (this.passT >= this.pass.T) this.resolveCatch();
      else if (this.passT > this.pass.T - 0.25) this.preCatchAnims();
    }

    // Jobs.
    for (const a of [...this.off, ...this.def]) {
      if (a.down || a.engaged) continue;
      if (a.user && this.userDrive(a, ctrl, dt)) continue;
      this.think(a, dt);
    }
    this.updateBlocks(dt);
    this.separate();
    this.checkCarrier(dt);

    // QB decisions.
    if (this.ballState === 'qb' && this.carrier === this.qb && !this.result) {
      if (this.userKey === this.offKey) this.userQb(ctrl);
      else this.cpuQb();
    }
  }

  // Which athlete the user steers.
  updateUserSelection(ctrl) {
    const prev = this.userAthlete;
    const mine = (a) => a && a.teamKey === this.userKey;
    let next = prev;
    const switching = !!ctrl?.switch;
    if (this.carrier && mine(this.carrier)) {
      next = this.carrier;
    } else if (this.ballState === 'air') {
      if (this.offKey === this.userKey) next = this.passTarget || prev;
      else if (switching || !mine(prev)) next = this.nearestTo({ p: this.pass.target }, this.def.filter((a) => !a.down));
    } else if (this.carrier) {
      if (switching || !mine(prev) || prev.down) {
        next = this.nearestTo(this.carrier, this.athletes.filter((a) => a.active && mine(a) && !a.down));
      }
    } else if (!mine(prev)) {
      next = this.byTeam[this.userKey].MIKE;
    }
    if (next !== prev) {
      if (prev) prev.user = false;
      if (next) { next.user = true; next.userTook = false; }
      this.userAthlete = next;
    }
    if (ctrl) ctrl.switch = false;
  }

  nearestTo(ref, list) {
    let best = null, bd = 1e9;
    for (const a of list) {
      const d = dist(a.p, ref.p);
      if (d < bd) { bd = d; best = a; }
    }
    return best;
  }

  // Returns true if the user moved this athlete this frame.
  userDrive(a, ctrl, dt) {
    if (!ctrl) return false;
    const m = ctrl.move;
    const mag = Math.hypot(m.x, m.z);
    if (!a.userTook) {
      if (mag > 0.2 || ctrl.dive || ctrl.juke || ctrl.stiff) a.userTook = true;
      else return false;
    }
    // Dropping back QB: user steering cancels the scripted drop.
    if (a === this.qb && a.job?.type === 'qb' && a.job.phase === 'mesh') return false;
    if (a.job?.type === 'rbRun' && !a.job.got) return false;
    const sprint = ctrl.sprint ? 1 : 0.84;
    const sp = a.maxSpeed * sprint * Math.min(1, mag);
    if (mag > 0.08) this.steer(a, (m.x / mag) * sp, (m.z / mag) * sp, dt, a.accel * 1.15);
    else this.steer(a, 0, 0, dt, a.accel * 1.3);
    // Moves.
    if (a === this.carrier && a.moveCd <= 0) {
      if (ctrl.juke) {
        const sp2 = Math.hypot(a.v.x, a.v.z) || 1;
        const lx = -a.v.z / sp2, lz = a.v.x / sp2;
        const side = (m.x * lx + m.z * lz) >= 0 ? 1 : -1;
        a.v.x += lx * side * 4.2; a.v.z += lz * side * 4.2;
        a.juke = 0.38; a.moveCd = 0.9;
        this.emit('move', { type: 'juke' });
      } else if (ctrl.stiff) {
        a.stiff = 0.6; a.moveCd = 1.0;
        this.emit('move', { type: 'stiff' });
      } else if (ctrl.dive && !(a === this.qb && !this.crossedLos)) {
        this.carrierDive(a);
      }
    } else if (a !== this.carrier && ctrl.dive && a.tackleCd <= 0 && this.carrier && this.carrier.teamKey !== a.teamKey) {
      this.diveTackle(a);
    }
    if (a === this.qb && this.carrier === a && !this.crossedLos && a.job) a.job.phase = 'scramble';
    return true;
  }

  // ------------------------------------------------------------ AI
  think(a, dt) {
    const j = a.job;
    if (!j) { this.steer(a, 0, 0, dt); return; }
    if (a === this.carrier) { this.cpuCarrier(a, dt); return; }
    // Once the ball is past the line (or handed off), everyone on defense pursues.
    const carrierLive = this.carrier && (this.carrier !== this.qb || this.crossedLos || this.qbScrambling());
    if (a.teamKey !== this.carrier?.teamKey && carrierLive && this.ballState !== 'air') {
      if (a.side === 'def' || this.turnover) { this.pursue(a, dt); return; }
    }
    if (this.turnover && a.teamKey === this.carrier?.teamKey) { this.escort(a, dt); return; }
    switch (j.type) {
      case 'qb': return this.qbMove(a, dt);
      case 'rbRun': return this.rbMove(a, dt);
      case 'route': return this.routeMove(a, dt);
      case 'ol': return this.olMove(a, dt);
      case 'protect': return this.protectMove(a, dt);
      case 'lead': return this.leadMove(a, dt);
      case 'stalk': return this.stalkMove(a, dt);
      case 'rush': return this.rushMove(a, dt);
      case 'man': return this.manMove(a, dt);
      case 'zone': return this.zoneMove(a, dt);
      default: this.steer(a, 0, 0, dt);
    }
  }

  qbScrambling() {
    const l = this.L(this.qb.p);
    return this.qb.job?.phase === 'scramble' && l.u > -2.5;
  }

  qbMove(a, dt) {
    const j = a.job;
    if (j.phase === 'mesh') {
      const m = this.W(j.mesh.u, j.mesh.v);
      this.seek(a, m.x, m.z, dt, 0.55, 0.8);
      a.facingLock = Math.atan2(m.z - a.p.z, m.x - a.p.x);
      return;
    }
    if (j.phase === 'drop') {
      const tgt = this.W(j.dropU, this.L(a.p).v * 0.6);
      const d = this.seek(a, tgt.x, tgt.z, dt, 0.62, 1.0);
      a.facingLock = this.dir > 0 ? 0 : Math.PI;
      if (d < 0.3) j.phase = 'set';
      return;
    }
    if (j.phase === 'set' || j.phase === 'thrown') {
      // Climb the pocket if a rusher is close behind.
      const r = this.nearestThreat(a);
      if (r && dist(r.p, a.p) < 2.6 && this.carrier === a && this.userKey !== this.offKey) {
        const away = { x: a.p.x - r.p.x, z: a.p.z - r.p.z };
        const l = Math.hypot(away.x, away.z) || 1;
        this.steer(a, away.x / l * 4, away.z / l * 4, dt);
      } else this.steer(a, 0, 0, dt);
      a.facingLock = this.dir > 0 ? 0 : Math.PI;
      return;
    }
    if (j.phase === 'boot') {
      const tgt = this.W(-6, j.bootV);
      this.seek(a, tgt.x, tgt.z, dt, 0.6);
      return;
    }
    this.steer(a, 0, 0, dt);
  }

  nearestThreat(a) {
    let best = null, bd = 1e9;
    for (const d of this.def) {
      if (d.down || d.engaged) continue;
      const dd = dist(d.p, a.p);
      if (dd < bd) { bd = dd; best = d; }
    }
    return best;
  }

  rbMove(a, dt) {
    const j = a.job;
    if (!j.got) {
      const m = this.W(j.mesh.u, j.mesh.v - Math.sign(j.hole.v || 1) * 0.4);
      const d = this.seek(a, m.x, m.z, dt, 0.75, 0.3);
      const qb = this.qb;
      if (this.carrier === qb && dist(a.p, qb.p) < 1.1 && this.t > 0.45 && this.qb.job?.phase === 'mesh') {
        if (j.fake) {
          j.got = true; j.faked = true;
          qb.job.phase = 'drop';
          qb.job.dropU = -8;
          this.runRead = true;
          this.fakeT = this.t;
          this.emit('fake');
        } else {
          j.got = true;
          qb.job.phase = 'boot';
          qb.job.bootV = -Math.sign(j.hole.v || 1) * 5;
          this.handoff(a);
        }
      } else if (d < 0.4 && this.t > 1.4) {
        j.got = true;
        if (!j.fake) this.handoff(a);
      }
      return;
    }
    if (j.faked) {
      // Play-action back: carry out the fake through the line, then sit as a blocker.
      const h = this.W(1.5, j.hole.v);
      if (this.t - this.fakeT < 0.9) this.seek(a, h.x, h.z, dt, 0.6);
      else this.protectMove(a, dt);
      return;
    }
    this.steer(a, 0, 0, dt);
  }

  handoff(rb) {
    this.handedOff = true;
    this.giveBall(rb, true);
    this.ballState = 'run';
    this.runRead = true;
    this.emit('handoff', { to: rb });
  }

  routeMove(a, dt) {
    const j = a.job;
    if (this.ballState === 'air' && this.passTarget === a) {
      const tgt = this.pass.target;
      const tl = Math.max(0.05, this.pass.T - this.passT);
      const d = Math.hypot(tgt.x - a.p.x, tgt.z - a.p.z);
      const need = d / tl;
      const sp = Math.min(a.maxSpeed, Math.max(need, d > 0.4 ? 3 : 0));
      if (d > 0.05) this.steer(a, (tgt.x - a.p.x) / d * sp, (tgt.z - a.p.z) / d * sp, dt, a.accel * 1.2);
      return;
    }
    if (this.carrier && this.carrier !== this.qb && this.carrier.teamKey === a.teamKey) {
      // Turn into a blocker for the ball carrier.
      return this.stalkMove(a, dt);
    }
    if (j.i >= j.pts.length) {
      if (j.settle) {
        this.steer(a, 0, 0, dt, a.accel * 1.4);
        a.facingLock = Math.atan2(this.qb.p.z - a.p.z, this.qb.p.x - a.p.x);
      } else {
        // Keep running the last leg, bending away from the sideline.
        const p0 = j.pts[j.pts.length - 2] || this.W(0, a.align.v);
        const p1 = j.pts[j.pts.length - 1];
        let dx = p1.x - p0.x, dz = p1.z - p0.z;
        const l = Math.hypot(dx, dz) || 1;
        dx /= l; dz /= l;
        if (Math.abs(a.p.z) > HW - 2) dz = -Math.sign(a.p.z) * 0.2;
        if ((a.p.x * this.dir) > FIELD.goal + 7) { dx = 0; dz = Math.sign(this.ballZ - a.p.z) * 0.5; }
        this.steer(a, dx * a.maxSpeed * 0.95, dz * a.maxSpeed * 0.95, dt);
      }
      return;
    }
    const p = j.pts[j.i];
    const d = dist(a.p, p);
    // Cut sharpness slows the receiver at the break.
    let frac = 1;
    if (j.i < j.pts.length - 1 && d < 2.5) {
      const n = j.pts[j.i + 1];
      const a1 = Math.atan2(p.z - a.p.z, p.x - a.p.x), a2 = Math.atan2(n.z - p.z, n.x - p.x);
      const turn = Math.abs(angleDiff(a1, a2));
      frac = 1 - Math.min(0.5, turn / Math.PI * 0.65) * (1 - d / 2.5);
    }
    this.seek(a, p.x, p.z, dt, frac * (this.t < 0.25 ? 0.8 : 1), j.settle && j.i === j.pts.length - 1 ? 1.5 : 0.01);
    if (d < 0.9) j.i++;
  }

  olMove(a, dt) {
    const j = a.job;
    let t = j.target;
    if (!t || t.down || (t.engaged && t.engaged !== a) || t.immune === a) {
      // Find someone to block near me.
      t = this.findBlockTarget(a, j.run ? 6 : 7);
      j.target = t;
    }
    if (!t) {
      // Hold the pocket.
      const anchor = this.W(j.run ? 1.5 : -1.6, this.L(a.p).v);
      this.seek(a, anchor.x, anchor.z, dt, 0.5);
      return;
    }
    if (j.run) {
      this.seek(a, t.p.x, t.p.z, dt, 0.95, 0.01);
    } else {
      // Stay between the rusher and the quarterback.
      const q = this.qb.p;
      const dx = t.p.x - q.x, dz = t.p.z - q.z;
      const l = Math.hypot(dx, dz) || 1;
      const k = Math.max(1.2, l - 1.0);
      this.seek(a, q.x + dx / l * k, q.z + dz / l * k, dt, 0.9, 0.5);
      a.facingLock = Math.atan2(t.p.z - a.p.z, t.p.x - a.p.x);
    }
    if (dist(a.p, t.p) < 1.15 && !t.engaged && t.immune !== a && !t.down) this.engage(a, t);
  }

  findBlockTarget(a, range) {
    let best = null, bd = range;
    const ref = this.carrier && this.carrier !== this.qb ? this.carrier : this.qb;
    for (const d of this.def) {
      if (d.down || d.engaged || d.immune === a) continue;
      const da = dist(d.p, a.p);
      const threat = dist(d.p, ref.p);
      const score = da + threat * 0.25;
      if (da < range && score < bd + range * 0.25) { bd = score; best = d; }
    }
    return best;
  }

  protectMove(a, dt) {
    const j = a.job || {};
    let t = j.target;
    if (!t || t.down || (t.engaged && t.engaged !== a)) {
      t = null;
      let bd = 7;
      for (const d of this.def) {
        if (d.down || d.engaged || d.job?.type !== 'rush') continue;
        const dd = dist(d.p, this.qb.p);
        if (dd < bd) { bd = dd; t = d; }
      }
      if (a.job) a.job.target = t;
    }
    if (t) {
      const q = this.qb.p;
      const dx = t.p.x - q.x, dz = t.p.z - q.z;
      const l = Math.hypot(dx, dz) || 1;
      this.seek(a, q.x + dx / l * Math.max(1.0, l - 0.9), q.z + dz / l * Math.max(1.0, l - 0.9), dt, 0.95, 0.4);
      if (dist(a.p, t.p) < 1.15 && !t.engaged && t.immune !== a) this.engage(a, t);
    } else {
      // Release into the flat as a check-down.
      const spot = this.W(2.5, this.L(a.p).v > 0 ? 6 : -6);
      this.seek(a, spot.x, spot.z, dt, 0.6);
    }
  }

  leadMove(a, dt) {
    const j = a.job;
    const hole = this.W(1.2, j.hole);
    if (!j.target) {
      if (this.L(a.p).u > -0.5) j.target = this.findBlockTarget(a, 9);
      this.seek(a, hole.x, hole.z, dt, 0.95, 0.01);
      return;
    }
    const t = j.target;
    if (t.down || (t.engaged && t.engaged !== a)) { j.target = null; return; }
    this.seek(a, t.p.x, t.p.z, dt, 1, 0.01);
    if (dist(a.p, t.p) < 1.15 && !t.engaged && t.immune !== a) this.engage(a, t);
  }

  stalkMove(a, dt) {
    const j = a.job || (a.job = { type: 'stalk' });
    let t = j.target;
    if (!t || t.down || (t.engaged && t.engaged !== a)) {
      t = null;
      let bd = 9;
      const ref = this.carrier || a;
      for (const d of this.def) {
        if (d.down || d.engaged) continue;
        const dd = dist(d.p, a.p) + dist(d.p, ref.p) * 0.3;
        if (dd < bd) { bd = dd; t = d; }
      }
      j.target = t;
    }
    if (!t) { this.steer(a, 0, 0, dt); return; }
    // Square up between the defender and the ball.
    const ref = this.carrier || this.qb;
    if (this.carrier && dist(t.p, this.carrier.p) < 2.5) { j.target = null; this.steer(a, a.v.x * 0.95, a.v.z * 0.95, dt); return; }
    const dx = ref.p.x - t.p.x, dz = ref.p.z - t.p.z;
    const l = Math.hypot(dx, dz) || 1;
    this.seek(a, t.p.x + dx / l * 0.9, t.p.z + dz / l * 0.9, dt, 0.9, 0.5);
    if (dist(a.p, t.p) < 1.1 && !t.engaged && t.immune !== a) this.engage(a, t);
  }

  rushMove(a, dt) {
    const target = this.carrier || this.qb;
    if (this.runRead && this.carrier && this.carrier !== this.qb) { this.pursue(a, dt); return; }
    // Rush lane: aim a bit outside the QB for edge rushers.
    const l = this.L(target.p);
    const lane = this.W(l.u, l.v + (a.job.lane || 0) * 0.35);
    const late = this.thrown;
    if (late) { this.steer(a, a.v.x * 0.9, a.v.z * 0.9, dt); return; }
    this.seek(a, lane.x, lane.z, dt, 1, 0.01);
  }

  manMove(a, dt) {
    const r = a.job.target;
    if (this.ballState === 'air') return this.breakOnBall(a, dt);
    if (this.t < a.react) { this.steer(a, 0, 0, dt); a.facingLock = this.dir > 0 ? Math.PI : 0; return; }
    if (this.runRead && this.t - (this.fakeT || 0) < 0.6 && this.play.type === 'pa' && ['MIKE', 'WILL', 'SS'].includes(a.slot)) {
      // Bite on play action.
      const fwd = this.W(this.L(a.p).u - 2, this.L(a.p).v);
      this.seek(a, fwd.x, fwd.z, dt, 0.5);
      return;
    }
    // Delayed read of the receiver's velocity gives the offense separation at the break.
    const rate = 2.5 + a.r.awr * 5;
    a.estV.x = lerp(a.estV.x, r.v.x, 1 - Math.exp(-rate * dt));
    a.estV.z = lerp(a.estV.z, r.v.z, 1 - Math.exp(-rate * dt));
    const ru = this.L(r.p).u;
    const cushion = clamp(4.5 - ru * 0.35, 0.8, 4.5);
    const tx = r.p.x + a.estV.x * 0.35 + this.dir * cushion * 0.6;
    const tz = r.p.z + a.estV.z * 0.35 + (this.ballZ - r.p.z) * 0.04;
    this.seek(a, tx, tz, dt, 1, 0.6);
    const myU = this.L(a.p).u;
    if (myU > ru + 0.5 && this.t < 2.2) a.facingLock = this.dir > 0 ? Math.PI : 0; // backpedal facing the QB
  }

  zoneMove(a, dt) {
    if (this.ballState === 'air') return this.breakOnBall(a, dt);
    if (this.t < a.react * 0.6) { this.steer(a, 0, 0, dt); return; }
    if (this.runRead && this.play.type === 'pa' && this.t - (this.fakeT || 0) < 0.5 && ['MIKE', 'WILL'].includes(a.slot)) {
      const fwd = this.W(this.L(a.p).u - 2, this.L(a.p).v);
      this.seek(a, fwd.x, fwd.z, dt, 0.5);
      return;
    }
    const z = a.job.zone;
    // Find the most dangerous receiver in my area (zones stretch toward the nearest sideline).
    let threat = null, best = 1e9;
    const reach = a.job.r * 1.7;
    for (const r of this.receivers) {
      if (this.L(r.p).u < -1) continue;
      const d = dist(r.p, z);
      const sidelineBias = Math.abs(r.p.z) > Math.abs(z.z) && Math.sign(r.p.z) === Math.sign(z.z) ? 0.65 : 1;
      const score = d * sidelineBias;
      if (score < reach && score < best) { best = score; threat = r; }
    }
    let tx = z.x, tz = z.z;
    if (threat) {
      const ru = this.L(threat.p).u;
      const deep = a.job.zu > 12;
      const k = deep ? (ru > 7 ? 0.85 : 0.6) : 0.85;
      tx = lerp(z.x, threat.p.x + this.dir * (deep ? 3 : 1.0), k) + (deep && ru > a.job.zu - 4 ? this.dir * 2 : 0);
      tz = lerp(z.z, threat.p.z + threat.v.z * 0.25, k);
    }
    this.seek(a, tx, tz, dt, threat ? 1 : 0.92, 0.8);
    if (this.t < 2.0 && this.L(a.p).u < a.job.zu) a.facingLock = this.dir > 0 ? Math.PI : 0;
  }

  breakOnBall(a, dt) {
    const reactT = 0.15 + (1 - a.r.awr) * 0.5;
    if (this.passT < reactT) { this.steer(a, a.v.x, a.v.z, dt); return; }
    const tgt = this.pass.target;
    const d = dist(a.p, tgt);
    const tl = Math.max(0.05, this.pass.T - this.passT);
    if (d / a.maxSpeed < tl + 0.8) this.seek(a, tgt.x, tgt.z, dt, 1, 0.01);
    else {
      // Can't get there: rally to where the receiver will be after the catch.
      this.seek(a, tgt.x + this.dir * 2, tgt.z, dt, 1, 0.01);
    }
  }

  pursue(a, dt) {
    const c = this.carrier;
    if (!c) { this.steer(a, 0, 0, dt); return; }
    const d = dist(a.p, c.p);
    let tx, tz;
    if (d < 4) {
      // Close: attack the ball carrier's near hip.
      tx = c.p.x + c.v.x * 0.18; tz = c.p.z + c.v.z * 0.18;
    } else {
      const tLead = Math.min(1.4, d / a.maxSpeed) * (0.6 + a.r.awr * 0.35);
      tx = c.p.x + c.v.x * tLead; tz = c.p.z + c.v.z * tLead;
    }
    this.seek(a, tx, tz, dt, a.stun > 0 ? 0.4 : 1, 0.01);
    // AI defenders lay out when they are a step away.
    if (!a.user && d > 1.1 && d < 2.8 && a.tackleCd <= 0 && a.stun <= 0 && !this.result && Math.random() < dt * (1.2 + a.r.tak * 2)) {
      this.diveTackle(a);
    }
  }

  escort(a, dt) {
    const c = this.carrier;
    let t = null, bd = 8;
    for (const d of this.athletes) {
      if (!d.active || d.down || d.teamKey === a.teamKey || d.engaged) continue;
      const dd = dist(d.p, c.p);
      if (dd < bd) { bd = dd; t = d; }
    }
    if (!t) { this.seek(a, c.p.x + c.v.x, c.p.z + c.v.z + (a.p.z > c.p.z ? 3 : -3), dt, 0.9); return; }
    this.seek(a, (t.p.x + c.p.x) / 2, (t.p.z + c.p.z) / 2, dt, 1, 0.01);
    if (dist(a.p, t.p) < 1.1 && !t.engaged) this.engage(a, t);
  }

  cpuCarrier(a, dt) {
    if (a.job?.type === 'qb' && !this.crossedLos && a === this.qb && this.ballState === 'qb' && a.job.phase !== 'scramble') {
      return this.qbMove(a, dt);
    }
    const j = a.job;
    // Hit the designed hole first.
    let gx = this.dir, gz = 0;
    if (j?.type === 'rbRun' && j.got && !j.faked && this.L(a.p).u < 0.8 && !this.turnover) {
      const h = this.W(j.hole.u, j.hole.v);
      const dx = h.x - a.p.x, dz = h.z - a.p.z;
      const l = Math.hypot(dx, dz) || 1;
      gx = dx / l; gz = dz / l;
    }
    const goalDir = this.carrierDir();
    if (!(j?.type === 'rbRun' && this.L(a.p).u < 0.8)) { gx = goalDir; gz = 0; }
    let rx = 0, rz = 0;
    for (const d of this.athletes) {
      if (!d.active || d.down || d.teamKey === a.teamKey) continue;
      const dx = a.p.x - d.p.x, dz = a.p.z - d.p.z;
      const dd = Math.hypot(dx, dz);
      if (dd > 7) continue;
      const ahead = (d.p.x - a.p.x) * goalDir > -1.0;
      if (!ahead) continue;
      const w = (d.engaged ? 0.2 : 0.85) / Math.max(0.8, dd * dd);
      rx += (dx / dd) * w * 0.3;
      rz += (dz / dd) * w * 0.9;
    }
    if (Math.abs(a.p.z) > HW - 4) rz -= Math.sign(a.p.z) * (Math.abs(a.p.z) - (HW - 4)) * 0.5;
    let dx = gx + rx, dz = gz + rz;
    if (dx * goalDir < 0.25) dx = goalDir * 0.25;
    const l = Math.hypot(dx, dz) || 1;
    this.steer(a, dx / l * a.maxSpeed, dz / l * a.maxSpeed, dt);
    // CPU jukes when a tackler is close in front.
    const threat = this.athletes.find((d) => d.active && !d.down && !d.engaged && d.teamKey !== a.teamKey && dist(d.p, a.p) < 2.2 && (d.p.x - a.p.x) * goalDir > 0);
    if (threat && a.moveCd <= 0 && Math.random() < dt * 1.1) {
      if (chance(0.5) && a.r.str > 0.65) a.stiff = 0.6;
      else { a.juke = 0.38; const sgn = chance(0.5) ? 1 : -1; a.v.z += sgn * 4; }
      a.moveCd = 1.2;
    }
  }

  carrierDir() {
    // The team with the ball heads toward the far goal for its side.
    if (!this.carrier) return this.dir;
    return this.carrier.side === 'off' ? this.dir : -this.dir;
  }

  // ------------------------------------------------------------ blocking
  engage(b, d) {
    b.engaged = d; d.engaged = b;
    d.shed = 0;
    b.engageT = 0;
    this.emit('engage', { a: b, b: d });
  }

  updateBlocks(dt) {
    for (const b of this.off.concat(this.def)) {
      const d = b.engaged;
      if (!d || d.engaged !== b) continue;
      if (b.side === d.side) continue;
      // Process each pair once, from the blocker's side.
      const blockingTeam = this.carrier ? this.carrier.teamKey : this.offKey;
      const blocker = b.teamKey === blockingTeam ? b : d;
      const def = blocker === b ? d : b;
      if (blocker !== b) continue;
      blocker.engageT = (blocker.engageT || 0) + dt;
      const goal = this.carrier && (this.carrier !== this.qb || this.runRead) ? this.carrier.p : this.qb.p;
      const gx = goal.x - def.p.x, gz = goal.z - def.p.z;
      const gl = Math.hypot(gx, gz) || 1;
      const power = def.r.str * rand(0.85, 1.15) - blocker.r.blk * rand(0.85, 1.15);
      const push = clamp(power * 2.4 + 0.45, -1.1, 1.8);
      const cx = (blocker.p.x + def.p.x) / 2 + (gx / gl) * push * dt;
      const cz = (blocker.p.z + def.p.z) / 2 + (gz / gl) * push * dt * 0.8;
      let nx = def.p.x - blocker.p.x, nz = def.p.z - blocker.p.z;
      const nl = Math.hypot(nx, nz) || 1;
      nx /= nl; nz /= nl;
      blocker.p.x = cx - nx * 0.5; blocker.p.z = cz - nz * 0.5;
      def.p.x = cx + nx * 0.5; def.p.z = cz + nz * 0.5;
      blocker.v.x = def.v.x = (gx / gl) * push;
      blocker.v.z = def.v.z = (gz / gl) * push * 0.8;
      blocker.h = Math.atan2(nz, nx);
      def.h = Math.atan2(-nz, -nx);
      // Shedding.
      const nearBall = this.carrier && this.carrier !== this.qb && dist(def.p, this.carrier.p) < 2.6;
      let rate = 0.16 + Math.max(0, def.r.str - blocker.r.blk + 0.12) * 0.9 + rand(0, 0.12);
      if (nearBall) rate *= 3.2;
      if (def.job?.type !== 'rush' && !nearBall) rate *= 1.6;
      if (this.thrown && ['X', 'Z', 'SL', 'SL2', 'RB', 'TE', 'FB'].includes(blocker.slot) && blocker.side === 'off') rate *= 2.2;
      def.shed += rate * dt;
      if (def.shed >= 1) {
        def.engaged = null; blocker.engaged = null;
        def.immune = blocker; def.immuneT = 1.6;
        blocker.stun = 0.35;
        if (blocker.job) blocker.job.target = null;
        // Burst off the block.
        def.v.x = gx / gl * 3; def.v.z = gz / gl * 3;
      }
    }
  }

  separate() {
    const list = this.athletes.filter((a) => a.active && !a.down);
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      for (let k = i + 1; k < list.length; k++) {
        const b = list[k];
        if (a.engaged === b) continue;
        const dx = b.p.x - a.p.x, dz = b.p.z - a.p.z;
        const d = Math.hypot(dx, dz);
        const minD = 0.72;
        if (d < minD && d > 1e-4) {
          const push = (minD - d) * 0.5;
          const wa = a === this.carrier ? 0.3 : 1, wb = b === this.carrier ? 0.3 : 1;
          a.p.x -= dx / d * push * wa; a.p.z -= dz / d * push * wa;
          b.p.x += dx / d * push * wb; b.p.z += dz / d * push * wb;
        }
      }
    }
  }

  // ------------------------------------------------------------ ball
  giveBall(a, tuck) {
    if (this.carrier && this.carrier !== a) this.carrier.speedCap = 1;
    this.carrier = a;
    a.speedCap = a === this.qb ? 0.97 : 0.94; // nobody runs quite as fast with the ball
    const ball = this.world.ball;
    if (a === this.qb && !tuck && !this.handedOff) ball.attach(a.model.handAnchor, false);
    else ball.attach(a.model.carryAnchor, true);
  }

  // Ball carrier bookkeeping: line crossing, sidelines, goal line, tackles.
  checkCarrier(dt) {
    const c = this.carrier;
    if (!c || this.result || this.ballState === 'air' || this.ballState === 'snap') return;
    const goalDir = this.carrierDir();
    if (c.side === 'off' && !this.crossedLos && this.L(c.p).u > 0.2) {
      this.crossedLos = true;
      if (c === this.qb) this.ballState = 'run';
    }
    if (c === this.qb && !this.thrown && !this.handedOff) {
      this.ballState = this.crossedLos ? 'run' : 'qb';
    }
    // Sideline.
    if (Math.abs(c.p.z) > HW) {
      return this.endPlay({ kind: 'oob', x: c.p.x, z: Math.sign(c.p.z) * HW });
    }
    // Goal line.
    if (c.p.x * goalDir >= FIELD.goal) {
      return this.endPlay({ kind: 'td', x: c.p.x, z: c.p.z });
    }
    if (c.p.x * goalDir > FIELD.goal + 10) return;
    // Tackles.
    const tacklers = [];
    for (const d of this.athletes) {
      if (!d.active || d.down || d.engaged || d.teamKey === c.teamKey || d.tackleCd > 0) continue;
      const dd = dist(d.p, c.p);
      if (dd < 1.25) tacklers.push(d);
    }
    if (!tacklers.length) return;
    let pFail = 1;
    for (const d of tacklers) {
      d.tackleCd = 0.5;
      const sack = c === this.qb && !this.crossedLos && !this.thrown;
      let p = sack ? 0.84 : 0.56 + 0.42 * d.r.tak - 0.2 * c.r.str;
      // Hit from behind is easier to break with speed, from the front harder to juke.
      const rel = Math.atan2(d.p.z - c.p.z, d.p.x - c.p.x);
      const front = Math.abs(angleDiff(Math.atan2(c.v.z, c.v.x), rel)) < Math.PI / 2;
      if (c.juke > 0 && front) p *= 0.42;
      if (c.stiff > 0 && c.r.str + 0.1 > d.r.str * 0.9) p *= 0.6;
      if (!front && Math.hypot(c.v.x, c.v.z) > 7) p *= 0.85;
      if (c.user) p *= this.diffMul?.userCarrier ?? 1;
      if (d.user) p *= this.diffMul?.userTackle ?? 1;
      p = clamp(p, 0.12, 0.97);
      pFail *= 1 - p;
    }
    if (Math.random() > pFail) {
      const d = tacklers[0];
      const rel = Math.atan2(d.p.z - c.p.z, d.p.x - c.p.x);
      const front = Math.abs(angleDiff(Math.atan2(c.v.z, c.v.x), rel)) < Math.PI / 2;
      const fwd = Math.hypot(c.v.x, c.v.z) > 3 ? 0.6 : 0.2;
      const spotX = c.p.x + goalDir * (front ? Math.min(0.4, fwd * 0.5) : fwd);
      this.knockDown(c, !front, 0);
      for (const t of tacklers) this.knockDown(t, false, 0, rand(-0.3, 0.3));
      const sack = c === this.qb && !this.crossedLos && !this.thrown;
      this.emit('hit', { power: Math.hypot(c.v.x, c.v.z) + Math.hypot(d.v.x, d.v.z) });
      if (spotX * goalDir >= FIELD.goal) return this.endPlay({ kind: 'td', x: spotX, z: c.p.z });
      this.endPlay({ kind: sack ? 'sack' : 'tackle', x: spotX, z: c.p.z, tackler: d });
    } else {
      for (const d of tacklers) {
        d.stun = 0.9;
        if (chance(0.55)) this.knockDown(d, false, 1.1, rand(-0.5, 0.5));
      }
      this.emit('broken', { by: c });
    }
  }

  knockDown(a, backward, dur, roll = 0) {
    a.down = true;
    a.downT = 0;
    a.downDur = dur;
    a.downBack = backward;
    a.downRoll = roll;
    if (a.engaged) { a.engaged.engaged = null; a.engaged = null; }
  }

  carrierDive(a) {
    const g = this.carrierDir();
    a.v.x = g * 5; a.v.z *= 0.5;
    a.p.x += g * 0.8;
    this.knockDown(a, false, 0);
    const spot = a.p.x + g * 1.2;
    if (spot * g >= FIELD.goal) return this.endPlay({ kind: 'td', x: spot, z: a.p.z });
    if (Math.abs(a.p.z) > HW) return this.endPlay({ kind: 'oob', x: spot, z: Math.sign(a.p.z) * HW });
    this.endPlay({ kind: 'tackle', x: spot, z: a.p.z, dive: true });
  }

  diveTackle(a) {
    const c = this.carrier;
    const d = dist(a.p, c.p);
    a.tackleCd = 1.5;
    const toC = { x: (c.p.x + c.v.x * 0.25) - a.p.x, z: (c.p.z + c.v.z * 0.25) - a.p.z };
    const l = Math.hypot(toC.x, toC.z) || 1;
    a.v.x = toC.x / l * 8; a.v.z = toC.z / l * 8;
    a.h = Math.atan2(toC.z, toC.x);
    if (d < 2.9) {
      const p = clamp(0.92 - (d - 1) * 0.22 - (c.juke > 0 ? 0.35 : 0), 0.25, 0.95);
      if (Math.random() < p) {
        a.p.x += toC.x / l * Math.max(0, d - 0.8); a.p.z += toC.z / l * Math.max(0, d - 0.8);
        this.knockDown(a, false, 0);
        this.knockDown(c, Math.abs(angleDiff(Math.atan2(c.v.z, c.v.x), a.h)) > Math.PI / 2, 0);
        this.emit('hit', { power: 14 });
        const g = this.carrierDir();
        const spotX = c.p.x + g * 0.3;
        if (spotX * g >= FIELD.goal) return this.endPlay({ kind: 'td', x: spotX, z: c.p.z });
        const sack = c === this.qb && !this.crossedLos && !this.thrown;
        return this.endPlay({ kind: sack ? 'sack' : 'tackle', x: spotX, z: c.p.z, tackler: a });
      }
    }
    a.p.x += toC.x / l * 1.2; a.p.z += toC.z / l * 1.2;
    this.knockDown(a, false, 1.2);
    this.emit('whiff');
  }

  // ------------------------------------------------------------ passing
  userQb(ctrl) {
    if (!ctrl || this.thrown || this.crossedLos) return;
    if (this.play.type === 'run' || this.qb.job?.phase === 'mesh') { ctrl.throwKey = 0; return; }
    if (ctrl.throwKey) {
      const r = this.icons.find((a) => a.key === ctrl.throwKey);
      if (r) this.throwTo(r, ctrl.throwLob ? 'lob' : 'bullet');
      ctrl.throwKey = 0;
    }
  }

  cpuQb() {
    if (this.thrown) return;
    const qb = this.qb;
    const j = qb.job;
    if (j.phase === 'mesh') return;
    const tDrop = this.shotgun ? 1.2 : 1.6;
    if (this.t < tDrop + (this.play.type === 'pa' ? 0.8 : 0)) return;
    if (this.cpuNextLook && this.t < this.cpuNextLook) return;
    this.cpuNextLook = this.t + 0.12;
    const threat = this.nearestThreat(qb);
    const pressure = threat ? dist(threat.p, qb.p) : 99;
    let best = null, bestScore = -1;
    for (const r of this.receivers) {
      if (r.job?.type !== 'route' || r.down) continue;
      let open = this.openness(r);
      const l = this.L(r.p);
      // Only trust a route once it has made its break.
      if (r.job.i < 1 && !r.job.settle && r.job.pts.length > 1) open *= 0.55;
      if (r.job.depth > 15 && l.u < 10) open *= 0.7;
      const depthBonus = clamp(l.u, -2, 25) * 0.06;
      const needFirst = (this.firstDownX - this.los) * this.dir;
      const sticks = l.u >= needFirst ? 0.6 : 0;
      const score = open + depthBonus + sticks;
      if (score > bestScore) { bestScore = score; best = r; }
    }
    const late = this.t > 3.6;
    const pressured = pressure < 2.0;
    if (best && (bestScore > 3.3 || (pressured && bestScore > 1.8) || (late && bestScore > 1.2))) {
      const deep = this.L(best.p).u > 14;
      this.throwTo(best, deep && chance(0.6) ? 'lob' : 'bullet');
    } else if (pressured && this.t > 2.6 && chance(0.35)) {
      // Throw it away.
      const away = this.W(8, (this.L(qb.p).v >= 0 ? 1 : -1) * (HW + 6));
      this.throwAway(away);
    } else if (this.t > 5.2) {
      if (best) this.throwTo(best, 'bullet');
    }
  }

  openness(r) {
    let m = 99;
    const fx = r.p.x + r.v.x * 0.6, fz = r.p.z + r.v.z * 0.6;
    for (const d of this.def) {
      if (d.down) continue;
      const dd = Math.hypot(d.p.x + d.v.x * 0.6 - fx, d.p.z + d.v.z * 0.6 - fz);
      m = Math.min(m, dd);
    }
    return m;
  }

  // Flight time for a pass of length d, chosen from the arc's peak height so a
  // touch pass floats (about 8 yards up on a deep ball) and a bullet stays flat.
  flightTime(d, type) {
    const y0 = 2.0, y1 = 1.35;
    const apex = type === 'lob' ? clamp(3.2 + d * 0.13, 4, 8.5) : clamp(2.5 + d * 0.05, 2.6, 4.2);
    const vy = Math.sqrt(2 * GRAVITY * (apex - y0));
    const tApex = (vy + Math.sqrt(vy * vy + 2 * GRAVITY * (y0 - y1))) / GRAVITY;
    const tMax = type === 'lob' ? d / 12 + 0.35 : d / 17 + 0.15;
    return Math.max(0.35, Math.min(tApex, tMax));
  }

  throwTo(r, type) {
    const qb = this.qb;
    // Lead the receiver along his current path.
    let T = 0.6, tx = r.p.x, tz = r.p.z;
    for (let i = 0; i < 4; i++) {
      tx = r.p.x + r.v.x * T;
      tz = r.p.z + r.v.z * T;
      const d = Math.hypot(tx - qb.p.x, tz - qb.p.z);
      T = this.flightTime(d, type);
    }
    if (r.job?.type === 'route' && r.job.settle && r.job.i >= r.job.pts.length - 1) {
      const last = r.job.pts[r.job.pts.length - 1];
      tx = lerp(tx, last.x, 0.6); tz = lerp(tz, last.z, 0.6);
    }
    // Accuracy.
    const threat = this.nearestThreat(qb);
    const pressure = threat ? clamp(1 - (dist(threat.p, qb.p) - 1) / 3, 0, 1) : 0;
    const moving = Math.hypot(qb.v.x, qb.v.z) > 2.5 ? 0.5 : 0;
    const d = Math.hypot(tx - qb.p.x, tz - qb.p.z);
    const userMul = this.offKey === this.userKey ? (this.diffMul?.userAcc ?? 1) : (this.diffMul?.cpuAcc ?? 1);
    const sigma = ((1 - qb.r.tha) * 1.6 + pressure * 1.3 + moving + d * 0.03) * userMul;
    tx += gaussian() * sigma * 0.7;
    tz += gaussian() * sigma * 0.7;
    tz = clamp(tz, -HW - 2, HW + 2);
    this.launchPass({ x: tx, z: tz }, T, r, type);
    this.emit('throw', { to: r, type });
  }

  throwAway(spot) {
    const qb = this.qb;
    const T = this.flightTime(Math.hypot(spot.x - qb.p.x, spot.z - qb.p.z), 'bullet');
    this.launchPass(spot, T, null, 'away');
    this.emit('throw', { to: null, type: 'away' });
  }

  launchPass(target, T, rec, type) {
    const qb = this.qb;
    const ball = this.world.ball;
    qb.model.root.updateMatrixWorld(true);
    const p0 = ball.mesh.getWorldPosition(new THREE.Vector3());
    p0.y = Math.max(p0.y, 2.0);
    const p1 = new THREE.Vector3(target.x, rec ? 1.35 : 0.3, target.z);
    ball.launch(p0, p1, T, 'spiral');
    this.pass = { target, T, type, from: { x: qb.p.x, z: qb.p.z } };
    this.passT = 0;
    this.passTarget = rec;
    this.thrown = true;
    this.ballState = 'air';
    this.carrier = null;
    qb.throwT = 0.5;
    if (qb.job) qb.job.phase = 'thrown';
  }

  preCatchAnims() {
    for (const a of this.athletes) {
      if (!a.active || a.down) continue;
      if (dist(a.p, this.pass.target) < 1.8) a.catching = 0.4;
    }
  }

  resolveCatch() {
    const tgt = this.pass.target;
    const ball = this.world.ball;
    let rec = null, rd = 1e9, def = null, dd = 1e9;
    for (const a of this.athletes) {
      if (!a.active || a.down) continue;
      const d = dist(a.p, tgt);
      if (a.side === 'off' && ELIGIBLE.includes(a.slot) && d < rd) { rd = d; rec = a; }
      if (a.side === 'def' && d < dd) { dd = d; def = a; }
    }
    const reach = 1.5;
    // Touch passes hang long enough for defenders to close and get a hand in.
    const defReach = reach * (this.pass.type === 'lob' ? 1.1 : 0.9);
    const recIn = rec && rd < reach;
    const defIn = def && dd < defReach;
    const contest = defIn ? clamp(1 - dd / defReach, 0, 1) : 0;
    const outOfBounds = Math.abs(tgt.z) > HW - 0.1 || tgt.x * this.dir > FIELD.goal + 10;
    if (defIn && (!recIn || dd < rd - 0.2) && !outOfBounds) {
      const intP = (0.18 + def.r.cat * 0.32) * contest * (recIn ? 0.75 : 1.25);
      if (Math.random() < intP) return this.interception(def);
      if (Math.random() < 0.55 + contest * 0.3) return this.incomplete('deflect', def);
    }
    if (recIn && !outOfBounds && this.pass.type !== 'away') {
      const dist01 = clamp(rd / reach, 0, 1);
      let p = rec.r.cat * (1 - 0.18 * dist01) * (1 - contest * 0.55);
      if (rec.user) p *= 1.03;
      if (Math.random() < p) return this.completion(rec);
      return this.incomplete('drop', rec);
    }
    return this.incomplete(outOfBounds ? 'oob' : 'ground');
  }

  completion(rec) {
    this.giveBall(rec, true);
    this.ballState = 'run';
    this.carrier = rec;
    rec.catching = 0;
    if (rec.job) rec.job.caught = true;
    this.catchSpot = { x: rec.p.x, z: rec.p.z };
    this.emit('catch', { rec });
  }

  interception(def) {
    this.turnover = true;
    this.giveBall(def, true);
    this.ballState = 'run';
    this.carrier = def;
    this.emit('interception', { by: def });
  }

  incomplete(why, who) {
    const ball = this.world.ball;
    // Let the ball fall to the turf.
    const f = ball.flight;
    if (f) {
      const v = new THREE.Vector3(f.vx * 0.35, -2, f.vz * 0.35);
      ball.launch(ball.mesh.position.clone(), ball.mesh.position.clone().add(v.multiplyScalar(0.5)).setY(0.12), 0.5, 'tumble');
    }
    this.endPlay({ kind: 'incomplete', why, who, x: this.los, z: this.ballZ });
  }

  // ------------------------------------------------------------ end of play
  endPlay(res) {
    if (this.result) return;
    res.carrier = this.carrier;
    res.turnover = !!this.turnover;
    res.thrown = this.thrown;
    res.catchSpot = this.catchSpot;
    res.playType = this.play.type;
    res.passTarget = this.passTarget;
    res.time = this.t;
    this.result = res;
    this.phase = 'post';
    this.postT = 0;
    if (res.kind === 'td' && this.carrier) {
      this.carrier.celebrate = true;
    }
    this.emit('end', res);
  }

  updatePost(dt) {
    this.postT += dt;
    const ball = this.world.ball;
    if (ball.flight) ball.update(dt);
    const hud = this.huddle;
    for (const a of this.athletes) {
      if (!a.active) continue;
      if (a.down) {
        a.downT += dt;
        a.v.x *= 0.88; a.v.z *= 0.88;
        a.p.x += a.v.x * dt; a.p.z += a.v.z * dt;
        if (this.postT > 1.4 + (a === this.carrier ? 0.6 : 0) && a.downT > 1.2) { a.down = false; }
        continue;
      }
      if (a.engaged) { a.engaged.engaged = null; a.engaged = null; }
      if (a.celebrate) {
        this.steer(a, a.v.x * 0.9, a.v.z * 0.9, dt);
        if (this.postT > 4) a.celebrate = false;
        continue;
      }
      if (this.result?.kind === 'td' && this.carrier && a.teamKey === this.carrier.teamKey && dist(a.p, this.carrier.p) < 25 && this.postT > 0.5 && !hud) {
        this.seek(a, this.carrier.p.x, this.carrier.p.z, dt, 0.6, 2.5);
        continue;
      }
      if (hud && this.postT > 1.8) {
        // Walk back toward the next huddle.
        const onOff = a.teamKey === hud.offKey;
        const idx = a._hIdx ?? (a._hIdx = Math.floor(Math.random() * 11));
        const ang = (idx / 11) * Math.PI * 2;
        const u = onOff ? -8 + Math.cos(ang) * 2.2 : 6 + Math.cos(ang) * 3;
        const v = onOff ? Math.sin(ang) * 2.2 : Math.sin(ang) * 6;
        const tx = hud.los + hud.dir * u, tz = hud.ballZ + v;
        const d = this.seek(a, tx, tz, dt, 0.32, 2);
        a.anim = d < 0.3 ? 'idle' : 'run';
        continue;
      }
      const sp = Math.hypot(a.v.x, a.v.z);
      const slow = Math.max(0, sp - dt * 6);
      if (sp > 0.01) this.steer(a, a.v.x / sp * slow, a.v.z / sp * slow, dt, 9);
    }
  }

  setHuddle(los, dir, ballZ, offKey) {
    this.huddle = { los, dir, ballZ, offKey };
  }

  // ------------------------------------------------------------ kicks
  // Scripted special-teams scenes: kickoff, punt, field goal / PAT.
  setupKick(opts) {
    this.phase = 'kick';
    this.result = null;
    this.carrier = null;
    this.kick = { ...opts, t: 0, stage: 'set', done: false };
    this.huddle = null;
    this.turnover = false;
    const { kickKey, recKey, spotX, dir, type } = opts;
    this.offKey = kickKey; this.defKey = recKey;
    this.los = spotX; this.dir = dir; this.ballZ = opts.z || 0;
    for (const a of this.athletes) a.reset();
    const K = this.byTeam[kickKey], Rr = this.byTeam[recKey];
    const kickers = ['TE', 'X', 'Z', 'SL', 'SL2', 'FB', 'MIKE', 'WILL', 'SS', 'NB'];
    this.off = []; this.def = [];
    const kicker = type === 'punt' ? K.P : K.K;
    const kickerSide = [];
    if (type === 'kickoff') {
      const lineup = kickers;
      lineup.forEach((slot, i) => {
        const a = K[slot];
        const v = (i - 4.5) * 4.6;
        a.align = { u: -1, v };
        kickerSide.push(a);
      });
      kicker.align = { u: -7, v: 0 };
      kickerSide.push(kicker);
      const rl = KICK_REC.kickoff;
      const recSpots = [[10, -18], [10, -9], [10, 0], [10, 9], [10, 18], [20, -12], [20, 0], [20, 12], [32, -6], [32, 6], [63, 0]];
      rl.forEach((slot, i) => { Rr[slot].align = { u: recSpots[i][0], v: recSpots[i][1] }; });
      this.returner = Rr.RB;
    } else if (type === 'punt') {
      const lineup = ['LT', 'LG', 'C', 'RG', 'RT', 'TE', 'X', 'Z', 'SL', 'MIKE'];
      const spots = [[-0.8, -2.8], [-0.8, -1.4], [-0.6, 0], [-0.8, 1.4], [-0.8, 2.8], [-0.8, 4.3], [-0.8, -18], [-0.8, 18], [-6, 1.5], [-6, -1.5]];
      lineup.forEach((slot, i) => { K[slot].align = { u: spots[i][0], v: spots[i][1] }; kickerSide.push(K[slot]); });
      kicker.align = { u: -14, v: 0 };
      kickerSide.push(kicker);
      const rl = KICK_REC.punt;
      const recSpots = [[1, -3.5], [1, -1], [1, 1.2], [1, 3.6], [4, -4], [4, 4], [1.5, -17], [1.5, 17], [12, 0], [20, -6], [40, 0]];
      rl.forEach((slot, i) => { Rr[slot].align = { u: recSpots[i][0], v: recSpots[i][1] }; });
      this.returner = Rr.FS;
    } else {
      // Field goal / PAT.
      const lineup = ['LT', 'LG', 'C', 'RG', 'RT', 'TE', 'SL', 'X', 'Z'];
      const spots = [[-0.8, -2.6], [-0.8, -1.3], [-0.6, 0], [-0.8, 1.3], [-0.8, 2.6], [-0.9, 3.9], [-0.9, -3.9], [-1.4, 5.0], [-1.4, -5.0]];
      lineup.forEach((slot, i) => { K[slot].align = { u: spots[i][0], v: spots[i][1] }; kickerSide.push(K[slot]); });
      const holder = K.QB;
      holder.align = { u: -7, v: 0 };
      kickerSide.push(holder);
      this.holder = holder;
      kicker.align = { u: -10, v: -2.2 };
      kickerSide.push(kicker);
      const rl = KICK_REC.fg;
      const recSpots = [[1, -3.2], [1, -1.0], [1, 1.0], [1, 3.2], [1.2, -5.2], [1.2, 5.2], [3, -7], [3, 7], [6, -9], [6, 9], [12, 0]];
      rl.forEach((slot, i) => { Rr[slot].align = { u: recSpots[i][0], v: recSpots[i][1] }; });
      this.returner = null;
    }
    this.kicker = kicker;
    for (const a of kickerSide) { a.side = 'off'; a.active = true; this.off.push(a); }
    for (const slot of KICK_REC[type]) { const a = Rr[slot]; a.side = 'def'; a.active = true; this.def.push(a); }
    for (const a of this.athletes) {
      a.model.root.visible = a.active;
      if (a.active) a.target = this.W(a.align.u, a.align.v);
    }
    this.snapToAlignment();
    for (const a of [...this.off, ...this.def]) a.anim = 'stance2';
    if (type === 'fg' || type === 'pat') {
      for (const a of this.off) if (['LT', 'LG', 'C', 'RG', 'RT', 'TE', 'SL'].includes(a.slot)) a.anim = 'stance3';
      for (const a of this.def) if (['LE', 'DT1', 'DT2', 'RE'].includes(a.slot)) a.anim = 'stance3';
      this.holder.anim = 'hold';
      this.world.ball.attach(this.holder.model.handAnchor, false);
    } else if (type === 'kickoff') {
      this.world.ball.place(this.los, 0.25, 0, 0);
      this.world.ball.mesh.rotation.set(0, 0, 0);
    } else {
      this.world.ball.place(this.los + this.dir * 0.15, 0.12, this.ballZ, this.dir > 0 ? Math.PI / 2 : -Math.PI / 2);
    }
  }

  // Start the kick. outcome is precomputed by the game: { land:{x,z}, T, kind, apex }
  startKick(outcome) {
    const k = this.kick;
    k.stage = 'approach';
    k.outcome = outcome;
    k.t = 0;
  }

  updateKick(dt) {
    const k = this.kick;
    if (!k) return;
    k.t += dt;
    const ball = this.world.ball;
    const kicker = this.kicker;
    const type = k.type;
    if (k.stage === 'set') {
      for (const a of [...this.off, ...this.def]) this.steer(a, 0, 0, dt);
      if (type === 'punt' || type === 'fg' || type === 'pat') kicker.anim = 'stance2';
      return;
    }
    if (k.stage === 'approach') {
      if (type === 'kickoff') {
        const spot = { x: this.los - this.dir * 0.6, z: -0.3 };
        this.seek(kicker, spot.x, spot.z, dt, 0.85, 0.01);
        kicker.anim = 'run';
        for (const a of this.off) if (a !== kicker && k.t > 0.6) this.seek(a, a.p.x + this.dir * 3, a.p.z, dt, 0.6);
        if (dist(kicker.p, spot) < 0.5 || k.t > 2.2) this.kickBall(k);
      } else if (type === 'punt') {
        // Snap to the punter, two steps, drop and kick.
        if (!k.snapped) {
          k.snapped = true;
          const from = new THREE.Vector3(this.los, 0.4, this.ballZ);
          const to = new THREE.Vector3(kicker.p.x, 1.2, kicker.p.z);
          ball.launch(from, to, 0.75, 'spiral');
        }
        ball.update(dt);
        if (k.t > 0.75) {
          if (!k.caught) { k.caught = true; ball.attach(kicker.model.handAnchor, false); }
          this.seek(kicker, kicker.p.x + this.dir * 2, kicker.p.z, dt, 0.3);
          if (k.t > 1.45) this.kickBall(k);
        }
        this.lineBattle(dt);
      } else {
        if (!k.snapped) {
          k.snapped = true;
          this.world.ball.detachTo(this.world.scene);
          const from = new THREE.Vector3(this.los, 0.4, this.ballZ);
          const h = this.holder;
          const to = new THREE.Vector3(h.p.x + this.dir * 0.4, 0.5, h.p.z);
          ball.launch(from, to, 0.45, 'spiral');
        }
        ball.update(dt);
        if (k.t > 0.45 && !k.placed) {
          k.placed = true;
          const h = this.holder;
          ball.place(h.p.x + this.dir * 0.45, 0.32, h.p.z, 0);
          ball.mesh.rotation.set(0, 0, 0.15);
        }
        if (k.t > 0.55) {
          const spot = { x: this.holder.p.x - this.dir * 0.7, z: this.holder.p.z - 0.6 };
          this.seek(kicker, spot.x, spot.z, dt, 0.5, 0.01);
          kicker.anim = 'run';
          if ((dist(kicker.p, spot) < 0.35 || k.t > 1.6) && !k.kicked) this.kickBall(k);
        }
        this.lineBattle(dt);
      }
      return;
    }
    if (k.stage === 'flight') {
      ball.update(dt);
      kicker.kickT = (kicker.kickT || 0) + dt * 2.2;
      const f = ball.flight;
      const landT = k.outcome.T;
      if (type === 'kickoff' || type === 'punt') {
        // Coverage runs downfield; returners settle under it.
        for (const a of this.off) if (a !== kicker) this.seek(a, k.outcome.land.x, a.p.z * 0.85 + k.outcome.land.z * 0.15, dt, 0.95, 0.01);
        if (this.returner) {
          this.seek(this.returner, k.outcome.land.x, k.outcome.land.z, dt, 0.9, 0.6);
          this.returner.catching = f.t > landT - 0.5 ? 0.3 : 0;
        }
        for (const a of this.def) if (a !== this.returner) {
          const back = { x: k.outcome.land.x - this.dir * 8, z: a.p.z };
          this.seek(a, a.p.x * 0.7 + back.x * 0.3, a.p.z, dt, 0.55);
        }
      } else {
        this.lineBattle(dt);
      }
      if (f.t >= landT) {
        k.stage = 'land';
        k.t = 0;
        if ((type === 'kickoff' || type === 'punt') && this.returner && k.outcome.kind === 'return') {
          ball.attach(this.returner.model.carryAnchor, true);
          k.carrier = this.returner;
        } else if ((type === 'kickoff' || type === 'punt') && this.returner && k.outcome.kind === 'fair') {
          ball.attach(this.returner.model.carryAnchor, true);
        }
        this.emit('kickLand', k.outcome);
      }
      return;
    }
    if (k.stage === 'land') {
      if (ball.flight) ball.update(dt);
      const o = k.outcome;
      if (k.carrier) {
        // Scripted return toward the precomputed tackle spot.
        const c = k.carrier;
        const spot = { x: o.endX, z: o.endZ };
        const d = this.seek(c, spot.x, spot.z, dt, 0.95, 0.01);
        c.anim = 'carry';
        for (const a of this.off) this.seek(a, c.p.x, c.p.z, dt, 1, 0.01);
        if (d < 0.6 && !k.tackled) {
          k.tackled = true;
          this.knockDown(c, false, 0);
          const tk = this.nearestTo(c, this.off);
          if (tk) this.knockDown(tk, false, 0);
          this.emit('hit', { power: 12 });
        }
        if (k.tackled && k.t > 1.4 && !k.done) { k.done = true; this.emit('kickDone', o); }
      } else {
        for (const a of [...this.off, ...this.def]) this.steer(a, a.v.x * 0.9, a.v.z * 0.9, dt, 6);
        if (k.t > 1.6 && !k.done) { k.done = true; this.emit('kickDone', o); }
      }
    }
  }

  lineBattle(dt) {
    for (const a of this.def) {
      if (['LE', 'DT1', 'DT2', 'RE', 'MIKE', 'WILL'].includes(a.slot)) {
        const tgt = { x: this.los - this.dir * 2, z: a.p.z * 0.9 };
        this.seek(a, tgt.x, tgt.z, dt, 0.35);
        a.anim = 'block';
      }
    }
    for (const a of this.off) {
      if (['LT', 'LG', 'C', 'RG', 'RT', 'TE', 'SL'].includes(a.slot)) {
        this.steer(a, -this.dir * 0.3, 0, dt);
        a.anim = 'block';
      }
    }
  }

  kickBall(k) {
    const ball = this.world.ball;
    const o = k.outcome;
    const kicker = this.kicker;
    const p0 = ball.mesh.parent === this.world.scene ? ball.mesh.position.clone() : ball.mesh.getWorldPosition(new THREE.Vector3());
    if (k.type === 'punt') p0.y = 1.1;
    const p1 = new THREE.Vector3(o.land.x, o.landY ?? 0.3, o.land.z);
    ball.launch(p0, p1, o.T, k.type === 'punt' ? 'spiral' : 'tumble');
    k.stage = 'flight';
    k.kicked = true;
    kicker.kickT = 0;
    this.emit('kick', { type: k.type });
  }

  // ------------------------------------------------------------ visuals
  integrateModels(dt) {
    for (const a of this.athletes) {
      if (!a.active) continue;
      const sp = Math.hypot(a.v.x, a.v.z);
      let face = a.h;
      if (a.facingLock != null) {
        face = a.facingLock;
        a.facingLock = null;
        a.h = dampAngle(a.h, face, 9, dt);
      } else if (sp > 0.6 && !a.engaged && !a.down) {
        a.h = dampAngle(a.h, Math.atan2(a.v.z, a.v.x), 10, dt);
      }
      const fwd = a.v.x * Math.cos(a.h) + a.v.z * Math.sin(a.h);
      let mode = a.anim;
      const isCarrier = this.carrier === a || (this.kick?.carrier === a);
      if (this.phase === 'live' || this.phase === 'post' || this.phase === 'kick') {
        if (a.down) mode = 'down';
        else if (a.celebrate) mode = 'celebrate';
        else if (a.engaged) mode = 'block';
        else if (a === this.qb && a.throwT != null && a.throwT < 1.05) mode = 'throw';
        else if (a.catching > 0) mode = 'catch';
        else if (isCarrier && a.stiff > 0) mode = 'stiffarm';
        else if (this.kick && a === this.kicker && this.kick.kicked && a.kickT < 1) mode = 'kick';
        else if (this.kick && a === this.holder && this.kick.stage !== 'land') mode = 'hold';
        else if (this.phase === 'kick' && this.kick.stage === 'set') mode = a.anim;
        else if (this.phase === 'kick' && (a.anim === 'stance3') && this.kick.stage === 'approach' && this.kick.t < 0.3) mode = 'stance3';
        else if (this.phase === 'kick' && a.anim === 'block') mode = 'block';
        else if (fwd < -0.8) mode = 'backpedal';
        else mode = isCarrier ? 'carry' : 'run';
        // Shotgun QB before the snap arrives.
        if (this.phase === 'live' && a === this.qb && this.ballState === 'snap') mode = this.shotgun ? 'qbGun' : 'qbUnder';
      }
      if (a.throwT != null) { a.throwT += dt * 2.2; if (a.throwT > 1.4) a.throwT = null; }
      if (a.catching > 0) a.catching -= dt;
      a.model.animate({
        mode,
        speed: mode === 'backpedal' ? fwd : Math.max(sp * 0.98, Math.abs(fwd)),
        t: mode === 'down' ? a.downT * 1.6 : mode === 'throw' ? a.throwT : mode === 'kick' ? a.kickT : 0,
        carry: isCarrier && !a.down,
        backward: a.downBack,
        roll: a.downRoll,
      }, dt);
      a.model.setTransform(a.p.x, a.p.z, a.h);
    }
  }

  setVisibleOnly(list) {
    for (const a of this.athletes) {
      a.active = list.includes(a);
      a.model.root.visible = a.active;
    }
  }
}

export { OFF_SLOTS, DEF_SLOTS, ELIGIBLE };
