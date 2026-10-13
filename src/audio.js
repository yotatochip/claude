// Synthesized stadium audio: crowd bed, roars, whistle, hits and a drumline.
export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.muted = false;
    this.level = 0.3;
  }

  start() {
    if (this.ctx) { this.ctx.resume?.(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    this.ctx = ctx;
    this.master = ctx.createGain();
    this.master.gain.value = this.muted ? 0 : 0.8;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14;
    comp.ratio.value = 4;
    this.master.connect(comp).connect(ctx.destination);
    this.noise = this.makeNoise(4);
    // Crowd bed: filtered noise layers with slow swells.
    this.crowd = ctx.createGain();
    this.crowd.gain.value = 0.25;
    this.crowd.connect(this.master);
    const bands = [[320, 0.7], [800, 0.9], [1900, 1.4], [3800, 2.5]];
    for (const [f, q] of bands) {
      const src = ctx.createBufferSource();
      src.buffer = this.noise;
      src.loop = true;
      src.playbackRate.value = 0.9 + Math.random() * 0.2;
      const bp = ctx.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = f;
      bp.Q.value = q;
      const g = ctx.createGain();
      g.gain.value = f < 1000 ? 0.9 : 0.35;
      const lfo = ctx.createOscillator();
      lfo.frequency.value = 0.08 + Math.random() * 0.15;
      const lg = ctx.createGain();
      lg.gain.value = 0.25;
      lfo.connect(lg).connect(g.gain);
      lfo.start();
      src.connect(bp).connect(g).connect(this.crowd);
      src.start(0, Math.random() * 3);
    }
    this.drumGain = ctx.createGain();
    this.drumGain.gain.value = 0;
    this.drumGain.connect(this.master);
    this.drumStep = 0;
    this.nextDrum = ctx.currentTime;
  }

  makeNoise(seconds) {
    const ctx = this.ctx;
    const buf = ctx.createBuffer(1, ctx.sampleRate * seconds, ctx.sampleRate);
    const d = buf.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < d.length; i++) {
      const w = Math.random() * 2 - 1;
      b0 = 0.99765 * b0 + w * 0.099;
      b1 = 0.963 * b1 + w * 0.2965;
      b2 = 0.57 * b2 + w * 1.0527;
      d[i] = (b0 + b1 + b2 + w * 0.1848) * 0.2;
    }
    return buf;
  }

  setMuted(m) {
    this.muted = m;
    if (this.master) this.master.gain.setTargetAtTime(m ? 0 : 0.8, this.ctx.currentTime, 0.05);
  }

  // Crowd intensity follows stadium excitement (0..1.5).
  update(excite) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.crowd.gain.setTargetAtTime(0.12 + Math.min(1.4, excite) * 0.45, t, 0.4);
    if (this.drumOn) this.scheduleDrums();
  }

  band(on) {
    if (!this.ctx) return;
    this.drumOn = on;
    this.drumGain.gain.setTargetAtTime(on ? 0.5 : 0, this.ctx.currentTime, 0.4);
  }

  scheduleDrums() {
    const ctx = this.ctx;
    const step = 60 / 132 / 2;
    // A simple cadence: bass on 1 and 3, snare rolls in between.
    const pattern = 'B.s.s.B.sss.B.s.B.s.s.Bss.ssssB.';
    while (this.nextDrum < ctx.currentTime + 0.2) {
      const c = pattern[this.drumStep % pattern.length];
      if (c === 'B') this.tone(this.nextDrum, 62, 0.22, 0.9, this.drumGain);
      if (c === 's') this.snare(this.nextDrum, 0.35);
      this.nextDrum += step;
      this.drumStep++;
    }
  }

  tone(t, freq, dur, vol, dest = this.master, type = 'sine', slide = 0.5) {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(20, freq * slide), t + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(dest);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  burst(t, dur, vol, freq, type = 'bandpass', dest = this.master, q = 1) {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    const f = ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    const g = ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f).connect(g).connect(dest);
    src.start(t, Math.random() * 2);
    src.stop(t + dur + 0.05);
  }

  snare(t, vol) {
    this.burst(t, 0.12, vol, 2400, 'highpass', this.drumGain);
    this.tone(t, 190, 0.08, vol * 0.5, this.drumGain, 'triangle');
  }

  whistle() {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime + 0.25;
    const o = ctx.createOscillator();
    o.frequency.value = 2850;
    const trill = ctx.createOscillator();
    trill.frequency.value = 28;
    const tg = ctx.createGain();
    tg.gain.value = 140;
    trill.connect(tg).connect(o.frequency);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.12, t + 0.03);
    g.gain.setValueAtTime(0.12, t + 0.42);
    g.gain.linearRampToValueAtTime(0, t + 0.5);
    o.connect(g).connect(this.master);
    o.start(t); trill.start(t);
    o.stop(t + 0.55); trill.stop(t + 0.55);
  }

  snap() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.burst(t, 0.08, 0.25, 900, 'bandpass');
  }

  hit(power = 0.6) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tone(t, 95, 0.18, 0.6 * power + 0.2, this.master, 'sine', 0.4);
    this.burst(t, 0.1, 0.5 * power + 0.15, 1400, 'bandpass', this.master, 0.8);
    this.burst(t + 0.01, 0.06, 0.3 * power, 4200, 'highpass');
  }

  kick() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tone(t, 140, 0.12, 0.7, this.master, 'sine', 0.3);
    this.burst(t, 0.05, 0.4, 1800, 'bandpass');
  }

  throwBall() {
    if (!this.ctx) return;
    this.burst(this.ctx.currentTime, 0.18, 0.08, 600, 'bandpass', this.master, 2);
  }

  catchBall() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tone(t, 230, 0.06, 0.35, this.master, 'triangle', 0.6);
    this.burst(t, 0.05, 0.2, 1200, 'bandpass');
  }

  whoosh() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.burst(t, 0.25, 0.15, 700, 'bandpass', this.master, 0.7);
  }

  roar(level = 1) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    for (const [f, v] of [[500, 0.5], [1200, 0.4], [2600, 0.25]]) {
      const src = ctx.createBufferSource();
      src.buffer = this.noise;
      const bp = ctx.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = f;
      bp.Q.value = 0.7;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(v * level, t + 0.35);
      g.gain.setTargetAtTime(0, t + 1.6 + level * 1.5, 0.9);
      src.connect(bp).connect(g).connect(this.master);
      src.start(t, Math.random() * 2);
      src.stop(t + 7);
    }
  }
}
