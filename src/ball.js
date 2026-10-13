// The football: mesh, attachment to players, and ballistic flight.
import * as THREE from 'three';
import { footballTexture } from './textures.js';

const G = 10.73; // gravity in yards / s^2
const UP = new THREE.Vector3(0, 1, 0);

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
      map: footballTexture(), roughness: 0.62, clearcoat: 0.25, clearcoatRoughness: 0.5,
    }));
    this.mesh.castShadow = true;
    scene.add(this.mesh);
    this.flight = null;
    this.spin = 0;
    this._q = new THREE.Quaternion();
    this._v = new THREE.Vector3();
  }

  // Attach to an Object3D anchor (a player's hand or carry pocket).
  attach(anchor, tuck = true) {
    this.flight = null;
    anchor.add(this.mesh);
    this.mesh.position.set(0, 0, 0);
    this.mesh.rotation.set(tuck ? 1.25 : 0.3, 0, 0);
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
  }

  // Launch from p0 so it reaches p1 after T seconds.
  launch(p0, p1, T, kind = 'spiral') {
    this.detachTo(this.scene);
    const vx = (p1.x - p0.x) / T, vz = (p1.z - p0.z) / T;
    const vy = (p1.y - p0.y + 0.5 * G * T * T) / T;
    this.flight = { p0: p0.clone(), vx, vy, vz, T, t: 0, kind };
    this.mesh.position.copy(p0);
  }

  // Ball position at time t of the current flight (can extrapolate past T).
  at(t, out = new THREE.Vector3()) {
    const f = this.flight;
    return out.set(f.p0.x + f.vx * t, f.p0.y + f.vy * t - 0.5 * G * t * t, f.p0.z + f.vz * t);
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
}

export const GRAVITY = G;
