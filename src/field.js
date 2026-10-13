// Playing surface, goalposts, pylons, broadcast lines and the chain crew.
import * as THREE from 'three';
import { fieldTexture, grassDetailTextures, FIELD_TEX } from './textures.js';
import { FIELD } from './util.js';

export class Field {
  constructor(scene, homeTeam) {
    this.scene = scene;
    this.group = new THREE.Group();
    scene.add(this.group);

    const detail = grassDetailTextures();
    this.map = fieldTexture(homeTeam);
    const mat = new THREE.MeshStandardMaterial({
      map: this.map, roughness: 0.92, metalness: 0,
      normalMap: detail.normal, normalScale: new THREE.Vector2(0.55, 0.55),
    });
    // Tile the normal map independently of the painted map.
    detail.normal.repeat.set(FIELD_TEX.w / 1.6, FIELD_TEX.h / 1.6);
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uDetail = { value: detail.color };
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec2 vWorldXZ;')
        .replace('#include <project_vertex>', '#include <project_vertex>\nvWorldXZ = (modelMatrix * vec4(transformed, 1.0)).xz;');
      shader.fragmentShader = shader.fragmentShader
        .replace('#include <common>', '#include <common>\nuniform sampler2D uDetail;\nvarying vec2 vWorldXZ;')
        .replace('#include <map_fragment>', `#include <map_fragment>
          vec3 dA = texture2D(uDetail, vWorldXZ * 0.62).rgb * 2.0;
          vec3 dB = texture2D(uDetail, vWorldXZ * 0.083 + 0.37).rgb * 2.0;
          diffuseColor.rgb *= mix(vec3(1.0), dA, 0.55) * mix(vec3(1.0), dB, 0.35);`);
    };
    const geo = new THREE.PlaneGeometry(FIELD_TEX.w, FIELD_TEX.h, 1, 1);
    geo.rotateX(-Math.PI / 2);
    this.surface = new THREE.Mesh(geo, mat);
    this.surface.receiveShadow = true;
    this.group.add(this.surface);

    // Surround: running track-coloured apron out to the stands.
    const apronMat = new THREE.MeshStandardMaterial({ color: '#2f5a24', roughness: 0.95 });
    const apron = new THREE.Mesh(new THREE.PlaneGeometry(220, 160), apronMat);
    apron.rotation.x = -Math.PI / 2;
    apron.position.y = -0.02;
    apron.receiveShadow = true;
    this.group.add(apron);

    this.buildGoalposts(homeTeam);
    this.buildPylons();
    this.buildLines();
    this.buildChains();
  }

  buildGoalposts(team) {
    const yellow = new THREE.MeshStandardMaterial({ color: '#f2c81e', roughness: 0.35, metalness: 0.1 });
    const pad = new THREE.MeshStandardMaterial({ color: team.primary, roughness: 0.7 });
    const flagMat = new THREE.MeshStandardMaterial({ color: '#e04018', roughness: 0.8, side: THREE.DoubleSide });
    const crossY = 10 / 3; // 10 ft
    const halfW = 18.5 / 6; // 18'6" between uprights
    const upH = 10; // uprights 30 ft above the bar
    for (const s of [-1, 1]) {
      const g = new THREE.Group();
      const x = s * FIELD.halfLength;
      // Gooseneck: base behind the end line curving forward to the crossbar.
      const curve = new THREE.CatmullRomCurve3([
        new THREE.Vector3(s * 2.2, 0, 0), new THREE.Vector3(s * 2.2, crossY * 0.65, 0),
        new THREE.Vector3(s * 1.4, crossY * 0.95, 0), new THREE.Vector3(0, crossY, 0),
      ]);
      const neck = new THREE.Mesh(new THREE.TubeGeometry(curve, 24, 0.12, 12), yellow);
      neck.castShadow = true;
      g.add(neck);
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 2.2, 16), pad);
      base.position.set(s * 2.2, 1.1, 0);
      base.castShadow = true;
      g.add(base);
      const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, halfW * 2, 12), yellow);
      bar.rotation.x = Math.PI / 2;
      bar.position.y = crossY;
      bar.castShadow = true;
      g.add(bar);
      for (const zs of [-1, 1]) {
        const up = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.065, upH, 10), yellow);
        up.position.set(0, crossY + upH / 2, zs * halfW);
        up.castShadow = true;
        g.add(up);
        const flag = new THREE.Mesh(new THREE.PlaneGeometry(0.15, 1.3), flagMat);
        flag.position.set(0, crossY + upH + 0.55, zs * halfW + 0.07);
        g.add(flag);
      }
      g.position.x = x;
      this.group.add(g);
    }
    this.goalpost = { crossY, halfW, top: crossY + upH };
  }

  buildPylons() {
    const mat = new THREE.MeshStandardMaterial({ color: '#ff6a13', roughness: 0.6, emissive: '#3a1000' });
    const geo = new THREE.BoxGeometry(0.11, 0.5, 0.11);
    const hw = FIELD.halfWidth;
    for (const x of [-60, -50, 50, 60]) {
      for (const z of [-hw, hw]) {
        const m = new THREE.Mesh(geo, mat);
        m.position.set(x + (Math.abs(x) === 50 ? 0 : 0), 0.25, z + Math.sign(z) * 0.06);
        m.castShadow = true;
        this.group.add(m);
      }
    }
  }

  // Broadcast-style line of scrimmage (blue) and first-down line (yellow), drawn "under" players.
  buildLines() {
    const mk = (color) => {
      const m = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, depthWrite: false, toneMapped: false });
      m.polygonOffset = true; m.polygonOffsetFactor = -2; m.polygonOffsetUnits = -2;
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(0.28, FIELD.halfWidth * 2), m);
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.y = 0.012;
      mesh.renderOrder = 2;
      this.group.add(mesh);
      return mesh;
    };
    this.losLine = mk('#2f7bff');
    this.fdLine = mk('#ffd21a');
  }

  buildChains() {
    const orange = new THREE.MeshStandardMaterial({ color: '#ff7b1a', roughness: 0.5 });
    const black = new THREE.MeshStandardMaterial({ color: '#111', roughness: 0.6 });
    const pole = new THREE.CylinderGeometry(0.035, 0.035, 2.6, 8);
    const flapGeo = new THREE.BoxGeometry(0.06, 0.5, 0.5);
    const z = -(FIELD.halfWidth + 3.2);
    this.chainA = new THREE.Group();
    this.chainB = new THREE.Group();
    this.downBox = new THREE.Group();
    for (const g of [this.chainA, this.chainB, this.downBox]) {
      const p = new THREE.Mesh(pole, black);
      p.position.y = 1.3;
      p.castShadow = true;
      g.add(p);
      const flap = new THREE.Mesh(flapGeo, orange);
      flap.position.y = 2.6;
      flap.castShadow = true;
      g.add(flap);
      g.position.z = z;
      this.group.add(g);
    }
    // Down number on the box.
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    this.downCanvas = c;
    this.downTex = new THREE.CanvasTexture(c);
    this.downTex.colorSpace = THREE.SRGBColorSpace;
    const card = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.5), new THREE.MeshBasicMaterial({ map: this.downTex }));
    card.position.set(0, 2.6, 0.27);
    this.downBox.add(card);
    const card2 = card.clone();
    card2.rotation.y = Math.PI;
    card2.position.z = -0.27;
    this.downBox.add(card2);
    const chainGeo = new THREE.CylinderGeometry(0.012, 0.012, 10, 4);
    chainGeo.rotateZ(Math.PI / 2);
    this.chainLink = new THREE.Mesh(chainGeo, new THREE.MeshStandardMaterial({ color: '#555', metalness: 0.8, roughness: 0.4 }));
    this.chainLink.position.set(0, 0.3, z);
    this.group.add(this.chainLink);
  }

  setMarkers({ los, firstDown, down, showFirst, visible }) {
    this.losLine.visible = visible;
    this.fdLine.visible = visible && showFirst;
    this.losLine.position.x = los;
    this.fdLine.position.x = firstDown;
    this.chainA.position.x = firstDown - (firstDown > los ? 10 : -10);
    this.chainB.position.x = firstDown;
    this.chainA.visible = this.chainB.visible = this.chainLink.visible = showFirst;
    this.chainLink.position.x = (this.chainA.position.x + firstDown) / 2;
    this.downBox.position.x = los;
    const ctx = this.downCanvas.getContext('2d');
    ctx.fillStyle = '#ff7b1a';
    ctx.fillRect(0, 0, 64, 64);
    ctx.fillStyle = '#111';
    ctx.font = 'bold 50px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(down || 1), 32, 35);
    this.downTex.needsUpdate = true;
  }
}
