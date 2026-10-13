// Renderer, post-processing and time-of-day lighting.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { Sky } from 'three/addons/objects/Sky.js';
import { setMaxAnisotropy } from './textures.js';

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uTime: { value: 0 },
    uVignette: { value: 0.32 },
    uGrain: { value: 0.035 },
    uSat: { value: 1.08 },
    uContrast: { value: 1.05 },
    uTint: { value: new THREE.Vector3(1, 1, 1) },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
  `,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse;
    uniform float uTime, uVignette, uGrain, uSat, uContrast;
    uniform vec3 uTint;
    varying vec2 vUv;
    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    void main() {
      vec2 d = vUv - 0.5;
      // Tiny lens fringe toward the edges.
      float ca = dot(d, d) * 0.004;
      vec3 col;
      col.r = texture2D(tDiffuse, vUv + d * ca).r;
      col.g = texture2D(tDiffuse, vUv).g;
      col.b = texture2D(tDiffuse, vUv - d * ca).b;
      float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
      col = mix(vec3(l), col, uSat);
      col = (col - 0.5) * uContrast + 0.5;
      col *= uTint;
      float v = smoothstep(0.95, 0.25, length(d * vec2(1.0, 1.15)));
      col *= mix(1.0 - uVignette, 1.0, v);
      col += (hash(vUv * 731.0 + uTime) - 0.5) * uGrain;
      gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
    }
  `,
};

export const QUALITY = {
  high: { pixelRatio: 2, shadow: 4096, samples: 4, bloom: true, crowd: 'high' },
  medium: { pixelRatio: 1.25, shadow: 2048, samples: 4, bloom: true, crowd: 'medium' },
  low: { pixelRatio: 1, shadow: 1024, samples: 0, bloom: false, crowd: 'low' },
};

export class Graphics {
  constructor(container, quality) {
    this.q = QUALITY[quality] || QUALITY.high;
    this.qualityName = quality;
    const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance', stencil: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, this.q.pixelRatio));
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    container.appendChild(renderer.domElement);
    this.renderer = renderer;
    setMaxAnisotropy(Math.min(16, renderer.capabilities.getMaxAnisotropy()));
    this.basePixelRatio = renderer.getPixelRatio();
    this.dynScale = 1;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(48, container.clientWidth / container.clientHeight, 0.25, 6000);
    this.container = container;

    // Lights.
    this.sun = new THREE.DirectionalLight('#fff4e6', 3);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(this.q.shadow, this.q.shadow);
    const sc = this.sun.shadow.camera;
    sc.left = -62; sc.right = 62; sc.top = 62; sc.bottom = -62;
    sc.near = 1; sc.far = 900;
    this.sun.shadow.bias = -0.00025;
    this.sun.shadow.normalBias = 0.035;
    this.sun.shadow.radius = 2.5;
    this.scene.add(this.sun, this.sun.target);
    this.fill = new THREE.DirectionalLight('#dfe8ff', 0.6);
    this.scene.add(this.fill, this.fill.target);
    this.hemi = new THREE.HemisphereLight('#bcd2ff', '#3b4a2a', 0.5);
    this.scene.add(this.hemi);

    this.sky = new Sky();
    this.sky.scale.setScalar(4500);
    this.scene.add(this.sky);
    this.nightSky = this.makeNightSky();
    this.scene.add(this.nightSky);
    this.pmrem = new THREE.PMREMGenerator(renderer);

    // Post.
    const size = renderer.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: this.q.samples });
    this.composer = new EffectComposer(renderer, rt);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(size.x / 2, size.y / 2), 0.35, 0.55, 0.92);
    this.bloom.enabled = this.q.bloom;
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());
    this.grade = new ShaderPass(GradeShader);
    this.composer.addPass(this.grade);

    this.lightDir = new THREE.Vector3(0.4, 0.8, 0.3).normalize();
    this.shadowCenter = new THREE.Vector3();
    this.frameTimes = [];
    window.addEventListener('resize', () => this.resize());
  }

  makeNightSky() {
    const g = new THREE.SphereGeometry(3000, 32, 16);
    const count = 1400;
    const pos = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      const u = Math.random() * Math.PI * 2, v = Math.acos(Math.random() * 0.9);
      pos[i * 3] = Math.sin(v) * Math.cos(u) * 2800;
      pos[i * 3 + 1] = Math.cos(v) * 2800;
      pos[i * 3 + 2] = Math.sin(v) * Math.sin(u) * 2800;
    }
    const stars = new THREE.Points(
      new THREE.BufferGeometry().setAttribute('position', new THREE.BufferAttribute(pos, 3)),
      new THREE.PointsMaterial({ color: '#cfd8ff', size: 2.2, sizeAttenuation: false, transparent: true, opacity: 0.7, depthWrite: false }),
    );
    const mat = new THREE.ShaderMaterial({
      side: THREE.BackSide, depthWrite: false,
      uniforms: { top: { value: new THREE.Color('#02040b') }, mid: { value: new THREE.Color('#0b1426') }, glow: { value: new THREE.Color('#2a2f3a') } },
      vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `uniform vec3 top; uniform vec3 mid; uniform vec3 glow; varying vec3 vP;
        void main(){ float h = vP.y; vec3 c = mix(mid, top, smoothstep(0.0, 0.6, h)); c = mix(glow, c, smoothstep(-0.05, 0.18, h)); gl_FragColor = vec4(c, 1.0); }`,
    });
    const dome = new THREE.Mesh(g, mat);
    const grp = new THREE.Group();
    grp.add(dome, stars);
    return grp;
  }

  // mode: 'day' | 'dusk' | 'night'
  setTimeOfDay(mode, stadium) {
    this.mode = mode;
    const sky = this.sky.material.uniforms;
    let sunDir;
    if (mode === 'night') {
      this.sky.visible = false;
      this.nightSky.visible = true;
      sunDir = new THREE.Vector3(0.25, 0.92, -0.3).normalize();
      this.sun.color.set('#f6f2ea');
      this.sun.intensity = 2.7;
      this.fill.color.set('#e8eeff');
      this.fill.intensity = 1.1;
      this.fill.position.set(-30, 60, 40);
      this.hemi.color.set('#334466');
      this.hemi.groundColor.set('#1a2414');
      this.hemi.intensity = 0.35;
      this.renderer.toneMappingExposure = 1.05;
      this.bloom.strength = 0.6;
      this.bloom.threshold = 0.85;
      this.scene.fog = new THREE.Fog('#0a0f1a', 250, 1600);
      this.scene.environment = this.envFromScene(this.nightEnvScene());
      this.scene.environmentIntensity = 0.55;
      this.grade.uniforms.uTint.value.set(0.98, 1.0, 1.04);
    } else {
      this.sky.visible = true;
      this.nightSky.visible = false;
      const dusk = mode === 'dusk';
      const elev = THREE.MathUtils.degToRad(dusk ? 7 : 52);
      const azim = THREE.MathUtils.degToRad(dusk ? 205 : 160);
      sunDir = new THREE.Vector3().setFromSphericalCoords(1, Math.PI / 2 - elev, azim);
      sky.turbidity.value = dusk ? 6 : 2.2;
      sky.rayleigh.value = dusk ? 2.6 : 1.6;
      sky.mieCoefficient.value = dusk ? 0.008 : 0.004;
      sky.mieDirectionalG.value = 0.82;
      sky.sunPosition.value.copy(sunDir);
      this.sun.color.set(dusk ? '#ffb27a' : '#fff4e6');
      this.sun.intensity = dusk ? 3.0 : 4.6;
      this.fill.color.set(dusk ? '#fff3e2' : '#dfe8ff');
      this.fill.intensity = dusk ? 1.8 : 0.5;
      this.fill.position.set(-20, 80, 30);
      this.hemi.color.set(dusk ? '#9fa8d8' : '#bcd2ff');
      this.hemi.groundColor.set('#3b4a2a');
      this.hemi.intensity = dusk ? 0.6 : 0.7;
      this.renderer.toneMappingExposure = dusk ? 0.72 : 0.58;
      this.bloom.strength = dusk ? 0.45 : 0.22;
      this.bloom.threshold = dusk ? 0.88 : 0.95;
      this.scene.fog = new THREE.Fog(dusk ? '#a78f86' : '#9fb4cc', 500, 2600);
      const envScene = new THREE.Scene();
      const skyCopy = new Sky();
      skyCopy.scale.setScalar(1000);
      Object.assign(skyCopy.material.uniforms.turbidity, { value: sky.turbidity.value });
      skyCopy.material.uniforms.rayleigh.value = sky.rayleigh.value;
      skyCopy.material.uniforms.mieCoefficient.value = sky.mieCoefficient.value;
      skyCopy.material.uniforms.sunPosition.value.copy(sunDir);
      envScene.add(skyCopy);
      const ground = new THREE.Mesh(new THREE.CircleGeometry(900, 16), new THREE.MeshBasicMaterial({ color: '#2d3d22' }));
      ground.rotation.x = -Math.PI / 2;
      ground.position.y = -1;
      envScene.add(ground);
      this.scene.environment = this.envFromScene(envScene);
      this.scene.environmentIntensity = dusk ? 0.75 : 0.9;
      this.grade.uniforms.uTint.value.set(dusk ? 1.04 : 1.0, 1.0, dusk ? 0.95 : 0.99);
    }
    this.lightDir.copy(sunDir);
    if (stadium) {
      const night = mode !== 'day';
      const sunLin = this.sun.color.clone().multiplyScalar(mode === 'night' ? 0.5 : mode === 'dusk' ? 0.55 : 0.78);
      const amb = mode === 'night' ? new THREE.Color(0.1, 0.11, 0.15) : mode === 'dusk' ? new THREE.Color(0.2, 0.19, 0.24) : new THREE.Color(0.26, 0.29, 0.34);
      const fogC = this.scene.fog.color.clone();
      stadium.setLighting({ night, sunDir, sunColor: sunLin, ambient: amb, fog: fogC });
    }
  }

  nightEnvScene() {
    const s = new THREE.Scene();
    const dome = new THREE.Mesh(new THREE.SphereGeometry(100, 16, 8), new THREE.MeshBasicMaterial({ color: '#0b1220', side: THREE.BackSide }));
    s.add(dome);
    const lamp = new THREE.MeshBasicMaterial({ color: new THREE.Color(12, 11.5, 10.5) });
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2;
      const m = new THREE.Mesh(new THREE.BoxGeometry(14, 5, 1), lamp);
      m.position.set(Math.cos(a) * 70, 45, Math.sin(a) * 70);
      m.lookAt(0, 0, 0);
      s.add(m);
    }
    const turf = new THREE.Mesh(new THREE.PlaneGeometry(200, 200), new THREE.MeshBasicMaterial({ color: '#1f3a18' }));
    turf.rotation.x = -Math.PI / 2;
    turf.position.y = -5;
    s.add(turf);
    return s;
  }

  envFromScene(s) {
    if (this.envRT) this.envRT.dispose();
    this.envRT = this.pmrem.fromScene(s, 0.02);
    return this.envRT.texture;
  }

  // Keep the shadow map focused on the action, snapped to texels to avoid shimmer.
  focusShadows(x, z) {
    const sun = this.sun;
    const dir = this.lightDir;
    const size = (sun.shadow.camera.right - sun.shadow.camera.left);
    const texel = size / sun.shadow.mapSize.x;
    // Light-space basis.
    const fwd = dir.clone().negate();
    const right = new THREE.Vector3().crossVectors(fwd, new THREE.Vector3(0, 1, 0)).normalize();
    const up = new THREE.Vector3().crossVectors(right, fwd).normalize();
    const c = new THREE.Vector3(x, 0, z);
    const r = Math.round(c.dot(right) / texel) * texel;
    const u = Math.round(c.dot(up) / texel) * texel;
    const f = c.dot(fwd);
    const snapped = right.multiplyScalar(r).add(up.multiplyScalar(u)).add(fwd.clone().multiplyScalar(f));
    sun.target.position.copy(snapped);
    sun.position.copy(snapped).addScaledVector(dir, 400);
    sun.target.updateMatrixWorld();
    this.fill.target.position.copy(snapped);
  }

  resize() {
    const w = this.container.clientWidth, h = this.container.clientHeight;
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setPixelRatio(this.basePixelRatio * this.dynScale);
    this.renderer.setSize(w, h);
    this.composer.setPixelRatio(this.basePixelRatio * this.dynScale);
    this.composer.setSize(w, h);
  }

  // Drop resolution a little if the frame rate sags.
  adapt(dt) {
    this.frameTimes.push(dt);
    if (this.frameTimes.length < 90) return;
    const avg = this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
    this.frameTimes.length = 0;
    let next = this.dynScale;
    if (avg > 1 / 40 && this.dynScale > 0.6) next = Math.max(0.6, this.dynScale - 0.1);
    else if (avg < 1 / 58 && this.dynScale < 1) next = Math.min(1, this.dynScale + 0.05);
    if (next !== this.dynScale) { this.dynScale = next; this.resize(); }
  }

  render(dt) {
    this.grade.uniforms.uTime.value += dt;
    this.composer.render(dt);
  }
}
