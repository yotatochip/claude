// Broadcast-style camera director.
import * as THREE from 'three';
import { damp, clamp, FIELD } from './util.js';

export class CameraDirector {
  constructor(camera) {
    this.camera = camera;
    this.pos = new THREE.Vector3(0, 30, 60);
    this.look = new THREE.Vector3();
    this.mode = 'menu';
    this.t = 0;
    this.shake = 0;
    this.fov = 48;
    this._v = new THREE.Vector3();
  }

  cut() { this.snapNext = true; }

  update(dt, ctx) {
    this.t += dt;
    const desiredPos = new THREE.Vector3();
    const desiredLook = new THREE.Vector3();
    let posRate = 3.2, lookRate = 5.5;
    let fov = 48;
    const { mode } = ctx;
    if (mode === 'menu') {
      // Slow sweep across the bowl, low over the turf like a broadcast open.
      const a = this.t * 0.045;
      desiredPos.set(Math.cos(a) * 48, 9 + Math.sin(this.t * 0.07) * 3, Math.sin(a) * 30);
      desiredLook.set(Math.cos(a + 0.9) * 8, 4, Math.sin(a + 0.9) * 4);
      posRate = 1.5; lookRate = 1.5;
      fov = 42;
    } else if (mode === 'hero') {
      // Close orbit around a player, like the cover art.
      const p = ctx.focus;
      const a = -0.55 + Math.sin(this.t * 0.12) * 0.3;
      desiredPos.set(p.x + Math.cos(a) * 4.4, 0.75, p.z + Math.sin(a) * 4.4);
      desiredLook.set(p.x - 0.25, 1.35, p.z - 0.6);
      fov = 36;
      posRate = 2; lookRate = 3;
    } else if (mode === 'broadcast' && ctx.air) {
      // Pass in the air: ride behind the ball, tilt up with its arc and keep the
      // receiver's landing spot in frame.
      const f = ctx.focus, vd = ctx.viewDir, y = ctx.ballY || 0;
      const tgt = ctx.target || f;
      desiredPos.set(f.x - vd * 12.5, 5.2 + y * 0.45, f.z * 0.6);
      desiredLook.set(f.x + (tgt.x - f.x) * 0.45 + vd * 3, 0.6 + y * 0.6, f.z + (tgt.z - f.z) * 0.45);
      desiredPos.x = clamp(desiredPos.x, -70, 70);
      posRate = 5.5; lookRate = 9;
      fov = 54;
    } else if (mode === 'broadcast') {
      const f = ctx.focus;
      const vd = ctx.viewDir;
      const air = ctx.air;
      const dist = air ? 15.5 : ctx.live ? 11.5 : 12.5;
      const height = air ? 8.2 : ctx.live ? 5.2 : 5.8;
      const ahead = air ? 12 : ctx.live ? 7 : 9;
      const zPull = f.z * 0.55;
      desiredPos.set(f.x - vd * dist, height, zPull);
      desiredLook.set(f.x + vd * ahead, 0.4, f.z * 0.85);
      // Keep the camera inside the stadium bowl.
      desiredPos.x = clamp(desiredPos.x, -70, 70);
      posRate = ctx.live ? 3.8 : 2.6;
      lookRate = ctx.live ? 6 : 4;
      fov = 50;
    } else if (mode === 'kick') {
      const b = ctx.ball;
      const kd = ctx.viewDir;
      desiredPos.set(b.x - kd * 16, Math.max(6, b.y * 0.6 + 5), b.z * 0.6);
      desiredLook.set(b.x + kd * 10, Math.max(1, b.y * 0.8), b.z);
      posRate = 3; lookRate = 6;
      fov = 52;
    } else if (mode === 'goalpost') {
      // Behind the kicker looking at the uprights.
      const b = ctx.ball, kd = ctx.viewDir;
      desiredPos.set(ctx.kickSpot.x - kd * 9, 3.2, ctx.kickSpot.z * 0.5);
      desiredLook.set(b.x + kd * 6, Math.max(2.5, b.y), b.z * 0.6);
      posRate = 2.5; lookRate = 5;
      fov = 46;
    } else if (mode === 'celebrate') {
      const p = ctx.focus;
      const a = this.t * 0.35 + (ctx.angle || 0);
      desiredPos.set(p.x + Math.cos(a) * 6, 1.9, p.z + Math.sin(a) * 6);
      desiredLook.set(p.x, 1.4, p.z);
      posRate = 2.2; lookRate = 4;
      fov = 38;
    } else if (mode === 'sideline') {
      const f = ctx.focus;
      desiredPos.set(f.x * 0.85, 26, -(FIELD.halfWidth + 34));
      desiredLook.set(f.x, 0, f.z * 0.3);
      posRate = 1.6; lookRate = 2.2;
      fov = 40;
    }
    if (this.snapNext) {
      this.pos.copy(desiredPos);
      this.look.copy(desiredLook);
      this.snapNext = false;
    } else {
      this.pos.x = damp(this.pos.x, desiredPos.x, posRate, dt);
      this.pos.y = damp(this.pos.y, desiredPos.y, posRate, dt);
      this.pos.z = damp(this.pos.z, desiredPos.z, posRate, dt);
      this.look.x = damp(this.look.x, desiredLook.x, lookRate, dt);
      this.look.y = damp(this.look.y, desiredLook.y, lookRate, dt);
      this.look.z = damp(this.look.z, desiredLook.z, lookRate, dt);
    }
    this.fov = damp(this.fov, fov, 3, dt);
    this.shake = Math.max(0, this.shake - dt * 2.5);
    const s = this.shake * this.shake * 0.12;
    // A camera operator never holds perfectly still: slow, tiny drift.
    const sway = mode === 'broadcast' || mode === 'kick' || mode === 'goalpost' ? 1 : 0.4;
    const t = this.t;
    const dx = (Math.sin(t * 0.73) + Math.sin(t * 1.91) * 0.5) * 0.04 * sway;
    const dy = (Math.sin(t * 0.61 + 1.3) + Math.sin(t * 2.3) * 0.4) * 0.03 * sway;
    this.camera.position.set(
      this.pos.x + (Math.random() - 0.5) * s + dx,
      this.pos.y + (Math.random() - 0.5) * s + dy,
      this.pos.z + (Math.random() - 0.5) * s,
    );
    this._v.copy(this.look);
    this._v.y += Math.sin(t * 0.83 + 0.4) * 0.05 * sway;
    this.camera.lookAt(this._v);
    if (Math.abs(this.camera.fov - this.fov) > 0.01) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
    }
  }

  bump(amount) { this.shake = Math.min(1, this.shake + amount); }

  // World direction (x,z) for the stick: up = camera forward on the ground.
  stickToWorld(sx, sy) {
    const f = this._v.set(this.look.x - this.pos.x, 0, this.look.z - this.pos.z).normalize();
    const rx = -f.z, rz = f.x; // right of forward
    return { x: f.x * sy + rx * sx, z: f.z * sy + rz * sx };
  }
}
