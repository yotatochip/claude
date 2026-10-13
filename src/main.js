// Entry point: builds the world, wires input/UI/audio and runs the frame loop.
import * as THREE from 'three';
import { Graphics } from './graphics.js';
import { Field } from './field.js';
import { Stadium } from './stadium.js';
import { Football } from './ball.js';
import { PlaySim } from './sim.js';
import { Game } from './game.js';
import { CameraDirector } from './camera.js';
import { UI } from './ui.js';
import { Input } from './input.js';
import { AudioEngine } from './audio.js';
import { TEAMS, buildRoster } from './data.js';
import { PlayerModel } from './player-model.js';
import { blobShadowTexture } from './textures.js';

const app = { game: null, paused: false, world: null };
window.__gridiron = app; // handy for debugging from the console
app.cameraContext = () => cameraContext();
const tmp = new THREE.Vector3();

async function loadFonts() {
  if (!document.fonts?.load) return;
  const want = ['900 64px "Big Shoulders Display"', '800 64px "Big Shoulders Display"', '700 64px "Big Shoulders Display"', '700 20px Archivo', '500 20px Archivo'];
  await Promise.race([
    Promise.all(want.map((f) => document.fonts.load(f).catch(() => null))),
    new Promise((r) => setTimeout(r, 2500)),
  ]);
}

const nextFrame = () => new Promise((r) => requestAnimationFrame(() => setTimeout(r, 0)));

function disposeTree(obj) {
  obj.traverse((o) => {
    if (o.geometry) o.geometry.dispose();
    const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
    for (const m of mats) {
      for (const k of ['map', 'normalMap', 'emissiveMap']) m[k]?.dispose?.();
      m.dispose();
    }
  });
}

async function buildWorld(home, away, settings) {
  const gfx = app.gfx;
  const key = `${home.id}|${away.id}|${settings.quality}`;
  if (app.world?.key === key) {
    if (app.world.time !== settings.time) {
      gfx.setTimeOfDay(settings.time, app.world.stadium);
      app.world.time = settings.time;
    }
    return app.world;
  }
  if (app.world) {
    gfx.scene.remove(app.world.field.group, app.world.stadium.group);
    disposeTree(app.world.field.group);
    disposeTree(app.world.stadium.group);
  }
  app.ui.loading('Painting the field');
  await nextFrame();
  const field = new Field(gfx.scene, home);
  app.ui.loading('Filling the stands');
  await nextFrame();
  const stadium = new Stadium(gfx.scene, home, away, gfx.q.crowd);
  gfx.setTimeOfDay(settings.time, stadium);
  app.world = { key, field, stadium, time: settings.time, home, away };
  app.ui.loading(null);
  return app.world;
}

function makeHero(team) {
  app.ball.place(0, 0.12, 0);
  if (app.hero) { app.gfx.scene.remove(app.hero.root); app.hero.dispose(); }
  const roster = buildRoster(team);
  const hero = new PlayerModel(team, 'home', roster.QB);
  hero.setTransform(-17, 3, -0.55);
  app.gfx.scene.add(hero.root);
  app.ball.attach(hero.carryAnchor, true);
  app.hero = hero;
}

function addBlobs(sim) {
  const tex = app.blobTex || (app.blobTex = blobShadowTexture());
  const geo = new THREE.PlaneGeometry(1.5, 1.5);
  geo.rotateX(-Math.PI / 2);
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -1 });
  for (const a of sim.athletes) {
    const m = new THREE.Mesh(geo, mat);
    m.position.y = 0.02;
    m.renderOrder = 1;
    a.model.root.add(m);
  }
}

async function startGame(settings) {
  const user = TEAMS.find((t) => t.id === settings.userTeam);
  const opp = TEAMS.find((t) => t.id === settings.oppTeam);
  const home = settings.userHome ? user : opp;
  const away = settings.userHome ? opp : user;
  app.audio.start();
  app.settings = settings;
  applyQuality(settings.quality);
  const world = await buildWorld(home, away, settings);
  app.ball.place(0, 0.12, 0);
  if (app.hero) { app.gfx.scene.remove(app.hero.root); app.hero.dispose(); app.hero = null; }
  app.ui.loading('Suiting up');
  await nextFrame();
  const sim = new PlaySim({ scene: app.gfx.scene, ball: app.ball, field: world.field });
  const game = new Game({
    sim, field: world.field, stadium: world.stadium, ball: app.ball, ui: app.ui, audio: app.audio,
    settings, home, away, userKey: settings.userHome ? 'home' : 'away',
  });
  addBlobs(sim);
  app.ui.loading(null);
  app.game = game;
  app.paused = false;
  sim.on((type, data) => {
    if (type === 'hit') app.cam.bump(Math.min(0.6, (data.power || 8) / 25));
  });
  if (app.restore) { restoreGame(game, app.restore); app.restore = null; }
  else game.start();
  app.cam.cut();
}

function quitGame() {
  const g = app.game;
  if (!g) return;
  for (const a of g.sim.athletes) {
    app.gfx.scene.remove(a.model.root);
    a.model.dispose();
  }
  app.game = null;
  app.paused = false;
  app.ui.setPaused(false);
  app.ui.setIcons([]);
  app.ui.showTitle();
  app.audio.band(false);
  const s = app.ui.settings;
  makeHero(TEAMS.find((t) => t.id === s.userTeam));
  app.cam.cut();
}

function applyQuality(q) {
  const gfx = app.gfx;
  if (gfx.qualityName === q) return;
  gfx.qualityName = q;
  const preset = { high: { pr: 2, shadow: 4096, bloom: true, crowd: 'high' }, medium: { pr: 1.25, shadow: 2048, bloom: true, crowd: 'medium' }, low: { pr: 1, shadow: 1024, bloom: false, crowd: 'low' } }[q];
  gfx.q = { ...gfx.q, crowd: preset.crowd, bloom: preset.bloom };
  gfx.basePixelRatio = Math.min(window.devicePixelRatio || 1, preset.pr);
  gfx.bloom.enabled = preset.bloom;
  gfx.sun.shadow.mapSize.set(preset.shadow, preset.shadow);
  gfx.sun.shadow.map?.dispose();
  gfx.sun.shadow.map = null;
  gfx.resize();
}

// ------------------------------------------------------------ camera context
function cameraContext() {
  const g = app.game;
  if (!g) return { mode: 'hero', focus: app.hero ? app.hero.root.position : { x: 0, z: 0 } };
  const s = g.sim;
  if (g.state === 'final') return { mode: 'menu' };
  if (g.state === 'break' && g.quarter === 3 && g.clock === g.qLen && !g.ot && g.timer > 1) return { mode: 'sideline', focus: { x: 0, z: 0 } };
  const ball = app.ball.mesh.getWorldPosition(tmp);
  if (['kickoff', 'kicking', 'kickMeter'].includes(g.state) && g.kickInfo && s.phase === 'kick') {
    const t = g.kickInfo.type;
    if ((t === 'fg' || t === 'pat') && s.holder) return { mode: 'goalpost', ball, viewDir: g.kickInfo.dir, kickSpot: s.holder.p };
    return { mode: 'kick', ball, viewDir: g.kickInfo.dir };
  }
  if (g.state === 'post' && s.result?.kind === 'td' && s.postT > 0.9 && s.carrier) {
    return { mode: 'celebrate', focus: s.carrier.p, angle: g.dir > 0 ? Math.PI : 0 };
  }
  const userOff = (s.offKey || g.offKey) === g.userKey;
  const dir = s.phase === 'live' || s.phase === 'post' ? s.dir : g.dir;
  const viewDir = userOff ? dir : -dir;
  let focus = { x: g.ballX, z: g.ballZ };
  const live = g.state === 'live' || g.state === 'post';
  let air = false, ballY = 0, target = null;
  if (live && s.ballState === 'air') {
    focus = { x: ball.x, z: ball.z };
    air = true;
    ballY = ball.y;
    target = s.pass?.target || null;
  }
  else if (live && s.carrier) focus = { x: s.carrier.p.x, z: s.carrier.p.z };
  else if (g.state === 'presnap' || g.state === 'playcall') focus = { x: g.ballX + g.dir * (userOff ? 0 : 1.5), z: g.ballZ };
  return { mode: 'broadcast', focus, viewDir, live: live && s.phase === 'live', air, ballY, target, ballPos: air ? ball.clone() : null };
}

function project(x, y, z) {
  tmp.set(x, y, z).project(app.gfx.camera);
  if (tmp.z > 1) return null;
  const c = app.gfx.renderer.domElement;
  return { x: (tmp.x + 1) / 2 * c.clientWidth, y: (1 - tmp.y) / 2 * c.clientHeight };
}

// ------------------------------------------------------------ frame loop
let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.05, Math.max(0.001, (now - last) / 1000));
  last = now;
  const { gfx, cam, ui, input, audio } = app;
  const ctrl = input.poll(dt, (x, y) => cam.stickToWorld(x, y));
  if (ctrl.mute) audio.setMuted(!audio.muted);
  if (ctrl.help) ui.toggleHelp();
  const g = app.game;
  if (g) {
    if (ctrl.pause && g.state !== 'final') { app.paused = !app.paused; ui.setPaused(app.paused); }
    if (!app.paused) {
      if (!ui.els.playcall.hidden && ui.navigate(ctrl)) { ctrl.snap = false; ctrl.dive = false; }
      input.consumeQueued(ctrl);
      if (ctrl.throwGlyph) {
        const r = g.sim.icons.find((a) => a.glyph === ctrl.throwGlyph);
        if (r) ctrl.throwKey = r.key;
      }
      g.update(dt, ctrl);
    }
  } else {
    if (ctrl.confirm && !ui.title.hidden) ui.startGame();
    if (app.hero) app.hero.animate({ mode: 'carry', speed: 0 }, dt);
  }
  const world = app.world;
  if (world) {
    world.stadium.update(dt);
    audio.update(world.stadium.excite);
  }
  if (!app.paused) app.ball.updateEffects(dt, gfx.camera);
  const cctx = cameraContext();
  cam.update(dt, cctx);
  const f = cctx.focus || cctx.ball || { x: 0, z: 0 };
  gfx.focusShadows(f.x + (cctx.viewDir || 0) * 10, f.z * 0.7);
  updateRing(g);
  if (g) ui.updateIcons(project);
  gfx.render(dt);
  gfx.adapt(dt);
}

function updateRing(g) {
  const ring = app.ring;
  const a = g?.sim.userAthlete;
  const show = g && a && a.active && (g.state === 'live' || g.state === 'presnap') && !a.down;
  ring.visible = !!show;
  if (show) {
    ring.position.set(a.p.x, 0.03, a.p.z);
    ring.material.color.set(a === g.sim.carrier ? '#ffd21a' : '#5ab0ff');
    ring.rotation.z += 0.02;
  }
}

// ------------------------------------------------------------ hot snapshot (artifact viewer)
function snapshot() {
  const g = app.game;
  if (!g || g.state === 'final') return { settings: app.ui?.settings };
  return {
    settings: app.settings,
    game: {
      score: g.score, quarter: g.quarter, clock: g.clock, possession: g.possession, ballX: g.ballX, ballZ: g.ballZ,
      down: g.down, firstDownX: g.firstDownX, stats: g.stats, firstReceiver: g.firstReceiver, ot: g.ot,
    },
  };
}

function restoreGame(g, data) {
  Object.assign(g, {
    score: data.score, quarter: data.quarter, clock: data.clock, possession: data.possession, ballX: data.ballX,
    ballZ: data.ballZ, down: data.down, firstDownX: data.firstDownX, stats: data.stats, firstReceiver: data.firstReceiver, ot: data.ot,
  });
  g.kickoffBy = null;
  g.next();
}

// ------------------------------------------------------------ boot
async function boot(hotData = {}) {
  const stage = document.getElementById('stage');
  const uiRoot = document.getElementById('ui');
  app.input = new Input();
  app.audio = new AudioEngine();
  app.ui = new UI(uiRoot, {
    onStart: (s) => startGame(s),
    onPreview: (s) => previewTitle(s),
    onResume: () => { app.paused = false; app.ui.setPaused(false); },
    onQuit: () => quitGame(),
    onMute: () => app.audio.setMuted(!app.audio.muted),
    onIconThrow: (key, lob) => app.input.queueThrow(key, lob),
  });
  if (hotData.settings) Object.assign(app.ui.settings, hotData.settings), app.ui.syncTitle();
  app.ui.loading('Loading');
  await loadFonts();
  const s = app.ui.settings;
  let gfx;
  try {
    gfx = new Graphics(stage, s.quality);
  } catch (err) {
    app.ui.loading('This browser could not start WebGL. Try a recent Chrome, Edge, Firefox or Safari with hardware acceleration on.');
    return;
  }
  app.gfx = gfx;
  app.cam = new CameraDirector(gfx.camera);
  app.ball = new Football(gfx.scene);
  const ringGeo = new THREE.RingGeometry(0.62, 0.78, 48, 1, 0, Math.PI * 1.7);
  ringGeo.rotateX(-Math.PI / 2);
  app.ring = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: '#ffd21a', transparent: true, opacity: 0.9, toneMapped: false, depthWrite: false }));
  app.ring.renderOrder = 3;
  app.ring.rotation.order = 'YXZ';
  gfx.scene.add(app.ring);
  app.ui.setTouchInput(app.input);
  const user = TEAMS.find((t) => t.id === s.userTeam);
  const opp = TEAMS.find((t) => t.id === s.oppTeam);
  await buildWorld(s.userHome ? user : opp, s.userHome ? opp : user, s);
  makeHero(user);
  app.cam.cut();
  requestAnimationFrame((t) => { last = t; frame(t); });
  window.claude?.hot?.snapshot?.(snapshot);
  if (hotData.game && hotData.settings) {
    app.restore = hotData.game;
    app.ui.title.hidden = true;
    app.ui.hudRoot.hidden = false;
    startGame(hotData.settings);
  }
}

let previewBusy = false;
async function previewTitle(s) {
  if (previewBusy || app.game || !app.gfx) return;
  previewBusy = true;
  try {
    applyQuality(s.quality);
    const user = TEAMS.find((t) => t.id === s.userTeam);
    const opp = TEAMS.find((t) => t.id === s.oppTeam);
    await buildWorld(s.userHome ? user : opp, s.userHome ? opp : user, s);
    makeHero(user);
  } finally {
    previewBusy = false;
  }
}

const hot = window.claude?.hot;
if (hot?.ready) hot.ready(boot);
else boot(hot?.data ?? {});
