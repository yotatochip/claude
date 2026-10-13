// DOM overlay: title menu, score bug, play-call cards, banners and receiver icons.
import { TEAMS, FORMATIONS, routeFor } from './data.js';

const GLYPH_SVG = {
  cross: '<svg viewBox="0 0 24 24"><path d="M5 5L19 19M19 5L5 19" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/></svg>',
  circle: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="3"/></svg>',
  square: '<svg viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="14" rx="1.5" fill="none" stroke="currentColor" stroke-width="3"/></svg>',
  tri: '<svg viewBox="0 0 24 24"><path d="M12 4.5L20 18.5H4Z" fill="none" stroke="currentColor" stroke-width="3" stroke-linejoin="round"/></svg>',
  r1: '<svg viewBox="0 0 24 24"><text x="12" y="16.5" text-anchor="middle" font-size="11" font-weight="800" fill="currentColor" font-family="Archivo, sans-serif">R1</text></svg>',
};

const $ = (sel, root = document) => root.querySelector(sel);
const el = (tag, cls, html) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  return e;
};

export class UI {
  constructor(root, handlers) {
    this.root = root;
    this.h = handlers;
    this.iconEls = new Map();
    this.cards = [];
    this.cardIdx = 0;
    this.settings = this.loadSettings();
    this.buildTitle();
    this.buildHud();
    this.buildPause();
  }

  loadSettings() {
    const touch = typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches;
    const def = { userTeam: 'ash', oppTeam: 'lkt', userHome: true, quarterMinutes: 5, difficulty: 'varsity', time: 'night', quality: touch ? 'medium' : 'high' };
    try {
      const s = JSON.parse(localStorage.getItem('gs26-settings') || '{}');
      return { ...def, ...s };
    } catch { return def; }
  }
  saveSettings() {
    try { localStorage.setItem('gs26-settings', JSON.stringify(this.settings)); } catch { /* storage unavailable */ }
  }

  // ------------------------------------------------------------ title
  buildTitle() {
    const t = el('section', 'title-screen');
    t.id = 'title';
    t.innerHTML = `
      <div class="title-brand">
        <div class="brand-kicker">College Football · Saturday Night</div>
        <h1 class="brand-mark"><span>Gridiron</span><span>Saturday</span><em>26</em></h1>
        <p class="brand-line">Full 11-on-11 college football in your browser. Call the play, read the coverage, win the fourth quarter.</p>
      </div>
      <div class="title-panel">
        <div class="matchup">
          <div class="pick" id="pick-user"><div class="pick-label">Your team</div><div class="team-list" id="list-user"></div></div>
          <div class="vs">VS</div>
          <div class="pick" id="pick-opp"><div class="pick-label">Opponent</div><div class="team-list" id="list-opp"></div></div>
        </div>
        <div class="settings">
          <label>Venue<select id="set-venue"><option value="home">Home game</option><option value="away">Road game</option></select></label>
          <label>Quarter<select id="set-quarter"><option value="3">3 min</option><option value="5">5 min</option><option value="8">8 min</option></select></label>
          <label>Difficulty<select id="set-diff"><option value="rookie">Freshman</option><option value="varsity">Varsity</option><option value="allamerican">All-American</option><option value="heisman">Heisman</option></select></label>
          <label>Kickoff<select id="set-time"><option value="day">Noon</option><option value="dusk">Dusk</option><option value="night">Night</option></select></label>
          <label>Graphics<select id="set-quality"><option value="high">High</option><option value="medium">Medium</option><option value="low">Low</option></select></label>
        </div>
        <button class="btn-primary" id="btn-start" type="button">Kick off <span class="kbd">Enter</span></button>
        <p class="controls-hint">WASD / arrows move · Shift sprint · Space snap · 1–5 throw (tap = touch, hold = bullet) · E juke · F stiff-arm · Tab switch · T timeout · H controls · Gamepad supported</p>
      </div>`;
    this.root.appendChild(t);
    this.title = t;
    const lists = { user: $('#list-user', t), opp: $('#list-opp', t) };
    for (const which of ['user', 'opp']) {
      for (const team of TEAMS) {
        const b = el('button', 'team-btn');
        b.type = 'button';
        b.dataset.id = team.id;
        b.style.setProperty('--c1', team.primary);
        b.style.setProperty('--c2', team.secondary);
        b.innerHTML = `<span class="swatch"><b>${team.letter}</b></span><span class="tname"><strong>${team.school}</strong><small>${team.name}</small></span><span class="ovr">${team.ovr}</span>`;
        b.addEventListener('click', () => {
          const key = which === 'user' ? 'userTeam' : 'oppTeam';
          const otherKey = which === 'user' ? 'oppTeam' : 'userTeam';
          if (this.settings[otherKey] === team.id) this.settings[otherKey] = this.settings[key];
          this.settings[key] = team.id;
          this.syncTitle();
          this.h.onPreview?.(this.settings);
        });
        lists[which].appendChild(b);
      }
    }
    const bind = (id, key, parse = (v) => v) => {
      const s = $(id, t);
      s.addEventListener('change', () => { this.settings[key] = parse(s.value); this.saveSettings(); this.h.onPreview?.(this.settings); });
    };
    bind('#set-venue', 'userHome', (v) => v === 'home');
    bind('#set-quarter', 'quarterMinutes', Number);
    bind('#set-diff', 'difficulty');
    bind('#set-time', 'time');
    bind('#set-quality', 'quality');
    $('#btn-start', t).addEventListener('click', () => this.startGame());
    this.syncTitle();
  }

  syncTitle() {
    const s = this.settings;
    for (const b of this.title.querySelectorAll('#list-user .team-btn')) b.classList.toggle('on', b.dataset.id === s.userTeam);
    for (const b of this.title.querySelectorAll('#list-opp .team-btn')) b.classList.toggle('on', b.dataset.id === s.oppTeam);
    $('#set-venue', this.title).value = s.userHome ? 'home' : 'away';
    $('#set-quarter', this.title).value = String(s.quarterMinutes);
    $('#set-diff', this.title).value = s.difficulty;
    $('#set-time', this.title).value = s.time;
    $('#set-quality', this.title).value = s.quality;
    const team = TEAMS.find((x) => x.id === s.userTeam);
    document.documentElement.style.setProperty('--team', team.primary);
    this.saveSettings();
  }

  startGame() {
    this.saveSettings();
    this.title.hidden = true;
    this.hudRoot.hidden = false;
    this.h.onStart?.(this.settings);
  }

  showTitle() {
    this.title.hidden = false;
    this.hudRoot.hidden = true;
    this.hidePlaycall();
    this.finalEl?.remove();
    this.statsEl?.remove();
    this.pauseEl.hidden = true;
  }

  // ------------------------------------------------------------ HUD
  buildHud() {
    const h = el('div', 'hud');
    h.hidden = true;
    h.innerHTML = `
      <div class="ticker" id="ticker" hidden></div>
      <div class="banner" id="banner" hidden><div class="banner-main"></div><div class="banner-sub"></div></div>
      <div class="flash" id="flash" hidden></div>
      <div class="toast" id="toast" hidden></div>
      <div class="icons" id="icons"></div>
      <div class="meter" id="meter" hidden><div class="meter-label"></div><div class="meter-bar"><div class="meter-zone"></div><div class="meter-needle"></div></div></div>
      <div class="scorebug" id="scorebug">
        <div class="sb-team" id="sb-away"><span class="sb-poss"></span><span class="sb-abbr"></span><span class="sb-to"><i></i><i></i><i></i></span><span class="sb-score"></span></div>
        <div class="sb-team" id="sb-home"><span class="sb-poss"></span><span class="sb-abbr"></span><span class="sb-to"><i></i><i></i><i></i></span><span class="sb-score"></span></div>
        <div class="sb-clock"><span class="sb-q"></span><span class="sb-time"></span></div>
        <div class="sb-down"><span class="sb-dd"></span><span class="sb-spot"></span></div>
      </div>
      <div class="playcall" id="playcall" hidden>
        <div class="pc-head"><span class="pc-side"></span><span class="pc-sit"></span><span class="pc-help">Arrows + Enter, or click a play</span></div>
        <div class="pc-cards"></div>
      </div>
      <div class="help" id="help" hidden>
        <h3>Controls</h3>
        <dl>
          <dt>Move</dt><dd>WASD / arrows · left stick</dd>
          <dt>Sprint</dt><dd>Shift · RT</dd>
          <dt>Snap</dt><dd>Space · A / ✕</dd>
          <dt>Throw</dt><dd>1–5 or click the icon · tap = touch pass, hold = bullet · face buttons on a pad</dd>
          <dt>Juke / stiff-arm</dt><dd>E / F · B / X</dd>
          <dt>Dive / tackle</dt><dd>Space · A</dd>
          <dt>Switch defender</dt><dd>Tab or Q · B</dd>
          <dt>Timeout</dt><dd>T · View / Back (between plays)</dd>
          <dt>Pause · mute</dt><dd>Esc · M</dd>
        </dl>
        <p>Press H to close.</p>
      </div>
      <div class="touchpad" id="touchpad" hidden>
        <div class="stick" id="stick"><div class="nub"></div></div>
        <div class="tbtns">
          <button type="button" data-b="a">Snap / Dive</button>
          <button type="button" data-b="sprint">Sprint</button>
          <button type="button" data-b="juke">Juke</button>
          <button type="button" data-b="switch">Switch</button>
        </div>
      </div>`;
    this.root.appendChild(h);
    this.hudRoot = h;
    this.els = {
      ticker: $('#ticker', h), banner: $('#banner', h), flash: $('#flash', h), toast: $('#toast', h), icons: $('#icons', h),
      meter: $('#meter', h), playcall: $('#playcall', h), help: $('#help', h),
    };
    $('.pc-cards', h).addEventListener('pointermove', (e) => {
      const c = e.target.closest('.card');
      if (c) this.focusCard(Number(c.dataset.i));
    });
  }

  setTouchInput(input) {
    const pad = $('#touchpad', this.hudRoot);
    const isTouch = matchMedia('(pointer: coarse)').matches;
    pad.hidden = !isTouch;
    if (!isTouch) return;
    const stick = $('#stick', pad), nub = $('.nub', stick);
    let id = null;
    const move = (e) => {
      const r = stick.getBoundingClientRect();
      const x = (e.clientX - r.left - r.width / 2) / (r.width / 2);
      const y = (e.clientY - r.top - r.height / 2) / (r.height / 2);
      const m = Math.min(1, Math.hypot(x, y)) / (Math.hypot(x, y) || 1);
      input.touch.x = x * m; input.touch.y = -y * m; input.touch.active = true;
      nub.style.transform = `translate(${x * m * 40}px, ${y * m * 40}px)`;
    };
    stick.addEventListener('pointerdown', (e) => { id = e.pointerId; stick.setPointerCapture(id); move(e); });
    stick.addEventListener('pointermove', (e) => { if (e.pointerId === id) move(e); });
    const end = () => { id = null; input.touch.active = false; input.touch.x = input.touch.y = 0; nub.style.transform = ''; };
    stick.addEventListener('pointerup', end);
    stick.addEventListener('pointercancel', end);
    for (const b of pad.querySelectorAll('button')) {
      b.addEventListener('pointerdown', () => { input.touch.buttons.add(b.dataset.b); input.touch.edges.add(b.dataset.b); });
      b.addEventListener('pointerup', () => input.touch.buttons.delete(b.dataset.b));
      b.addEventListener('pointerleave', () => input.touch.buttons.delete(b.dataset.b));
    }
  }

  setScore({ home, away, score, quarter, clock, down, spot, possession, timeouts }) {
    const set = (id, team, sc, poss) => {
      const t = $(id, this.hudRoot);
      const left = timeouts?.[id === '#sb-home' ? 'home' : 'away'] ?? 3;
      t.querySelectorAll('.sb-to i').forEach((dot, i) => dot.classList.toggle('used', i >= left));
      t.style.setProperty('--c1', team.primary);
      t.querySelector('.sb-abbr').textContent = team.abbr;
      t.querySelector('.sb-score').textContent = sc;
      t.classList.toggle('has-ball', poss);
    };
    set('#sb-away', away, score.away, possession === 'away');
    set('#sb-home', home, score.home, possession === 'home');
    $('.sb-q', this.hudRoot).textContent = quarter;
    $('.sb-time', this.hudRoot).textContent = clock;
    $('.sb-dd', this.hudRoot).textContent = down;
    $('.sb-spot', this.hudRoot).textContent = spot;
  }

  banner(main, sub = '', tone = 'gold', ms = 2000) {
    const b = this.els.banner;
    b.querySelector('.banner-main').textContent = main;
    b.querySelector('.banner-sub').textContent = sub;
    b.dataset.tone = tone;
    b.hidden = false;
    b.classList.remove('in');
    void b.offsetWidth;
    b.classList.add('in');
    clearTimeout(this.bannerT);
    this.bannerT = setTimeout(() => { b.hidden = true; }, ms);
  }

  flash(text) {
    const f = this.els.flash;
    f.textContent = text;
    f.hidden = false;
    f.classList.remove('in');
    void f.offsetWidth;
    f.classList.add('in');
    clearTimeout(this.flashT);
    this.flashT = setTimeout(() => { f.hidden = true; }, 1300);
  }

  toast(text) {
    const t = this.els.toast;
    if (!text) { t.hidden = true; return; }
    t.textContent = text;
    t.hidden = false;
  }

  ticker(text) {
    const t = this.els.ticker;
    if (!text) { t.hidden = true; return; }
    t.textContent = text;
    t.hidden = false;
    t.classList.remove('in');
    void t.offsetWidth;
    t.classList.add('in');
    clearTimeout(this.tickerT);
    this.tickerT = setTimeout(() => { t.hidden = true; }, 7000);
  }

  kickMeter(show, value = 0, label = '') {
    const m = this.els.meter;
    m.hidden = !show;
    if (!show) return;
    m.querySelector('.meter-label').textContent = label;
    m.querySelector('.meter-needle').style.left = `${50 + value * 48}%`;
  }

  // ------------------------------------------------------------ receiver icons
  setIcons(list) {
    this.iconList = list;
    for (const [, e] of this.iconEls) e.remove();
    this.iconEls.clear();
    for (const a of list) {
      const e = el('button', `ricon g-${a.glyph}`, `${GLYPH_SVG[a.glyph]}<span class="rkey">${a.key}</span>`);
      e.type = 'button';
      e.title = `Throw to #${a.info.num} ${a.info.last}`;
      e.addEventListener('pointerdown', (ev) => { ev.preventDefault(); this.h.onIconThrow?.(a.key, ev.shiftKey); });
      this.els.icons.appendChild(e);
      this.iconEls.set(a, e);
    }
  }

  updateIcons(project) {
    if (!this.iconList?.length) return;
    for (const [a, e] of this.iconEls) {
      const s = project(a.p.x, 2.75, a.p.z);
      if (!s || a.down) { e.style.display = 'none'; continue; }
      e.style.display = '';
      e.style.transform = `translate(${s.x}px, ${s.y}px) translate(-50%, -100%)`;
    }
  }

  // ------------------------------------------------------------ play calling
  showPlaycall({ side, team, plays, situation, onPick }) {
    const pc = this.els.playcall;
    pc.hidden = false;
    pc.style.setProperty('--c1', team.primary);
    pc.querySelector('.pc-side').textContent = side === 'offense' ? 'Offense' : 'Defense';
    pc.querySelector('.pc-sit').textContent = situation;
    const wrap = pc.querySelector('.pc-cards');
    wrap.innerHTML = '';
    this.cards = [];
    plays.forEach((p, i) => {
      const c = el('button', 'card');
      c.type = 'button';
      c.dataset.i = i;
      const art = document.createElement('canvas');
      art.width = 240; art.height = 132;
      c.appendChild(art);
      c.appendChild(el('div', 'card-meta', `<span class="card-tag">${p.tag}</span><strong>${p.name}</strong><small>${p.formation ? FORMATIONS[p.formation].name : p.blurb}</small>`));
      this.drawPlayArt(art, p, side, team);
      c.addEventListener('click', () => this.pick(i));
      wrap.appendChild(c);
      this.cards.push({ el: c, play: p });
    });
    this.onPick = onPick;
    this.focusCard(0);
  }

  hidePlaycall() {
    this.els.playcall.hidden = true;
    this.onPick = null;
  }

  focusCard(i) {
    if (!this.cards.length) return;
    this.cardIdx = (i + this.cards.length) % this.cards.length;
    this.cards.forEach((c, k) => c.el.classList.toggle('focus', k === this.cardIdx));
  }

  pick(i) {
    const c = this.cards[i];
    if (!c || !this.onPick) return;
    const cb = this.onPick;
    this.hidePlaycall();
    cb(c.play);
  }

  navigate(ctrl) {
    if (this.els.playcall.hidden || !this.cards.length) return false;
    const perRow = Math.max(1, Math.round(this.els.playcall.querySelector('.pc-cards').clientWidth / 200));
    if (ctrl.left) this.focusCard(this.cardIdx - 1);
    if (ctrl.right) this.focusCard(this.cardIdx + 1);
    if (ctrl.up) this.focusCard(this.cardIdx - perRow);
    if (ctrl.down) this.focusCard(this.cardIdx + perRow);
    if (ctrl.confirm || ctrl.snap) { this.pick(this.cardIdx); return true; }
    return true;
  }

  drawPlayArt(cv, play, side, team) {
    const ctx = cv.getContext('2d');
    const W = cv.width, H = cv.height;
    ctx.fillStyle = '#0f2a17';
    ctx.fillRect(0, 0, W, H);
    ctx.strokeStyle = 'rgba(255,255,255,0.08)';
    ctx.lineWidth = 1;
    for (let y = H - 30; y > 0; y -= 18) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }
    const losY = H - 34;
    ctx.strokeStyle = 'rgba(80,150,255,0.8)';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(0, losY); ctx.lineTo(W, losY); ctx.stroke();
    const sx = (v) => W / 2 + v * 6.8, sy = (u) => losY - u * 3.6;
    if (play.type === 'punt' || play.type === 'fg') {
      ctx.fillStyle = '#ffffff';
      ctx.font = '700 15px Archivo, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(play.type === 'punt' ? 'PUNT' : 'FIELD GOAL', W / 2, H / 2 - 6);
      ctx.font = '500 11px Archivo, sans-serif';
      ctx.fillStyle = 'rgba(255,255,255,0.65)';
      ctx.fillText(play.blurb, W / 2, H / 2 + 12);
      return;
    }
    if (side === 'defense') {
      // Zones and blitz arrows.
      const zones = {
        cover3: [[16, -13, '#3b82f6'], [18, 0, '#3b82f6'], [16, 13, '#3b82f6'], [6, -11, '#facc15'], [6, 11, '#facc15'], [7, -3, '#a855f7'], [7, 3, '#a855f7']],
        cover2: [[18, -10, '#3b82f6'], [18, 10, '#3b82f6'], [4, -13, '#38bdf8'], [4, 13, '#38bdf8'], [13, 0, '#3b82f6'], [7, -5, '#a855f7'], [7, 5, '#a855f7']],
        cover4: [[16, -14, '#3b82f6'], [16, -5, '#3b82f6'], [16, 5, '#3b82f6'], [16, 14, '#3b82f6'], [5, 10, '#facc15'], [7, 2, '#a855f7'], [6, -9, '#facc15']],
        cover1: [[18, 0, '#3b82f6']],
        cover0: [],
      }[play.coverage] || [];
      for (const [u, v, c] of zones) {
        ctx.fillStyle = c + '55';
        ctx.strokeStyle = c;
        ctx.beginPath();
        ctx.ellipse(sx(v), sy(u), 26, 13, 0, 0, Math.PI * 2);
        ctx.fill(); ctx.stroke();
      }
      if (play.coverage === 'cover1' || play.coverage === 'cover0') {
        ctx.strokeStyle = 'rgba(255,255,255,0.7)';
        ctx.setLineDash([4, 4]);
        for (const v of [-12, -6, 6, 12]) { ctx.beginPath(); ctx.moveTo(sx(v), sy(5)); ctx.lineTo(sx(v), sy(1)); ctx.stroke(); }
        ctx.setLineDash([]);
      }
      ctx.fillStyle = '#ffffff';
      for (const v of [-3.7, -1, 1.1, 3.8]) this.drawX(ctx, sx(v), sy(1.2));
      ctx.strokeStyle = '#ff5d5d';
      ctx.lineWidth = 2.5;
      for (const slot of play.blitz) {
        const v = slot === 'WILL' ? -3 : slot === 'MIKE' ? 1 : 6;
        this.arrow(ctx, sx(v), sy(5), sx(v * 0.3), sy(-2));
      }
      return;
    }
    const f = FORMATIONS[play.formation];
    const spots = { LT: [-0.75, -2.7], LG: [-0.75, -1.35], C: [-0.55, 0], RG: [-0.75, 1.35], RT: [-0.75, 2.7], QB: f.qb, ...f.spots };
    // Routes.
    for (const [slot, rname] of Object.entries(play.routes)) {
      const s = spots[slot];
      if (!s) continue;
      const r = routeFor(rname);
      ctx.lineWidth = 2.2;
      ctx.lineJoin = 'round';
      if (!r) {
        ctx.strokeStyle = 'rgba(255,255,255,0.55)';
        ctx.beginPath(); ctx.moveTo(sx(s[1]), sy(s[0])); ctx.lineTo(sx(s[1]), sy(s[0] + 1.6)); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(sx(s[1]) - 5, sy(s[0] + 1.6)); ctx.lineTo(sx(s[1]) + 5, sy(s[0] + 1.6)); ctx.stroke();
        continue;
      }
      const side = s[1] === 0 ? 1 : Math.sign(s[1]);
      ctx.strokeStyle = { X: '#4ade80', Z: '#f87171', SL: '#f472b6', SL2: '#60a5fa', TE: '#60a5fa', RB: '#cbd5e1', FB: '#f472b6' }[slot] || '#ffd21a';
      ctx.beginPath();
      ctx.moveTo(sx(s[1]), sy(s[0]));
      let px = sx(s[1]), py = sy(s[0]), qx = px, qy = py;
      for (const [du, dout] of r) {
        const u = Math.min(du, 26);
        qx = px; qy = py;
        px = sx(s[1] + side * dout); py = sy(u);
        ctx.lineTo(Math.max(4, Math.min(W - 4, px)), Math.max(4, py));
      }
      ctx.stroke();
      this.arrowHead(ctx, qx, qy, Math.max(4, Math.min(W - 4, px)), Math.max(4, py), ctx.strokeStyle);
    }
    if (play.type === 'run') {
      const rb = spots.RB;
      ctx.strokeStyle = '#ffd21a';
      ctx.lineWidth = 3;
      this.arrow(ctx, sx(rb[1]), sy(rb[0]), sx(play.runTo), sy(4));
    }
    // Players.
    for (const [slot, s] of Object.entries(spots)) {
      ctx.beginPath();
      ctx.arc(sx(s[1]), sy(s[0]), 4.6, 0, Math.PI * 2);
      ctx.fillStyle = slot === 'QB' ? '#ffd21a' : '#ffffff';
      ctx.fill();
    }
  }

  drawX(ctx, x, y) {
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x - 4, y - 4); ctx.lineTo(x + 4, y + 4);
    ctx.moveTo(x + 4, y - 4); ctx.lineTo(x - 4, y + 4);
    ctx.stroke();
  }

  arrow(ctx, x0, y0, x1, y1) {
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    this.arrowHead(ctx, x0, y0, x1, y1, ctx.strokeStyle);
  }

  arrowHead(ctx, x0, y0, x1, y1, color) {
    const a = Math.atan2(y1 - y0, x1 - x0);
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(x1 + Math.cos(a) * 3, y1 + Math.sin(a) * 3);
    ctx.lineTo(x1 + Math.cos(a + 2.5) * 7, y1 + Math.sin(a + 2.5) * 7);
    ctx.lineTo(x1 + Math.cos(a - 2.5) * 7, y1 + Math.sin(a - 2.5) * 7);
    ctx.closePath();
    ctx.fill();
  }

  // ------------------------------------------------------------ pause / stats / final
  buildPause() {
    const p = el('div', 'modal');
    p.id = 'pause';
    p.hidden = true;
    p.innerHTML = `<div class="modal-card"><h2>Timeout</h2>
      <button type="button" class="btn-primary" data-a="resume">Resume</button>
      <button type="button" class="btn-ghost" data-a="controls">Controls</button>
      <button type="button" class="btn-ghost" data-a="mute">Sound on / off</button>
      <button type="button" class="btn-ghost" data-a="quit">Quit to title</button></div>`;
    p.addEventListener('click', (e) => {
      const a = e.target.closest('button')?.dataset.a;
      if (!a) return;
      if (a === 'resume') this.h.onResume?.();
      if (a === 'controls') this.toggleHelp();
      if (a === 'mute') this.h.onMute?.();
      if (a === 'quit') this.h.onQuit?.();
    });
    this.root.appendChild(p);
    this.pauseEl = p;
  }

  setPaused(on) { this.pauseEl.hidden = !on; }
  toggleHelp() { this.els.help.hidden = !this.els.help.hidden; }

  statsTable(stats, teams) {
    const rows = [
      ['Total yards', (s) => s.passYds + s.rushYds],
      ['Passing', (s) => `${s.comp}/${s.att} · ${s.passYds}`],
      ['Rushing', (s) => s.rushYds],
      ['First downs', (s) => s.firstDowns],
      ['Touchdowns', (s) => s.td],
      ['Turnovers', (s) => s.int],
      ['Sacks', (s) => s.sacks],
    ];
    return `<table class="stats"><thead><tr><th></th><th style="--c1:${teams.away.primary}">${teams.away.abbr}</th><th style="--c1:${teams.home.primary}">${teams.home.abbr}</th></tr></thead>
      <tbody>${rows.map(([n, f]) => `<tr><td>${n}</td><td>${f(stats.away)}</td><td>${f(stats.home)}</td></tr>`).join('')}</tbody></table>`;
  }

  showStats(stats, teams, heading) {
    this.statsEl?.remove();
    const s = el('div', 'stats-pop', `<h3>${heading}</h3>${this.statsTable(stats, teams)}`);
    this.hudRoot.appendChild(s);
    this.statsEl = s;
    setTimeout(() => s.remove(), 4400);
  }

  showFinal({ score, teams, stats, userKey, won }) {
    this.hidePlaycall();
    const f = el('div', 'modal final');
    f.innerHTML = `<div class="modal-card wide">
      <div class="final-kicker">Final</div>
      <div class="final-score">
        <div style="--c1:${teams.away.primary}"><span>${teams.away.school}</span><b>${score.away}</b></div>
        <div style="--c1:${teams.home.primary}"><span>${teams.home.school}</span><b>${score.home}</b></div>
      </div>
      <p class="final-line">${won ? `${teams[userKey].school} wins it.` : `${teams[userKey].school} comes up short.`}</p>
      ${this.statsTable(stats, teams)}
      <button type="button" class="btn-primary" data-a="again">Play again</button></div>`;
    f.addEventListener('click', (e) => { if (e.target.closest('[data-a="again"]')) this.h.onQuit?.(); });
    this.root.appendChild(f);
    this.finalEl = f;
  }

  loading(text) {
    let l = $('#loading');
    if (!text) { l?.remove(); return; }
    if (!l) { l = el('div', 'loading'); l.id = 'loading'; this.root.appendChild(l); }
    l.innerHTML = `<div class="ld-mark">Gridiron Saturday <em>26</em></div><div class="ld-text">${text}</div>`;
  }
}
