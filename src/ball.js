// The football: mesh, attachment to players, ballistic flight and the in-air
// visibility aids (bigger in flight, a faint trail and a shadow on the turf).
import * as THREE from 'three';
import { footballTexture, blobShadowTexture } from './textures.js';

const G = 10.73; // gravity in yards / s^2
const UP = new THREE.Vector3(0, 1, 0);
const FLIGHT_SCALE = 1.7; // broadcast games enlarge the ball in the air so it reads on screen
const TRAIL_POINTS = 22;

export class Football {
  constructor(scene) {
    this.scene = scene;
    const geo = new THREE.SphereGeometry(1, 32, 20);
    // Prolate spheroid: pointed tips along local y.
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const y = pos.getY(i);
      const r = Math.pow(1 - y * y, 0.62) / Math.sqrt(Math.max(1e-4, 1 - y * y));
      pos.setX(i, pos.getX(i) * (y * y < 1 ? r : 0));
      pos.setZ(i, pos.getZ(i) * (y * y < 1 ? r : 0));
    }
    geo.computeVertexNormals();
    const k = 1.3; // a touch larger than life so it reads on screen
    geo.scale(0.093 * k, 0.153 * k, 0.093 * k);
    this.mesh = new THREE.Mesh(geo, new THREE.MeshPhysicalMaterial({
      map: footballTexture(), roughness: 0.55, clearcoat: 0.35, clearcoatRoughness: 0.45,
      // A little self-light keeps the leather from going black against dark stands.
      emissive: '#5a2a12', emissiveIntensity: 0.35,
    }));
    this.mesh.castShadow = true;
    scene.add(this.mesh);
    this.flight = null;
    this.spin = 0;
    this._q = new THREE.Quaternion();
    this._v = new THREE.Vector3();
    this.buildTrail();
    this.buildShadow();
  }

  buildTrail() {
    const n = TRAIL_POINTS;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 2 * 3), 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(n * 2 * 4), 4).setUsage(THREE.DynamicDrawUsage));
    const idx = [];
    for (let i = 0; i < n - 1; i++) {
      const a = i * 2;
      idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
    geo.setIndex(idx);
    this.trail = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
      vertexColors: true, transparent: true, depthWrite: false, side: THREE.DoubleSide, toneMapped: false,
    }));
    this.trail.frustumCulled = false;
    this.trail.renderOrder = 5;
    this.trail.visible = false;
    this.scene.add(this.trail);
    this.trailPts = [];
  }

  buildShadow() {
    const geo = new THREE.PlaneGeometry(1, 1);
    geo.rotateX(-Math.PI / 2);
    this.shadow = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
      map: blobShadowTexture(), transparent: true, depthWrite: false, toneMapped: false,
      polygonOffset: true, polygonOffsetFactor: -2,
    }));
    this.shadow.renderOrder = 2;
    this.shadow.visible = false;
    this.scene.add(this.shadow);
  }

  // Attach to an Object3D anchor (a player's hand or carry pocket).
  attach(anchor, tuck = true) {
    this.flight = null;
    anchor.add(this.mesh);
    this.mesh.position.set(0, 0, 0);
    this.mesh.rotation.set(tuck ? 1.25 : 0.3, 0, 0);
    this.mesh.scale.setScalar(0.86); // life size in a player's hands
  }

  detachTo(scene) {
    this.mesh.getWorldPosition(this._v);
    scene.add(this.mesh);
    this.mesh.position.copy(this._v);
  }

  place(x, y, z, yaw = 0) {
    if (this.mesh.parent !== this.scene) this.scene.add(this.mesh);
    this.flight = null;
    this.mesh.position.set(x, y, z);
    this.mesh.rotation.set(0, yaw, Math.PI / 2);
    this.mesh.scale.setScalar(1);
  }

  // Launch from p0 so it reaches p1 after T seconds.
  launch(p0, p1, T, kind = 'spiral') {
    this.detachTo(this.scene);
    const vx = (p1.x - p0.x) / T, vz = (p1.z - p0.z) / T;
    const vy = (p1.y - p0.y + 0.5 * G * T * T) / T;
    this.flight = { p0: p0.clone(), vx, vy, vz, T, t: 0, kind };
    this.mesh.position.copy(p0);
    this.mesh.scale.setScalar(T > 0.5 ? FLIGHT_SCALE : 1);
    // Short hops (snaps, dead balls bouncing) don't get a trail.
    this.trailOn = T > 0.5;
    this.trailPts.length = 0;
  }

  // Ball position at time t of the current flight (can extrapolate past T).
  at(t, out = new THREE.Vector3()) {
    const f = this.flight;
    return out.set(f.p0.x + f.vx * t, f.p0.y + f.vy * t - 0.5 * G * t * t, f.p0.z + f.vz * t);
  }

  get inAir() {
    return !!this.flight && this.flight.t < this.flight.T && this.mesh.parent === this.scene;
  }

  update(dt) {
    const f = this.flight;
    if (!f) return;
    f.t += dt;
    this.at(f.t, this.mesh.position);
    const vel = this._v.set(f.vx, f.vy - G * f.t, f.vz);
    if (f.kind === 'spiral') {
      this.spin += dt * 38;
      this._q.setFromUnitVectors(UP, vel.normalize());
      this.mesh.quaternion.copy(this._q);
      this.mesh.rotateY(this.spin);
    } else if (f.kind === 'tumble') {
      this.spin += dt * 11;
      const yaw = Math.atan2(f.vx, f.vz);
      this.mesh.rotation.set(this.spin, yaw, 0, 'YXZ');
    } else if (f.kind === 'flutter') {
      this.spin += dt * 3;
      this._q.setFromUnitVectors(UP, vel.normalize());
      this.mesh.quaternion.copy(this._q);
      this.mesh.rotateX(Math.sin(this.spin * 3) * 0.4);
    }
    if (this.mesh.position.y < 0.12) this.mesh.position.y = 0.12;
  }

  // Called once per rendered frame: trail ribbon facing the camera + turf shadow.
  updateEffects(dt, camera) {
    const flying = this.inAir && this.trailOn;
    const p = this.mesh.position;
    if (flying) {
      this.trailPts.push(p.clone());
      if (this.trailPts.length > TRAIL_POINTS) this.trailPts.shift();
    } else if (this.trailPts.length) {
      // Let the tail catch up and vanish once the ball is caught or lands.
      this.trailPts.splice(0, Math.max(1, Math.round(dt * 90)));
    }
    this.drawTrail(camera);
    const sh = this.shadow;
    sh.visible = this.inAir;
    if (sh.visible) {
      const h = Math.max(0, p.y);
      sh.position.set(p.x, 0.03, p.z);
      sh.scale.setScalar(0.9 + h * 0.06);
      sh.material.opacity = Math.max(0.15, 0.85 - h * 0.05);
    }
  }

  drawTrail(camera) {
    const pts = this.trailPts;
    const n = pts.length;
    this.trail.visible = n > 2;
    if (n <= 2) return;
    const posAttr = this.trail.geometry.attributes.position;
    const colAttr = this.trail.geometry.attributes.color;
    const pos = posAttr.array, col = colAttr.array;
    const dir = new THREE.Vector3(), toCam = new THREE.Vector3(), side = new THREE.Vector3();
    for (let i = 0; i < TRAIL_POINTS; i++) {
      const k = Math.min(i, n - 1);
      const a = pts[k];
      const b = pts[Math.min(k + 1, n - 1)];
      const c = pts[Math.max(k - 1, 0)];
      dir.subVectors(b, c);
      if (dir.lengthSq() < 1e-8) dir.set(1, 0, 0);
      toCam.subVectors(camera.position, a);
      side.crossVectors(dir, toCam).normalize();
      const t = k / (n - 1); // 0 at the tail, 1 at the ball
      const w = 0.03 + 0.11 * t;
      pos[i * 6] = a.x + side.x * w; pos[i * 6 + 1] = a.y + side.y * w; pos[i * 6 + 2] = a.z + side.z * w;
      pos[i * 6 + 3] = a.x - side.x * w; pos[i * 6 + 4] = a.y - side.y * w; pos[i * 6 + 5] = a.z - side.z * w;
      const alpha = i < n ? Math.pow(t, 1.8) * 0.5 : 0;
      for (const o of [0, 4]) {
        col[i * 8 + o] = 1; col[i * 8 + o + 1] = 0.96; col[i * 8 + o + 2] = 0.86; col[i * 8 + o + 3] = alpha;
      }
    }
    posAttr.needsUpdate = true;
    colAttr.needsUpdate = true;
  }
}

export const GRAVITY = G;
