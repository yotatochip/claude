// Game flow: possession, downs, clock, scoring, special teams and play calling.
import { OFF_PLAYS, DEF_PLAYS, FORMATIONS, buildRoster, shortName } from './data.js';
import { Athlete } from './sim.js';
import { PlayerModel } from './player-model.js';
import { clamp, rand, chance, gaussian, weightedPick, FIELD, yardLineLabel } from './util.js';

const PUNT = { id: 'punt', name: 'Punt', type: 'punt', tag: 'Special Teams', blurb: 'Flip the field.' };
const FG = { id: 'fg', name: 'Field Goal', type: 'fg', tag: 'Special Teams', blurb: 'Points on the board.' };

const DIFFICULTY = {
  rookie: { cpu: 0.9, user: 1.08, userAcc: 0.7, cpuAcc: 1.35, userCarrier: 0.8, userTackle: 1.15 },
  varsity: { cpu: 0.97, user: 1.03, userAcc: 0.85, cpuAcc: 1.15, userCarrier: 0.9, userTackle: 1.06 },
  allamerican: { cpu: 1.02, user: 1.0, userAcc: 1.0, cpuAcc: 1.0, userCarrier: 1.0, userTackle: 1.0 },
  heisman: { cpu: 1.07, user: 0.97, userAcc: 1.15, cpuAcc: 0.85, userCarrier: 1.1, userTackle: 0.92 },
};

const ORD = ['', '1st', '2nd', '3rd', '4th'];

export class Game {
  constructor({ sim, field, stadium, ball, ui, audio, settings, home, away, userKey }) {
    Object.assign(this, { sim, field, stadium, ball, ui, audio, settings, userKey });
    this.teams = { home, away };
    this.cpuKey = userKey === 'home' ? 'away' : 'home';
    this.score = { home: 0, away: 0 };
    this.quarter = 1;
    this.qLen = settings.quarterMinutes * 60;
    this.clock = this.qLen;
    this.runoff = settings.quarterMinutes * 1.8 + 4;
    this.diff = DIFFICULTY[settings.difficulty] || DIFFICULTY.varsity;
    this.stats = {
      home: { passYds: 0, rushYds: 0, comp: 0, att: 0, td: 0, int: 0, sacks: 0, firstDowns: 0, plays: 0 },
      away: { passYds: 0, rushYds: 0, comp: 0, att: 0, td: 0, int: 0, sacks: 0, firstDowns: 0, plays: 0 },
    };
    this.state = 'init';
    this.timer = 0;
    this.timeouts = { home: 3, away: 3 };
    this.lastRunoff = 0;
    this.pat = null;
    this.kickoffBy = null;
    this.ot = null;
    this.drive = { plays: 0, yards: 0 };
    this.lastResultText = '';
    this.createAthletes();
    sim.diffMul = this.diff;
    sim.on((type, data) => this.onSimEvent(type, data));
  }

  createAthletes() {
    for (const key of ['home', 'away']) {
      const team = this.teams[key];
      const roster = buildRoster(team);
      const mul = key === this.userKey ? this.diff.user : this.diff.cpu;
      for (const info of Object.values(roster)) {
        const model = new PlayerModel(team, key, info);
        const a = new Athlete(info, team, key, model);
        for (const k of ['str', 'cat', 'tak', 'blk', 'awr', 'tha']) if (a.r[k] != null) a.r[k] = clamp(a.r[k] * mul, 0.2, 0.99);
        a.r.spd *= 1 + (mul - 1) * 0.35;
        this.sim.addAthlete(a);
      }
    }
  }

  // ------------------------------------------------------------ helpers
  dirFor(key) {
    const half = this.quarter <= 2 ? 1 : -1;
    return (key === 'home' ? 1 : -1) * half;
  }
  other(key) { return key === 'home' ? 'away' : 'home'; }
  get offKey() { return this.possession; }
  get defKey() { return this.other(this.possession); }
  get dir() { return this.dirFor(this.possession); }
  yardsToGoal() { return FIELD.goal - this.ballX * this.dir; }
  toGo() { return Math.max(1, Math.round((this.firstDownX - this.ballX) * this.dir)); }
  goalToGo() { return this.firstDownX * this.dir >= FIELD.goal - 0.01; }
  downText() {
    const d = ORD[this.down] || '4th';
    return `${d} & ${this.goalToGo() ? 'Goal' : this.toGo()}`;
  }
  spotText() { return yardLineLabel(this.ballX, this.dir); }
  clockText() {
    if (this.ot) return 'OT';
    const c = Math.max(0, Math.ceil(this.clock));
    return `${Math.floor(c / 60)}:${String(c % 60).padStart(2, '0')}`;
  }
  quarterText() { return this.ot ? `OT${this.ot.round > 1 ? this.ot.round : ''}` : `${ORD[this.quarter]}`; }

  setSpot(x, z, newSeries) {
    const hash = FIELD.hash;
    this.ballX = clamp(x, -49.5, 49.5);
    this.ballZ = clamp(z ?? 0, -hash, hash);
    if (newSeries) {
      this.down = 1;
      const fd = this.ballX + this.dir * 10;
      this.firstDownX = fd * this.dir >= FIELD.goal ? FIELD.goal * this.dir : fd;
    }
  }

  hud() {
    this.ui.setScore({
      home: this.teams.home, away: this.teams.away, score: this.score, quarter: this.quarterText(),
      clock: this.clockText(), down: this.state === 'kickoff' ? 'Kickoff' : this.downText(), spot: this.spotText(),
      possession: this.possession, userKey: this.userKey, timeouts: this.timeouts,
    });
    this.stadium.drawBoard({
      home: this.score.home, away: this.score.away, quarter: this.ot ? 5 : this.quarter, clock: this.clockText(),
      down: `${this.downText()}  ·  ${this.spotText()}`, possession: this.possession,
    });
  }

  // ------------------------------------------------------------ flow
  start() {
    // The user's team receives the opening kickoff.
    this.firstReceiver = this.userKey;
    this.possession = this.userKey;
    this.ballX = 0; this.ballZ = 0; this.down = 1; this.firstDownX = 10;
    this.kickoffBy = this.other(this.userKey);
    this.ui.banner(`${this.teams.away.school} at ${this.teams.home.school}`, 'Kickoff', 'gold');
    this.next();
  }

  next() {
    this.ui.hidePlaycall();
    if (this.pat) return this.startPat(this.pat);
    if (!this.ot && this.clock <= 0) return this.endQuarter();
    if (this.kickoffBy) return this.startKickoff(this.kickoffBy, this.kickFrom ?? 35);
    return this.startPlaycall();
  }

  endQuarter() {
    const q = this.quarter;
    if (q === 2) {
      this.quarter = 3;
      this.timeouts = { home: 3, away: 3 };
      this.clock = this.qLen;
      this.kickoffBy = this.firstReceiver;
      this.kickFrom = 35;
      this.possession = this.other(this.firstReceiver);
      this.setState('break', 4.5, () => this.next());
      this.ui.banner('Halftime', `${this.teams.away.abbr} ${this.score.away} · ${this.teams.home.abbr} ${this.score.home}`, 'gold', 4200);
      this.ui.showStats(this.stats, this.teams, 'Halftime');
      this.stadium.cheer(0.5);
      return;
    }
    if (q === 4) {
      if (this.score.home !== this.score.away) return this.finish();
      return this.startOvertime();
    }
    this.quarter = q + 1;
    this.clock = this.qLen;
    this.ui.banner(`End of ${ORD[q]} Quarter`, `${this.teams.away.abbr} ${this.score.away} · ${this.teams.home.abbr} ${this.score.home}`, 'gold', 2600);
    this.setState('break', 2.6, () => this.next());
  }

  startOvertime() {
    this.ot = { round: 1, first: this.userKey, idx: 0 };
    this.quarter = 5;
    this.ui.banner('Overtime', 'Each team gets the ball at the 25', 'gold', 3200);
    this.setState('break', 3.2, () => this.startOtPossession());
  }

  startOtPossession() {
    const key = this.ot.idx === 0 ? this.ot.first : this.other(this.ot.first);
    this.possession = key;
    this.kickoffBy = null;
    this.setSpot(this.dir * 25, 0, true);
    this.next();
  }

  // Called when an OT possession ends (after the PAT if any).
  otPossessionOver() {
    if (this.ot.idx === 0) {
      this.ot.idx = 1;
      this.ui.banner(`${this.teams[this.other(this.ot.first)].school} ball`, 'Overtime', 'gold', 2200);
      this.setState('break', 2.2, () => this.startOtPossession());
      return;
    }
    if (this.score.home !== this.score.away) return this.finish();
    this.ot.round++;
    this.ot.idx = 0;
    this.ot.first = this.other(this.ot.first);
    this.ui.banner(`Overtime ${this.ot.round}`, 'Still tied', 'gold', 2400);
    this.setState('break', 2.4, () => this.startOtPossession());
  }

  finish() {
    this.state = 'final';
    const won = this.score[this.userKey] > this.score[this.cpuKey];
    this.stadium.cheer(won ? 1.2 : 0.3, 8000);
    this.audio.roar(won ? 1 : 0.3);
    this.ui.showFinal({ score: this.score, teams: this.teams, stats: this.stats, userKey: this.userKey, won });
  }

  setState(s, t = 0, cb = null) {
    this.state = s;
    this.timer = t;
    this.timerCb = cb;
  }

  // ------------------------------------------------------------ play calling
  startPlaycall() {
    const offUser = this.offKey === this.userKey;
    this.state = 'playcall';
    this.sim.setHuddle(this.ballX, this.dir, this.ballZ, this.offKey);
    if (this.sim.phase !== 'post') {
      this.sim.phase = 'post';
      this.sim.postT = 3;
      this.sim.result = this.sim.result || { kind: 'none' };
    }
    // Officials spot the ball while the teams huddle up.
    this.sim.kick = null;
    this.sim.carrier = null;
    for (const a of this.sim.athletes) { a.celebrate = false; a.user = false; }
    this.ball.place(this.ballX + this.dir * 0.15, 0.12, this.ballZ, this.dir > 0 ? Math.PI / 2 : -Math.PI / 2);
    this.field.setMarkers({ los: this.ballX, firstDown: this.firstDownX, down: this.down, showFirst: !this.goalToGo(), visible: true });
    this.hud();
    const cpuDef = this.cpuDefenseCall();
    const cpuOff = this.cpuOffenseCall();
    const situation = `${this.downText()} · ${this.spotText()}`;
    const options = [...OFF_PLAYS];
    if (this.down === 4 || this.settings.alwaysSpecial) {
      if (!this.ot) options.push(PUNT);
      if (this.yardsToGoal() <= 45) options.push(FG);
    } else if (this.yardsToGoal() <= 40) options.push(FG);
    if (offUser) {
      this.ui.showPlaycall({
        side: 'offense', team: this.teams[this.userKey], plays: options, situation,
        onPick: (play) => this.callPlay(play, cpuDef),
      });
    } else {
      if (cpuOff.type === 'punt' || cpuOff.type === 'fg') {
        this.ui.toast(`${this.teams[this.cpuKey].school} sends out the ${cpuOff.type === 'punt' ? 'punt' : 'field goal'} unit`);
        this.setState('break', 1.6, () => this.callPlay(cpuOff, null));
        return;
      }
      this.ui.showPlaycall({
        side: 'defense', team: this.teams[this.userKey], plays: DEF_PLAYS, situation,
        onPick: (def) => this.callPlay(cpuOff, def),
      });
    }
  }

  cpuOffenseCall() {
    const ytg = this.yardsToGoal(), toGo = this.toGo();
    const trailing = this.score[this.offKey] < this.score[this.defKey];
    const late = this.quarter >= 4 && this.clock < 120;
    if (this.down === 4) {
      const fgDist = ytg + 17;
      const goForIt = (toGo <= 2 && ytg < 60 && chance(0.45)) || (late && trailing) || (this.ot && fgDist > 50);
      if (!goForIt) {
        if (fgDist <= 52) return FG;
        if (!this.ot) return PUNT;
      }
    }
    let passW = 0.5;
    if (toGo <= 2) passW = 0.25;
    else if (toGo >= 7) passW = 0.8;
    if (ytg <= 4) passW = 0.35;
    if (late && trailing) passW = 0.9;
    const wantPass = Math.random() < passW;
    const pool = OFF_PLAYS.filter((p) => (wantPass ? p.type !== 'run' : p.type === 'run'));
    return pool[Math.floor(Math.random() * pool.length)];
  }

  cpuDefenseCall() {
    const toGo = this.toGo();
    return weightedPick(DEF_PLAYS, (p) => {
      if (toGo <= 2) return p.tag === 'Blitz' || p.coverage === 'cover1' ? 3 : 1;
      if (toGo >= 8) return p.coverage === 'cover4' || p.coverage === 'cover3' ? 3 : p.tag === 'Blitz' ? 1.5 : 1;
      return p.tag === 'Blitz' ? 1 : 2;
    });
  }

  callPlay(play, defPlay) {
    this.ui.hidePlaycall();
    if (play.type === 'punt') return this.startPunt();
    if (play.type === 'fg') return this.startFieldGoal();
    defPlay = defPlay || this.cpuDefenseCall();
    this.currentPlay = play;
    this.currentDef = defPlay;
    this.sim.setupPlay({
      offKey: this.offKey, defKey: this.defKey, los: this.ballX, dir: this.dir, ballZ: this.ballZ,
      play, defPlay, userKey: this.userKey, firstDownX: this.firstDownX,
    });
    this.state = 'presnap';
    this.snapDelay = rand(1.0, 2.2);
    this.audio.band(false);
    const offUser = this.offKey === this.userKey;
    this.ui.toast(offUser
      ? `${play.name} · ${FORMATIONS_NAME(play)} — press Space to snap`
      : `${defPlay.name} — Tab switches players, Space dives`);
  }

  // ------------------------------------------------------------ live play
  onSimEvent(type, data) {
    const a = this.audio;
    switch (type) {
      case 'set':
        if (this.state === 'presnap') this.ui.setIcons(this.offKey === this.userKey ? this.sim.icons : []);
        break;
      case 'snap':
        a.snap();
        this.stadium.cheer(this.offKey === this.userKey ? 0.1 : 0.55, 1500);
        break;
      case 'throw': a.throwBall(); this.ui.setIcons([]); break;
      case 'handoff': this.ui.setIcons([]); break;
      case 'catch': a.catchBall(); break;
      case 'hit': a.hit(Math.min(1, (data.power || 8) / 16)); break;
      case 'broken':
        this.ui.flash('Broken tackle');
        this.stadium.cheer(0.7, 1500);
        a.roar(0.4);
        break;
      case 'move': a.whoosh(); break;
      case 'interception':
        this.ui.flash('Intercepted!');
        a.roar(0.8);
        this.stadium.cheer(1, 3000);
        break;
      case 'end': this.onPlayEnd(data); break;
      case 'kick': a.kick(); break;
      case 'kickLand': break;
      case 'kickDone': this.onKickDone(data); break;
      default: break;
    }
  }

  callTimeout() {
    const key = this.userKey;
    if (this.ot || this.timeouts[key] <= 0) return;
    if (!['playcall', 'presnap'].includes(this.state)) return;
    if (this.lastRunoff <= 0) { this.ui.toast('The clock is already stopped'); return; }
    this.timeouts[key]--;
    this.clock += this.lastRunoff;
    this.lastRunoff = 0;
    this.ui.banner(`Timeout ${this.teams[key].abbr}`, `${this.timeouts[key]} left this half`, 'muted', 1800);
    this.hud();
  }

  update(dt, ctrl) {
    if (ctrl.timeout) this.callTimeout();
    if (this.timer > 0) {
      this.timer -= dt;
      if (this.timer <= 0 && this.timerCb) { const cb = this.timerCb; this.timerCb = null; cb(); }
    }
    const offUser = this.offKey === this.userKey;
    if (this.state === 'presnap') {
      if (this.sim.phase === 'set') {
        if (offUser) {
          if (ctrl.snap) { this.snap(); ctrl.snap = false; ctrl.dive = false; }
        } else {
          this.snapDelay -= dt;
          if (this.snapDelay <= 0) this.snap();
        }
      }
      if (ctrl.switch && !offUser) {
        // Cycle through defenders pre-snap.
        const list = this.sim.def;
        const i = list.indexOf(this.sim.userAthlete);
        const next = list[(i + 1) % list.length];
        if (this.sim.userAthlete) this.sim.userAthlete.user = false;
        next.user = true;
        this.sim.userAthlete = next;
        ctrl.switch = false;
      }
    }
    if (this.state === 'live') {
      if (!this.ot) {
        this.clock = Math.max(0, this.clock - dt);
      }
      this.sim.update(dt, ctrl);
    } else if (this.state === 'kickMeter') {
      this.meterT += dt;
      const m = Math.sin(this.meterT * 2.7);
      this.ui.kickMeter(true, m, this.meterLabel);
      this.sim.update(dt, null);
      if (ctrl.snap || ctrl.dive) {
        this.ui.kickMeter(false);
        this.meterCb(m);
      }
    } else {
      this.sim.update(dt, null);
    }
    if (this.state === 'live' || this.state === 'post' || this.state === 'presnap') this.hudTick(dt);
  }

  hudTick(dt) {
    this.hudT = (this.hudT || 0) + dt;
    if (this.hudT > 0.25) { this.hudT = 0; this.hud(); }
  }

  snap() {
    this.state = 'live';
    this.ui.setIcons(this.offKey === this.userKey && this.currentPlay.type !== 'run' ? this.sim.icons : []);
    this.ui.toast(null);
    this.sim.snap();
    this.playStartX = this.ballX;
  }

  onPlayEnd(res) {
    this.state = 'post';
    this.ui.setIcons([]);
    this.audio.whistle();
    const delay = res.kind === 'td' ? 4.2 : 2.3;
    if (res.kind === 'td') {
      this.audio.roar(1);
      this.stadium.cheer(1.3, 5000);
      this.stadium.drawRibbon('TOUCHDOWN', true);
      setTimeout(() => this.stadium.drawRibbon(`${this.teams.home.school.toUpperCase()} ${this.teams.home.name.toUpperCase()}`), 5000);
    }
    this.setState('post', delay, () => this.processResult(res));
  }

  processResult(res) {
    const off = this.offKey, def = this.defKey, dir = this.dir;
    const st = this.stats[off];
    const startX = this.ballX;
    const carrier = res.carrier;
    const name = carrier ? shortName(carrier.info) : '';
    let text = '';
    let clockStops = false;
    let firstDown = false;
    let possessionOver = false;
    st.plays++;
    const gainFrom = (x) => Math.round((x - startX) * dir);

    if (res.kind === 'incomplete') {
      st.att++;
      clockStops = true;
      this.down++;
      text = res.why === 'drop' ? 'Dropped pass' : res.why === 'deflect' ? 'Pass broken up' : 'Incomplete';
      this.ui.banner('Incomplete', res.why === 'drop' ? 'Dropped' : res.why === 'deflect' ? 'Broken up' : '', 'muted', 1500);
    } else if (res.turnover) {
      // Interception return ended.
      st.att++; st.int++;
      const newOff = def;
      this.possession = newOff;
      clockStops = true;
      possessionOver = true;
      if (res.kind === 'td') {
        this.score[newOff] += 6;
        this.stats[newOff].td++;
        this.pat = newOff;
        this.kickoffBy = newOff;
        this.kickFrom = 35;
        text = `${name} pick-six!`;
        this.ui.banner('Pick Six', `${this.teams[newOff].school} scores`, 'gold', 3000);
      } else {
        let x = res.x;
        if (x * this.dirFor(newOff) <= -FIELD.goal) x = this.dirFor(newOff) * -30; // touchback to the 20
        this.setSpot(x, res.z, true);
        text = `Intercepted by ${name}`;
        this.ui.banner('Interception', `${this.teams[newOff].school} ball`, 'red', 2600);
      }
    } else {
      const gain = gainFrom(res.x);
      const passPlay = res.thrown;
      if (passPlay) {
        st.att++; st.comp++; st.passYds += gain;
      } else if (res.kind === 'sack') {
        this.stats[def].sacks++;
        st.rushYds += 0;
      } else {
        st.rushYds += gain;
      }
      if (res.kind === 'td') {
        this.score[off] += 6;
        st.td++;
        this.pat = off;
        this.kickoffBy = off;
        this.kickFrom = 35;
        possessionOver = true;
        clockStops = true;
        text = `${name} ${Math.abs(gain)}-yd ${passPlay ? 'TD catch' : 'TD run'}`;
        this.ui.banner('Touchdown', `${this.teams[off].school} · ${name}`, 'gold', 3400);
      } else if (res.x * dir <= -FIELD.goal) {
        // Safety.
        this.score[def] += 2;
        this.kickoffBy = off;
        this.kickFrom = 20;
        possessionOver = true;
        clockStops = true;
        text = 'Safety';
        this.ui.banner('Safety', `${this.teams[def].school} +2`, 'red', 2800);
      } else {
        this.setSpot(res.x, res.z, false);
        if (res.kind === 'oob') clockStops = true;
        if (this.ballX * dir >= this.firstDownX * dir - 0.01) {
          firstDown = true;
          st.firstDowns++;
          this.setSpot(this.ballX, this.ballZ, true);
        } else {
          this.down++;
        }
        const yds = gain === 0 ? 'no gain' : gain > 0 ? `${gain}-yd ${passPlay ? 'catch' : 'run'}` : `loss of ${-gain}`;
        text = res.kind === 'sack' ? `${res.tackler ? shortName(res.tackler.info) : 'Defense'} sack, loss of ${Math.max(0, -gain)}` : `${name} ${yds}`;
        if (res.kind === 'sack') this.ui.banner('Sack', `Loss of ${Math.max(0, -gain)}`, 'red', 1800);
        else if (firstDown) this.ui.banner('First Down', `${name} · ${yds}`, 'gold', 1600);
        if (gain >= 15) { this.stadium.cheer(0.9, 2500); this.audio.roar(0.6); }
      }
    }

    // Turnover on downs.
    if (!possessionOver && !firstDown && this.down > 4) {
      this.possession = def;
      this.setSpot(this.ballX, this.ballZ, true);
      text += ' · Turnover on downs';
      this.ui.banner('Turnover on Downs', `${this.teams[def].school} ball`, 'red', 2400);
      clockStops = true;
      possessionOver = true;
    }

    // Clock.
    this.lastRunoff = 0;
    if (!this.ot) {
      if (!clockStops && this.clock > 0) {
        const r = Math.min(this.clock, firstDown ? this.runoff * 0.55 : this.runoff);
        // Keep at least a second on the clock so a timeout can still save the half.
        this.lastRunoff = this.clock - r > 0 ? r : 0;
        this.clock = Math.max(0, this.clock - r);
      }
    }
    this.lastResultText = text;
    this.ui.ticker(text);
    if (this.ot && possessionOver && !this.pat) return this.otPossessionOver();
    if (this.ot && possessionOver && this.pat) this.otAfterPat = true;
    this.next();
  }

  // ------------------------------------------------------------ special teams
  startKickoff(kicker, fromOwn) {
    this.kickoffBy = null;
    this.kickFrom = 35;
    const dir = this.dirFor(kicker);
    const rec = this.other(kicker);
    this.possession = rec;
    const spotX = dir * (-FIELD.goal + fromOwn);
    this.sim.setupKick({ type: 'kickoff', kickKey: kicker, recKey: rec, spotX, dir });
    this.field.setMarkers({ los: spotX, firstDown: spotX, down: 1, showFirst: false, visible: false });
    this.kickInfo = { type: 'kickoff', kicker, rec, dir, spotX };
    this.state = 'kickoff';
    this.hud();
    this.audio.band(true);
    this.beginKick((m) => {
      const power = 1 - Math.abs(m) * 0.45;
      const k = this.sim.kicker.r;
      const dist = 52 + power * 16 + (k.kpw - 0.8) * 10 + gaussian() * 2.5;
      const landX = spotX + dir * dist;
      const landZ = clamp(gaussian() * 7, -20, 20);
      const T = 3.6 + dist * 0.012;
      const inEnd = landX * dir >= FIELD.goal;
      let kind = 'return';
      if (inEnd && chance(landX * dir > FIELD.goal + 3 ? 0.95 : 0.7)) kind = 'touchback';
      let ret = clamp(22 + gaussian() * 7, 8, 45);
      if (chance(0.05)) ret += 20;
      const endX = landX - dir * ret;
      this.sim.startKick({ land: { x: landX, z: landZ }, T, kind, endX, endZ: landZ * 0.6 + gaussian() * 4 });
      this.state = 'kicking';
    }, kicker === this.userKey ? 'Kickoff power — press Space' : null);
  }

  startPunt() {
    const off = this.offKey, dir = this.dir;
    this.sim.setupKick({ type: 'punt', kickKey: off, recKey: this.defKey, spotX: this.ballX, dir, z: this.ballZ });
    this.kickInfo = { type: 'punt', kicker: off, rec: this.defKey, dir };
    this.state = 'kickoff';
    this.field.setMarkers({ los: this.ballX, firstDown: this.firstDownX, down: this.down, showFirst: false, visible: true });
    this.beginKick((m) => {
      const p = this.sim.kicker.r;
      const power = 1 - Math.abs(m) * 0.4;
      let dist = 33 + power * 10 + (p.kpw - 0.8) * 12 + gaussian() * 3.5;
      if (chance(0.04)) dist = 24;
      const landX = this.ballX + dir * dist;
      const landZ = clamp(this.ballZ + gaussian() * 6, -22, 22);
      const T = 3.9 + gaussian() * 0.25;
      let kind = chance(0.55) ? 'fair' : 'return';
      if (landX * dir >= FIELD.goal) kind = 'touchback';
      const ret = kind === 'return' ? clamp(6 + gaussian() * 4, 0, 18) : 0;
      this.sim.startKick({ land: { x: landX, z: landZ }, T, kind, endX: landX - dir * ret, endZ: landZ + gaussian() * 3 });
      this.state = 'kicking';
    }, off === this.userKey ? 'Punt — press Space' : null);
  }

  startFieldGoal() {
    const off = this.offKey, dir = this.dir;
    this.sim.setupKick({ type: 'fg', kickKey: off, recKey: this.defKey, spotX: this.ballX, dir, z: this.ballZ });
    const dist = Math.round(this.yardsToGoal() + 17);
    this.kickInfo = { type: 'fg', kicker: off, dir, dist };
    this.state = 'kickoff';
    this.field.setMarkers({ los: this.ballX, firstDown: this.firstDownX, down: this.down, showFirst: false, visible: true });
    this.ui.toast(`${dist}-yard field goal attempt`);
    this.beginKick((m) => this.kickAtGoal(m, dist), off === this.userKey ? `${dist}-yd FG — stop the needle in the middle` : null);
  }

  startPat(team) {
    this.pat = null;
    this.possession = team;
    const dir = this.dirFor(team);
    const spotX = dir * (FIELD.goal - 3);
    this.ballX = spotX; this.ballZ = 0;
    this.sim.setupKick({ type: 'pat', kickKey: team, recKey: this.other(team), spotX, dir, z: 0 });
    this.kickInfo = { type: 'pat', kicker: team, dir, dist: 20 };
    this.state = 'kickoff';
    this.field.setMarkers({ los: spotX, firstDown: spotX, down: 1, showFirst: false, visible: false });
    this.ui.toast('Extra point');
    this.setState('kickoff', 1.4, () => { this.kickAtGoal(gaussian() * 0.12, 20); });
  }

  // m: needle offset -1..1 (0 = perfect)
  kickAtGoal(m, dist) {
    const k = this.sim.kicker.r;
    const d50 = 54 + (k.kpw - 0.85) * 20 + (k.kac - 0.85) * 10;
    let p = 1 / (1 + Math.exp((dist - d50) / 6.5));
    const userKick = this.kickInfo.kicker === this.userKey && this.kickInfo.type === 'fg';
    if (userKick) p = Math.abs(m) < 0.15 ? Math.min(0.99, p + 0.2) : p * clamp(1 - (Math.abs(m) - 0.15) * 1.25, 0.05, 1);
    if (this.kickInfo.type === 'pat') p = 0.97;
    const good = Math.random() < p;
    let kind = 'good';
    if (!good) kind = dist > 45 && chance((dist - 40) / 40) ? 'short' : (m < 0 || (!userKick && chance(0.5)) ? 'wideL' : 'wideR');
    const dir = this.kickInfo.dir;
    const h = this.sim.holder;
    const x0 = h.p.x + dir * 0.45, z0 = h.p.z, y0 = 0.32;
    const xe = dir * 60;
    const D1 = Math.abs(xe - x0);
    const halfW = 18.5 / 6;
    let outcome;
    if (kind === 'short') {
      const landX = xe - dir * 3;
      outcome = { land: { x: landX, z: z0 + gaussian() * 1.5 }, landY: 0.3, T: 2.5, kind };
    } else {
      const D2 = D1 + 9;
      const f = D1 / D2;
      const H = 4.6 + Math.random() * 3;
      const zEnd = kind === 'good' ? gaussian() * halfW * 0.35 : (kind === 'wideL' ? -1 : 1) * dir * (halfW + 0.7 + Math.random() * 1.6);
      const G = 10.73;
      const T = Math.sqrt(Math.max(0.5, (H - y0 - f * (0.3 - y0)) / (0.5 * G * f * (1 - f))));
      outcome = { land: { x: xe + dir * 9, z: z0 + (zEnd - z0) / f }, landY: 0.3, T, kind };
    }
    this.kickResult = kind;
    this.sim.startKick(outcome);
    this.state = 'kicking';
  }

  beginKick(cb, meterLabel) {
    if (meterLabel) {
      this.state = 'kickMeter';
      this.meterT = Math.random() * 3;
      this.meterLabel = meterLabel;
      this.meterCb = cb;
    } else {
      this.setState('kickoff', 1.6, () => cb(gaussian() * 0.25));
    }
  }

  onKickDone(o) {
    const info = this.kickInfo;
    if (info.type === 'kickoff' || info.type === 'punt') {
      const rec = info.rec;
      this.possession = rec;
      let x;
      if (o.kind === 'touchback') x = this.dirFor(rec) * (info.type === 'kickoff' ? -25 : -30);
      else if (o.kind === 'fair') x = o.land.x;
      else x = o.endX;
      const z = o.kind === 'return' ? o.endZ : o.land.z;
      this.setSpot(x, z, true);
      if (info.type === 'punt') {
        this.stats[info.kicker].plays++;
        this.ui.ticker(`Punt ${Math.round(Math.abs(o.land.x - (this.sim.los)))} yds · ${o.kind === 'touchback' ? 'touchback' : o.kind === 'fair' ? 'fair catch' : 'returned'}`);
      } else {
        this.ui.ticker(o.kind === 'touchback' ? 'Kickoff · touchback' : `Kickoff returned to the ${yardLineLabel(this.ballX, this.dirFor(rec)).toLowerCase()}`);
      }
      if (this.ot) return this.otPossessionOver();
      if (info.type === 'punt' && !this.ot && this.clock > 0) this.clock = Math.max(0, this.clock - 6);
      return this.next();
    }
    // Field goal / PAT.
    const good = this.kickResult === 'good';
    if (info.type === 'pat') {
      if (good) this.score[info.kicker] += 1;
      this.ui.banner(good ? 'Extra Point Good' : 'Extra Point No Good', '', good ? 'gold' : 'muted', 1600);
      if (this.ot && this.otAfterPat) { this.otAfterPat = false; this.hud(); return this.otPossessionOver(); }
      this.hud();
      return this.next();
    }
    // Field goal.
    if (good) {
      this.score[info.kicker] += 3;
      this.kickoffBy = info.kicker;
      this.kickFrom = 35;
      this.ui.banner('Field Goal Good', `${info.dist} yards`, 'gold', 2200);
      this.stadium.cheer(info.kicker === 'home' ? 1 : 0.3, 3000);
      this.audio.roar(info.kicker === 'home' ? 0.8 : 0.2);
    } else {
      const miss = this.kickResult === 'short' ? 'Short' : this.kickResult === 'wideL' ? 'Wide left' : 'Wide right';
      this.ui.banner('No Good', `${info.dist} yards · ${miss}`, 'red', 2200);
      // Defense takes over at the spot of the kick (or the 20).
      const rec = this.other(info.kicker);
      this.possession = rec;
      const kickSpot = this.ballX - info.dir * 7;
      let x = kickSpot;
      if (x * this.dirFor(rec) < -30) x = this.dirFor(rec) * -30;
      this.setSpot(x, 0, true);
    }
    if (!this.ot) this.clock = Math.max(0, this.clock - 5);
    this.hud();
    if (this.ot) return this.otPossessionOver();
    this.next();
  }
}

function FORMATIONS_NAME(play) {
  return FORMATIONS[play.formation]?.name || play.formation;
}
