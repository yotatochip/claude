// Keyboard, gamepad and touch input folded into one control state per frame.
const GLYPH_BUTTON = { cross: 0, circle: 1, square: 2, tri: 3, r1: 5 };

export class Input {
  constructor() {
    this.keys = new Set();
    this.edges = new Set();
    this.throwHold = null; // { key, t, glyph }
    this.touch = { x: 0, y: 0, active: false, buttons: new Set(), edges: new Set() };
    this.prevPad = [];
    this.lastDevice = 'keyboard';
    window.addEventListener('keydown', (e) => {
      if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT')) return;
      if (['Space', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      if (!this.keys.has(e.code)) this.edges.add(e.code);
      this.keys.add(e.code);
      this.lastDevice = 'keyboard';
    });
    window.addEventListener('keyup', (e) => {
      this.keys.delete(e.code);
      this.edges.add('up:' + e.code);
    });
    window.addEventListener('blur', () => this.keys.clear());
  }

  pressed(code) { return this.edges.has(code); }

  // Called once per frame. stickToWorld converts screen stick to field direction.
  poll(dt, stickToWorld) {
    const k = this.keys;
    let sx = 0, sy = 0;
    if (k.has('KeyA') || k.has('ArrowLeft')) sx -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) sx += 1;
    if (k.has('KeyW') || k.has('ArrowUp')) sy += 1;
    if (k.has('KeyS') || k.has('ArrowDown')) sy -= 1;
    let sprint = k.has('ShiftLeft') || k.has('ShiftRight');
    const ctrl = {
      snap: this.pressed('Space'), dive: this.pressed('Space'), juke: this.pressed('KeyE'), stiff: this.pressed('KeyF'),
      switch: this.pressed('Tab') || this.pressed('KeyQ'), pause: this.pressed('Escape') || this.pressed('KeyP'),
      mute: this.pressed('KeyM'), help: this.pressed('KeyH'), timeout: this.pressed('KeyT'),
      up: this.pressed('ArrowUp') || this.pressed('KeyW'), down: this.pressed('ArrowDown') || this.pressed('KeyS'),
      left: this.pressed('ArrowLeft') || this.pressed('KeyA'), right: this.pressed('ArrowRight') || this.pressed('KeyD'),
      confirm: this.pressed('Enter') || this.pressed('NumpadEnter'),
      throwKey: 0, throwGlyph: null, throwLob: false,
    };
    // Throw keys: a tap floats a touch pass, holding fires a bullet.
    for (let i = 1; i <= 5; i++) {
      const code = 'Digit' + i;
      if (this.pressed(code)) this.throwHold = { key: i, t: 0 };
      if (this.throwHold?.key === i && this.pressed('up:' + code)) {
        ctrl.throwKey = i; ctrl.throwLob = true; this.throwHold = null;
      }
    }

    // Gamepad.
    let pads = [];
    try { pads = navigator.getGamepads ? navigator.getGamepads() : []; } catch { pads = []; } // blocked in some embeds
    const pad = pads && Array.from(pads).find((p) => p && p.connected);
    if (pad) {
      const b = pad.buttons.map((x) => x.pressed || x.value > 0.5);
      const prev = this.prevPad;
      const edge = (i) => b[i] && !prev[i];
      const ax = pad.axes[0] || 0, ay = pad.axes[1] || 0;
      if (Math.hypot(ax, ay) > 0.18) { sx = ax; sy = -ay; this.lastDevice = 'pad'; }
      if (b[12]) sy = 1; if (b[13]) sy = -1; if (b[14]) sx = -1; if (b[15]) sx = 1;
      if (b[7] || b[6]) sprint = true;
      if (edge(0)) { ctrl.snap = true; ctrl.dive = true; ctrl.confirm = true; this.lastDevice = 'pad'; }
      if (edge(1)) { ctrl.switch = true; ctrl.juke = true; }
      if (edge(2)) ctrl.stiff = true;
      if (edge(9)) ctrl.pause = true;
      if (edge(8)) ctrl.timeout = true;
      if (edge(12)) ctrl.up = true;
      if (edge(13)) ctrl.down = true;
      if (edge(14)) ctrl.left = true;
      if (edge(15)) ctrl.right = true;
      for (const [glyph, bi] of Object.entries(GLYPH_BUTTON)) {
        if (edge(bi)) this.throwHold = { glyph, t: 0 };
        if (this.throwHold?.glyph === glyph && !b[bi] && prev[bi]) {
          ctrl.throwGlyph = glyph; ctrl.throwLob = true; this.throwHold = null;
        }
      }
      this.prevPad = b;
    }

    // Touch.
    const t = this.touch;
    if (t.active) { sx = t.x; sy = t.y; }
    if (t.buttons.has('sprint')) sprint = true;
    if (t.edges.has('a')) { ctrl.snap = true; ctrl.dive = true; }
    if (t.edges.has('juke')) ctrl.juke = true;
    if (t.edges.has('switch')) ctrl.switch = true;
    if (t.edges.has('stiff')) ctrl.stiff = true;
    t.edges.clear();

    if (this.throwHold) {
      this.throwHold.t += dt;
      if (this.throwHold.t > 0.16) {
        if (this.throwHold.key) ctrl.throwKey = this.throwHold.key;
        else ctrl.throwGlyph = this.throwHold.glyph;
        ctrl.throwLob = false;
        this.throwHold = null;
      }
    }

    const mag = Math.min(1, Math.hypot(sx, sy));
    const n = Math.hypot(sx, sy) || 1;
    const w = stickToWorld ? stickToWorld(sx / n * mag, sy / n * mag) : { x: 0, z: 0 };
    ctrl.move = mag > 0.05 ? w : { x: 0, z: 0 };
    ctrl.sprint = sprint;
    ctrl.stick = { x: sx, y: sy };
    this.edges.clear();
    return ctrl;
  }

  // Programmatic throw (clicking/tapping a receiver icon).
  queueThrow(key, lob) { this.queued = { key, lob }; }
  consumeQueued(ctrl) {
    if (this.queued) { ctrl.throwKey = this.queued.key; ctrl.throwLob = this.queued.lob; this.queued = null; }
  }
}
