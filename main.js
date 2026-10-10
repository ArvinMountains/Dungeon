import * as THREE from 'three';

// All visual assets are geometry. Coordinates: +Y up, a character faces +Z,
// feet at Y=0. The same rig and world scale are used in both scenes.
const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;
const lerp = THREE.MathUtils.lerp;
const smooth = x => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
let randomSeed = 741;
function random() {
  randomSeed = (1664525 * randomSeed + 1013904223) >>> 0;
  return randomSeed / 4294967296;
}
const CLASS_DATA = {
  archer: {
    name: '精灵弓箭手', subtitle: 'WARDEN OF THE WITHERED WOODS', tags: ['远程', '敏捷', '古林守望者'],
    description: '旧日森林最后的低语者。以月光为弦，以寂静为誓，在黑暗察觉之前，箭已离弦。',
    stats: [2, 5, 3], trait: '寂静猎手', motto: '风记得每一支箭的归途。', icon: 'bow',
    accent: 0x8caf80, walkSpeed: 3.2,
  },
  warrior: {
    name: '铁匠战士', subtitle: 'THE LAST HAMMER OF THE FORGE', tags: ['近战', '坚韧', '余烬铸造者'],
    description: '王国已化为灰烬，炉火却从未熄灭。他将往日铸进战锤，以血肉之躯，守住最后一道城门。',
    stats: [5, 2, 5], trait: '不熄熔心', motto: '只要炉火尚存，便不向长夜低头。', icon: 'hammer',
    accent: 0xc09157, walkSpeed: 2.7,
  },
};
const STORAGE_KEY = 'lost-abyss-save-v1';
const freshSave = () => ({
  version: 1, selected: 'archer', gold: 80, potions: 1, hp: 74, upgrade: 0,
  quest: 'new', embers: [], trainingReward: false, trainingHits: 0, quality: 'pixel',
});
let save = freshSave(), storageAvailable = true, storageNotice = '';
function validSave(data) {
  return data?.version === 1 && ['archer', 'warrior'].includes(data.selected)
    && ['new', 'active', 'complete'].includes(data.quest)
    && ['gold', 'potions', 'hp', 'upgrade', 'trainingHits'].every(key => Number.isInteger(data[key]) && data[key] >= 0)
    && data.gold <= 100000 && data.potions <= 999 && data.hp <= 100 && data.upgrade <= 3 && data.trainingHits <= 3
    && typeof data.trainingReward === 'boolean'
    && ['pixel', 'fine'].includes(data.quality)
    && Array.isArray(data.embers) && data.embers.length <= 3
    && new Set(data.embers).size === data.embers.length && data.embers.every(id => ['ember0', 'ember1', 'ember2'].includes(id));
}
try {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw) {
    const parsed = JSON.parse(raw);
    if (!validSave(parsed)) throw new Error('Invalid save');
    save = parsed;
  }
} catch {
  try {
    const backup = JSON.parse(localStorage.getItem(`${STORAGE_KEY}-backup`));
    if (validSave(backup)) { save = backup; storageNotice = '已从本地备份恢复旅途记录。'; }
    else { storageAvailable = false; storageNotice = '本地存档不可读。本次以临时进度游玩，原存档保留。'; }
  } catch { storageAvailable = false; storageNotice = '存储不可用，本次旅途进度仅在当前页面保留。'; }
}
function persist() {
  if (!storageAvailable) return;
  try {
    const old = localStorage.getItem(STORAGE_KEY);
    if (old) {
      try { if (validSave(JSON.parse(old))) localStorage.setItem(`${STORAGE_KEY}-backup`, old); } catch { /* Preserve the last valid backup. */ }
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(save));
  } catch {
    storageAvailable = false;
    toast('本地存储已满或不可用，当前页面仍可继续游玩。');
  }
}

const state = {
  mode: 'selection', phase: 'idle', selected: save.selected, pending: null, transitionTime: 0,
  showcaseTime: 0, switchingScene: false, time: 0, yaw: .12, audio: false,
  path: [], destination: null, near: null, moving: false, walkPhase: 0, steps: 0,
  // Combat
  attacking: false, attackTime: 0, attackCooldown: 0, attackHit: false,
  lockedEnemy: null,
  // Day / night cycle (hours 0..24). 0.6 game-minutes per real-second.
  dayTime: 8, dayPaused: false, daySpeed: 1 / 100,
  // Free camera orbit around a target.
  camYaw: 0, camPitch: .55, camDist: 22, camZoom: 1,
};
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x141d18);
scene.fog = new THREE.FogExp2(0x17251e, .037);
const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(1);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.35;
$('#scene').appendChild(renderer.domElement);
renderer.domElement.tabIndex = 0;
renderer.domElement.setAttribute('aria-label', '三维游戏场景，拖动旋转视角；主城中点击地面行走');
const camera = new THREE.PerspectiveCamera(48, innerWidth / innerHeight, .1, 220);
const selectionWorld = new THREE.Group(), townWorld = new THREE.Group(), dungeonWorld = new THREE.Group();
scene.add(selectionWorld, townWorld, dungeonWorld);
townWorld.visible = false;
dungeonWorld.visible = false;

const materials = new Map();
function mat(color, options = {}) {
  const key = `${color}-${JSON.stringify(options)}`;
  if (!materials.has(key)) materials.set(key, new THREE.MeshStandardMaterial({
    color, roughness: .92, metalness: .04, flatShading: true, ...options,
  }));
  return materials.get(key);
}
const geoCache = new Map();
function boxGeometry(w, h, d) {
  const key = `b${w},${h},${d}`;
  if (!geoCache.has(key)) geoCache.set(key, new THREE.BoxGeometry(w, h, d));
  return geoCache.get(key);
}
function mesh(parent, geometry, material, x = 0, y = 0, z = 0, shadows = true) {
  const m = new THREE.Mesh(geometry, material);
  m.position.set(x, y, z);
  m.castShadow = shadows;
  m.receiveShadow = shadows;
  parent.add(m);
  return m;
}
function box(parent, w, h, d, color, x = 0, y = 0, z = 0) {
  return mesh(parent, boxGeometry(w, h, d), typeof color === 'number' ? mat(color) : color, x, y, z);
}
function cylinder(parent, rt, rb, h, color, x = 0, y = 0, z = 0, n = 8) {
  return mesh(parent, new THREE.CylinderGeometry(rt, rb, h, n), typeof color === 'number' ? mat(color) : color, x, y, z);
}
function group(parent, x = 0, y = 0, z = 0) {
  const g = new THREE.Group(); g.position.set(x, y, z); parent.add(g); return g;
}
function beam(parent, from, to, width, depth, color) {
  const a = new THREE.Vector3(...from), b = new THREE.Vector3(...to);
  const m = box(parent, width, a.distanceTo(b), depth, color);
  m.position.copy(a).add(b).multiplyScalar(.5);
  m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.sub(a).normalize());
  return m;
}
const stoneColors = [0x464b40, 0x555548, 0x3f483d, 0x4e5144, 0x505142, 0x41493e];
const scratchColor = 0x8a8064;
const warmMaterial = mat(0xd1953c, { emissive: 0xe88c25, emissiveIntensity: 1.5 });
const candleMaterial = mat(0xd7c594);
const flames = [], fogs = [], townNpcs = [];

function tiledFloor(parent, size, y = 0) {
  box(parent, size + 1, .55, size + 1, 0x202b24, 0, y - .38, 0);
  const count = Math.floor(size);
  const geometry = boxGeometry(.96, .13, .96);
  const tiles = new THREE.InstancedMesh(geometry, mat(0xffffff), count * count);
  const dummy = new THREE.Object3D(), color = new THREE.Color();
  let index = 0;
  for (let x = 0; x < count; x++) for (let z = 0; z < count; z++) {
    dummy.position.set(x - (count - 1) / 2, y - random() * .026, z - (count - 1) / 2);
    dummy.rotation.y = (random() - .5) * .025;
    dummy.scale.set(.96 + random() * .04, 1, .96 + random() * .04);
    dummy.updateMatrix(); tiles.setMatrixAt(index, dummy.matrix);
    color.setHex(stoneColors[Math.floor(random() * stoneColors.length)]);
    color.multiplyScalar(.75 + random() * .3);
    tiles.setColorAt(index++, color);
  }
  tiles.receiveShadow = true; parent.add(tiles);
}

function pillar(parent, x, z, height = 5.3, broken = false) {
  const p = group(parent, x, 0, z);
  box(p, 1.03, .25, 1.03, 0x545747, 0, .1);
  box(p, .82, .24, .82, 0x404638, 0, .34);
  for (let i = 0; i < 6; i++) {
    const piece = cylinder(p, .31, .34, (height - .65) / 6 - .025, stoneColors[i], 0, .63 + i * ((height - .65) / 6), 0, 6);
    if (broken && i === 5) { piece.rotation.z = .1; piece.position.x = .08; }
  }
  for (const dx of [-.25, .25]) for (const dz of [-.25, .25]) box(p, .11, height - .45, .11, 0x555746, dx, height / 2, dz);
  if (!broken) {
    box(p, .8, .18, .8, 0x67634e, 0, height);
    box(p, 1.04, .2, 1.04, 0x414a3d, 0, height + .18);
  }
  return p;
}

function gothicArch(parent, width = 4.2, height = 6, depth = .5, color = 0x4e5344) {
  const a = group(parent);
  const spring = height * .53;
  for (const side of [-1, 1]) {
    box(a, .45, spring, depth, color, side * width / 2, spring / 2);
    box(a, .7, .24, depth + .2, 0x68614a, side * width / 2, .12);
    box(a, .58, .22, depth + .12, 0x67604a, side * width / 2, spring);
    const curve = new THREE.QuadraticBezierCurve3(
      new THREE.Vector3(side * width / 2, spring, 0),
      new THREE.Vector3(side * width / 2, height * .83, 0),
      new THREE.Vector3(0, height, 0),
    );
    const points = curve.getPoints(10);
    for (let i = 0; i < points.length - 1; i++) beam(a, points[i].toArray(), points[i + 1].toArray(), .43, depth, i % 3 ? color : 0x68614d);
    // Thin raised ribs catch candlelight.
    for (let i = 0; i < points.length - 1; i++) {
      const p = points[i].clone(), q = points[i + 1].clone();
      p.x *= .91; q.x *= .91; p.z += depth / 2 + .035; q.z += depth / 2 + .035;
      beam(a, p.toArray(), q.toArray(), .045, .06, 0x898064);
    }
  }
  return a;
}

function candle(parent, x, y, z, scale = 1) {
  const c = group(parent, x, y, z); c.scale.setScalar(scale);
  cylinder(c, .08, .075, .36, candleMaterial, 0, .18);
  box(c, .015, .065, .015, 0x342923, 0, .38);
  const flame = mesh(c, new THREE.OctahedronGeometry(.1), warmMaterial, 0, .46, 0, false);
  flame.scale.set(.65, 1.8, .65);
  const glow = mesh(c, new THREE.SphereGeometry(.23, 6, 4), mat(0xeaa344, {
    emissive: 0xe49c43, emissiveIntensity: 1.4, transparent: true, opacity: .065, depthWrite: false,
  }), 0, .46, 0, false);
  flames.push({ mesh: flame, glow, phase: random() * 10, base: 1.8 });
  return c;
}
function candelabra(parent, x, z, height = 1.6, light = true) {
  const c = group(parent, x, 0, z);
  cylinder(c, .22, .4, .2, 0x242b25, 0, .12);
  cylinder(c, .065, .11, height, 0x383b2d, 0, height / 2);
  cylinder(c, .16, .13, .15, 0x716044, 0, height * .7);
  for (const side of [-1, 1]) {
    beam(c, [0, height - .3, 0], [side * .45, height - .13, 0], .045, .045, 0x4f4b34);
    beam(c, [side * .45, height - .13, 0], [side * .45, height + .08, 0], .045, .045, 0x4f4b34);
    cylinder(c, .14, .11, .045, 0x87724c, side * .45, height + .1);
    candle(c, side * .45, height + .11, 0, .83);
  }
  cylinder(c, .16, .12, .045, 0x87724c, 0, height + .05);
  candle(c, 0, height + .07, 0, 1.13);
  if (light) {
    const point = new THREE.PointLight(0xffbd68, 12, 7, 2);
    point.position.set(0, height + .5, 0); c.add(point);
    flames.push({ light: point, intensity: 12, phase: random() * 10 });
  }
  return c;
}

function makeFog(parent, size, y, opacity) {
  const m = new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, side: THREE.DoubleSide,
    uniforms: { time: { value: 0 }, opacity: { value: opacity }, tint: { value: new THREE.Color(0x839780) } },
    vertexShader: `varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,
    fragmentShader: `
      varying vec2 vUv; uniform float time; uniform float opacity; uniform vec3 tint;
      float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
      float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
        return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
      void main(){vec2 p=vUv*7.+vec2(time*.018,time*.009);
        float n=noise(p)*.65+noise(p*2.1)*.35;
        float edge=smoothstep(0.,.18,vUv.x)*smoothstep(0.,.18,1.-vUv.x)*smoothstep(0.,.18,vUv.y)*smoothstep(0.,.18,1.-vUv.y);
        gl_FragColor=vec4(tint,smoothstep(.24,.8,n)*opacity*edge);}`,
  });
  const p = mesh(parent, new THREE.PlaneGeometry(size, size), m, 0, y, 0, false);
  p.rotation.x = -Math.PI / 2;
  p.rotation.z = random();
  fogs.push(m); return p;
}

function makeMotes(parent, count, radius, color) {
  const positions = new Float32Array(count * 3), seeds = [];
  for (let i = 0; i < count; i++) {
    const x = (random() - .5) * radius, y = random() * 7, z = (random() - .5) * radius;
    positions.set([x, y, z], i * 3); seeds.push([x, y, z, random() * TAU]);
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  const p = new THREE.Points(g, new THREE.PointsMaterial({ color, size: .027, transparent: true, opacity: .65, depthWrite: false }));
  parent.add(p); return { points: p, seeds };
}
const motes = [];

function createSelectionWorld() {
  tiledFloor(selectionWorld, 26, -.2);
  for (let i = 0; i < 3; i++) cylinder(selectionWorld, 2.7 - i * .18, 2.7 - i * .18, .19, 0x424a3a, 0, -.04 + i * .19, 0, 12);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(2.25, .025, 3, 64), mat(0xa28b51, { metalness: .5, roughness: .7 }));
  rim.rotation.x = Math.PI / 2; rim.position.y = .45; selectionWorld.add(rim);
  const inner = rim.clone(); inner.scale.setScalar(.92); inner.position.y = .451; selectionWorld.add(inner);
  for (let i = 0; i < 24; i++) {
    const a = i / 24 * TAU;
    const tile = box(selectionWorld, .12, .014, .23, 0xa08b56, Math.cos(a) * 2.05, .449, Math.sin(a) * 2.05);
    tile.rotation.y = -a;
  }
  for (let i = 0; i < 11; i++) {
    const a = random() * TAU, r = random() * 1.8;
    box(selectionWorld, .03, .014, .25 + random() * .4, 0x343d32, Math.cos(a) * r, .452, Math.sin(a) * r).rotation.y = random() * TAU;
  }
  pillar(selectionWorld, -4.2, -.8, 5.8);
  pillar(selectionWorld, 4.7, -.8, 5.8);
  pillar(selectionWorld, -4.2, -5, 6.1);
  pillar(selectionWorld, 4.7, -5, 6.1);
  pillar(selectionWorld, -7, 2.2, 3.1, true);
  pillar(selectionWorld, 7.5, 2, 3.8, true);
  const arch = gothicArch(selectionWorld, 4.2, 6.6, .8, 0x3f493c);
  arch.position.set(0, -.1, -5.6);
  box(selectionWorld, 4.1, 7.7, .2, 0x0c1713, 0, 3.7, -5.9);
  for (let x = -1.5; x <= 1.5; x += .5) {
    box(selectionWorld, .06, 4.2, .06, 0x383d2b, x, 2.0, -5.63);
    mesh(selectionWorld, new THREE.ConeGeometry(.11, .26, 4), mat(0x706144), x, 4.22, -5.63);
  }
  for (const y of [1.1, 2.4, 3.3]) box(selectionWorld, 3.3, .05, .08, 0x484b35, 0, y, -5.62);
  for (const side of [-1, 1]) {
    for (let i = 0; i < 7; i++) box(selectionWorld, 4.4, .8, .9, stoneColors[i % 6], side * 4.4, i * .85 + .3, -6.2);
    const sideArch = gothicArch(selectionWorld, 2.5, 4.3, .3, 0x333f33);
    sideArch.position.set(side * 6.9, -.2, -4.8);
    box(selectionWorld, 2.3, 4.3, .1, 0x0e1913, side * 6.9, 1.9, -5);
    candelabra(selectionWorld, side * 3.35, -.3, 1.55, true);
    candle(selectionWorld, side * 2.2, .47, .85, 1);
    candle(selectionWorld, side * 2.02, .47, 1.17, .72);
    candle(selectionWorld, side * 2.42, .28, 1.24, .87);
  }
  // Fallen masonry and quiet moss give the stage a lived-in scale.
  for (let i = 0; i < 50; i++) {
    const angle = random() * TAU, radius = 3.8 + random() * 6;
    const x = Math.cos(angle) * radius, z = Math.sin(angle) * radius;
    const rock = box(selectionWorld, .15 + random() * .35, .08 + random() * .2, .2 + random() * .4, stoneColors[i % 6], x, -.08, z);
    rock.rotation.set(random() * .3, random() * TAU, random() * .3);
  }
  for (let i = 0; i < 5; i++) makeFog(selectionWorld, 25, .08 + i * .23, .1);
  motes.push(makeMotes(selectionWorld, 85, 15, 0xc1b68a));
  const fill = new THREE.PointLight(0xa7c5ad, 17, 11, 2); fill.position.set(1, 4, -3); selectionWorld.add(fill);
  const key = new THREE.SpotLight(0xe1cdaa, 80, 18, .65, .8, 1.5);
  key.position.set(-2, 7, 4); key.target.position.set(0, 1.5, 0);
  selectionWorld.add(key, key.target);
}
const hemi = new THREE.HemisphereLight(0xb4c4ac, 0x303126, 1.25);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff0d0, 1.6);
sun.position.set(8, 18, 6);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.camera.left = -18; sun.shadow.camera.right = 18;
sun.shadow.camera.top = 18; sun.shadow.camera.bottom = -18;
sun.shadow.normalBias = .04; sun.shadow.bias = -.00012;
scene.add(sun);
const moon = new THREE.DirectionalLight(0x9cbaa9, 2.1);
moon.position.set(-5, 12, 6);
moon.castShadow = true;
moon.shadow.mapSize.set(2048, 2048);
moon.shadow.camera.left = -15; moon.shadow.camera.right = 15;
moon.shadow.camera.top = 15; moon.shadow.camera.bottom = -15;
moon.shadow.normalBias = .035; moon.shadow.bias = -.0001;
scene.add(moon);
// Procedural sky dome with gradient driven by day time.
const skyUniforms = {
  topColor: { value: new THREE.Color(0x1a2a3e) },
  bottomColor: { value: new THREE.Color(0x3b4a55) },
  sunColor: { value: new THREE.Color(0xffd27a) },
  sunDir: { value: new THREE.Vector3(0, 1, 0) },
  sunIntensity: { value: 0 },
};
const sky = new THREE.Mesh(new THREE.SphereGeometry(110, 24, 16), new THREE.ShaderMaterial({
  side: THREE.BackSide, depthWrite: false,
  uniforms: skyUniforms,
  vertexShader: `varying vec3 vWorldDir; void main(){vWorldDir=normalize(position);gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,
  fragmentShader: `
    varying vec3 vWorldDir; uniform vec3 topColor, bottomColor, sunColor, sunDir; uniform float sunIntensity;
    void main(){
      float h=clamp(vWorldDir.y*0.5+0.5,0.,1.);
      vec3 col=mix(bottomColor,topColor,pow(h,.65));
      float sd=max(dot(normalize(vWorldDir),normalize(sunDir)),0.);
      col+=sunColor*pow(sd,180.)*sunIntensity*1.6;
      col+=sunColor*smoothstep(.85,1.,sd)*sunIntensity*.4;
      gl_FragColor=vec4(col,1.);
    }`,
}));
sky.frustumCulled = false;
scene.add(sky);
function updateDayNight(dt) {
  if (!state.dayPaused) state.dayTime = (state.dayTime + dt * state.daySpeed * 60 / 60) % 24;
  const h = state.dayTime;
  // Sun height: sunrise ~6, noon ~12, sunset ~18, midnight ~0.
  const sunAngle = ((h - 6) / 24) * TAU;
  const sunHeight = Math.sin(sunAngle); // -1..1
  const dayFactor = clamp(sunHeight, 0, 1);
  const nightFactor = clamp(-sunHeight, 0, 1);
  const horizon = 1 - Math.abs(sunHeight);
  // Sky colors.
  const dayTop = new THREE.Color(0x5b86b8), dayBottom = new THREE.Color(0xc9d6cf);
  const duskTop = new THREE.Color(0x6e4a52), duskBottom = new THREE.Color(0xc08a5a);
  const nightTop = new THREE.Color(0x0c1422), nightBottom = new THREE.Color(0x1a2533);
  skyUniforms.topColor.value.copy(nightTop).lerp(duskTop, horizon * .9).lerp(dayTop, dayFactor);
  skyUniforms.bottomColor.value.copy(nightBottom).lerp(duskBottom, horizon * .85).lerp(dayBottom, dayFactor);
  skyUniforms.sunDir.value.set(Math.cos(sunAngle), sunHeight, .45).normalize();
  skyUniforms.sunIntensity.value = dayFactor;
  sun.position.set(Math.cos(sunAngle) * 20, Math.max(sunHeight * 20, -5), 8);
  sun.intensity = dayFactor * 2.4;
  moon.intensity = nightFactor * 1.9 + .15;
  hemi.intensity = .35 + dayFactor * 1.25;
  hemi.color.copy(new THREE.Color(0x2a3550)).lerp(new THREE.Color(0xb4c4ac), dayFactor);
  hemi.groundColor.copy(new THREE.Color(0x1a1d22)).lerp(new THREE.Color(0x4a4530), dayFactor);
  // Fog and exposure.
  const fogDay = new THREE.Color(0xb9c4bd), fogDusk = new THREE.Color(0x6e5b4c), fogNight = new THREE.Color(0x12181f);
  scene.fog.color.copy(fogNight).lerp(fogDusk, horizon * .6).lerp(fogDay, dayFactor);
  scene.fog.density = state.mode === 'dungeon' ? .045 : (.022 + nightFactor * .012);
  renderer.toneMappingExposure = .75 + dayFactor * .85;
  // Background matches horizon.
  scene.background.copy(skyUniforms.bottomColor.value);
  // Clock UI.
  const hh = String(Math.floor(h)).padStart(2, '0');
  const mm = String(Math.floor((h % 1) * 60)).padStart(2, '0');
  $('#clock-text').textContent = `${hh}:${mm}`;
  $('#clock-icon').textContent = dayFactor > .6 ? '☀' : horizon > .3 ? '◐' : '☾';
  $('#clock-toggle').classList.toggle('paused', state.dayPaused);
  const phase = h < 5 ? '深夜' : h < 7 ? '黎明' : h < 11 ? '清晨' : h < 14 ? '正午' : h < 17 ? '午后' : h < 19 ? '黄昏' : h < 21 ? '暮色' : '夜晚';
  const townTime = $('#town-time'); if (townTime) townTime.textContent = `${phase} ${hh}:${mm}`;
}
createSelectionWorld();

/**
 * Model replacement API.
 * registerCharacterFactory('archer', factory) accepts an async factory returning:
 * { root: THREE.Group, update(dt, elapsed, pose), setOpacity(value), dispose?() }.
 * Foot pivot must be (0,0,0), height ≈ 2.7, facing +Z. Real GLTF models may map
 * pose to AnimationMixer clips. No selection/town code depends on mesh names.
 */
const characterFactories = new Map();
export function registerCharacterFactory(id, factory) {
  if (!CLASS_DATA[id] || typeof factory !== 'function') throw new TypeError('Unknown class or invalid factory');
  characterFactories.set(id, factory);
}
function createProceduralCharacter(id) {
  const warrior = id === 'warrior';
  const root = new THREE.Group();
  root.userData.dynamic = true;
  const rig = group(root);
  const torso = group(rig, 0, 1.35, 0);
  const palette = warrior
    ? { cloth: 0x563d30, cloth2: 0x3d3028, armor: 0x5d6258, edge: 0x9b865d, skin: 0xb49b78, hair: 0x684a35, leather: 0x392d25 }
    : { cloth: 0x344d3d, cloth2: 0x23382c, armor: 0x555744, edge: 0xb69e6b, skin: 0xc5baa0, hair: 0xc6c8b7, leather: 0x473c2b };
  const bodyWidth = warrior ? .76 : .54;
  const body = cylinder(torso, bodyWidth * .68, bodyWidth * .56, .72, palette.cloth, 0, .19, 0, 6);
  body.rotation.y = Math.PI / 6;
  box(torso, bodyWidth, .46, .39, palette.armor, 0, .34, .02);
  box(torso, bodyWidth * .66, .13, .065, palette.edge, 0, .47, .228);
  box(torso, bodyWidth + .02, .11, .45, palette.leather, 0, -.06, .025);
  box(torso, .13, .13, .055, palette.edge, 0, -.06, .269);
  for (const x of [-1, 1]) box(torso, .09, .11, .08, palette.edge, x * bodyWidth * .32, .42, .235);
  if (warrior) {
    box(torso, .56, .67, .09, palette.leather, 0, -.28, .24);
    box(torso, .46, .045, .095, palette.edge, 0, -.54, .25);
    beam(torso, [-.24, .65, .27], [.24, -.03, .27], .09, .05, palette.leather);
    for (let i = 0; i < 4; i++) box(torso, .04, .05, .045, palette.edge, -.19 + i * .12, -.46, .302);
  } else {
    beam(torso, [-.25, .61, .25], [.23, -.12, .25], .09, .035, palette.leather);
    const cape = new THREE.Mesh(new THREE.CylinderGeometry(.35, .67, 1.42, 5, 1, true, Math.PI / 2, Math.PI), mat(palette.cloth2, { side: THREE.DoubleSide }));
    cape.position.set(0, -.07, -.12); cape.rotation.x = -.12; torso.add(cape);
    const trim = box(torso, .07, 1.13, .06, palette.edge, -.35, -.2, -.25); trim.rotation.z = -.13;
    const quiver = cylinder(torso, .12, .1, .77, palette.leather, .3, .25, -.35, 6); quiver.rotation.z = -.19;
    for (let i = 0; i < 5; i++) {
      const arrow = group(torso, .23 + i * .04, .47 + (i % 2) * .04, -.35);
      box(arrow, .016, .68, .016, palette.edge);
      box(arrow, .075, .12, .015, palette.hair, 0, .3);
      arrow.rotation.z = -.19;
    }
  }
  const head = group(torso, 0, .88, .015);
  cylinder(head, .12, .14, .18, palette.skin, 0, -.31);
  box(head, .44, .48, .41, palette.skin, 0, -.025, .02);
  box(head, .075, .105, .11, palette.skin, 0, -.04, .265);
  for (const side of [-1, 1]) {
    box(head, .1, .041, .021, 0x26372d, side * .115, .035, .239);
    box(head, .04, .028, .025, warrior ? 0xb5b68b : 0xc9d8bb, side * .11, .033, .25);
    box(head, .12, .035, .035, palette.hair, side * .112, .096, .236).rotation.z = side * .1;
  }
  if (warrior) {
    box(head, .49, .16, .46, palette.hair, 0, .24, .01);
    box(head, .47, .12, .08, 0x8b7850, 0, .16, .245);
    box(head, .41, .25, .12, palette.hair, 0, -.23, .22);
    box(head, .27, .15, .11, palette.hair, 0, -.39, .2);
    for (const s of [-1, 1]) box(head, .085, .2, .08, 0x876048, s * .13, -.28, .285);
    box(head, .08, .07, .13, palette.edge, 0, -.41, .23);
  } else {
    // Angular silver hair, long pointed ears and a deep green hood.
    box(head, .49, .15, .46, palette.hair, 0, .24);
    for (const side of [-1, 1]) {
      box(head, .105, .56, .32, palette.hair, side * .247, -.09, -.05).rotation.z = side * .06;
      const ear = mesh(head, new THREE.ConeGeometry(.09, .31, 3), mat(palette.skin), side * .326, .03, .02);
      ear.rotation.z = side * -1.05;
      box(head, .07, .1, .04, palette.edge, side * .35, -.03, .09);
    }
    const hood = cylinder(head, .21, .37, .38, palette.cloth, 0, .3, -.095, 5);
    hood.rotation.y = Math.PI / 5;
    box(head, .12, .06, .035, palette.edge, 0, .23, .27);
  }
  const arms = {}, legs = {};
  for (const [name, side] of [['left', -1], ['right', 1]]) {
    const upper = group(torso, side * (bodyWidth / 2 + .075), .48, 0);
    const upperWidth = warrior ? .25 : .18;
    box(upper, upperWidth, .44, .24, palette.cloth, side * .015, -.2);
    const shoulder = cylinder(upper, warrior ? .27 : .19, warrior ? .23 : .16, .22, palette.armor, side * .015, -.005, 0, 5);
    shoulder.rotation.z = side * .12;
    box(upper, warrior ? .36 : .24, .06, .29, palette.edge, side * .025, .12);
    const lower = group(upper, 0, -.43, 0);
    box(lower, upperWidth * .92, .33, .23, palette.leather, 0, -.16);
    box(lower, upperWidth + .04, .23, .26, warrior ? palette.armor : palette.cloth, 0, -.1);
    box(lower, upperWidth + .05, .045, .27, palette.edge, 0, -.235);
    box(lower, upperWidth * .86, .15, .19, palette.skin, 0, -.37);
    arms[name] = { upper, lower, hand: group(lower, 0, -.41, .025) };
    const thigh = group(rig, side * (warrior ? .225 : .17), 1.2, 0);
    box(thigh, warrior ? .28 : .21, .53, .28, palette.cloth2, 0, -.22);
    const knee = group(thigh, 0, -.49, 0);
    box(knee, warrior ? .285 : .22, .51, .28, palette.leather, 0, -.23);
    box(knee, warrior ? .31 : .23, .23, .3, palette.armor, 0, -.02, .02);
    box(knee, warrior ? .32 : .245, .22, .43, palette.leather, 0, -.5, .07);
    box(knee, warrior ? .33 : .25, .07, .44, 0x23281f, 0, -.61, .065);
    legs[name] = { thigh, knee };
  }
  // Weapons are mounted at the hand pivot and offset outwards so they never
  // clip through the torso. `weapon.localOffset` preserves the rest pose so
  // every animation frame can restore and build on top of it.
  const weapon = group(warrior ? arms.right.hand : arms.left.hand);
  let string, arrowMesh, hammerHead;
  if (warrior) {
    // Grip at the bottom of the handle; head sits above the hand.
    const handle = box(weapon, .075, 1.25, .075, palette.leather, 0, .55, .05);
    for (let i = 0; i < 6; i++) box(weapon, .09, .026, .09, palette.edge, 0, i * .075 + .18, .05);
    hammerHead = group(weapon, 0, 1.18, .05);
    box(hammerHead, .52, .34, .34, 0x5a6359);
    for (const side of [-1, 1]) box(hammerHead, .1, .38, .38, 0x9c895e, side * .28, 0);
    box(hammerHead, .17, .18, .02, palette.edge, 0, 0, .2);
    weapon.position.set(.04, -.02, .05);
    weapon.rotation.set(.05, 0, -.15);
  } else {
    // Bow held on the left side, string facing forward (+Z).
    const points = [[0,-.82,0],[-.2,-.62,0],[-.34,-.33,0],[-.38,0,0],[-.34,.33,0],[-.2,.62,0],[0,.82,0]];
    for (let i = 0; i < points.length - 1; i++) beam(weapon, points[i], points[i + 1], .072, .068, palette.edge);
    box(weapon, .085, .26, .085, palette.leather, -.36, 0);
    const geometry = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(0, -.82, 0), new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, .82, 0),
    ]);
    string = new THREE.Line(geometry, new THREE.LineBasicMaterial({ color: 0xd7d0b0 }));
    weapon.add(string); weapon.position.set(.03, -.02, .06);
    weapon.rotation.set(.05, 0, .18);
    arrowMesh = box(weapon, 1.35, .024, .024, palette.edge, -.66, 0, .025);
    arrowMesh.visible = false;
  }
  weapon.userData.localOffset = weapon.position.clone();
  weapon.userData.localRotation = weapon.rotation.clone();
  // Clone materials once per character for independent dissolve without touching the world.
  const ownMaterials = new Set();
  root.traverse(obj => {
    if (!obj.material) return;
    obj.material = obj.material.clone();
    obj.material.transparent = true;
    ownMaterials.add(obj.material);
  });
  const rest = [];
  for (const obj of [torso, head, arms.left.upper, arms.left.lower, arms.right.upper, arms.right.lower, legs.left.thigh, legs.right.thigh, legs.left.knee, legs.right.knee, weapon]) {
    rest.push([obj, obj.position.clone(), obj.rotation.clone()]);
  }
  function update(dt, elapsed, pose) {
    for (const [obj, position, rotation] of rest) { obj.position.copy(position); obj.rotation.copy(rotation); }
    const t = reducedMotion ? 0 : elapsed;
    torso.position.y += Math.sin(t * 1.7) * .022;
    torso.rotation.z = Math.sin(t * .9) * .012;
    arms.left.upper.rotation.z = .12; arms.right.upper.rotation.z = -.12;
    arms.left.lower.rotation.x = -.12; arms.right.lower.rotation.x = -.12;
    head.rotation.y = Math.sin(t * .6) * .035;
    if (pose.type === 'walk') {
      const s = Math.sin(pose.step), c = Math.cos(pose.step);
      legs.left.thigh.rotation.x = s * .55; legs.right.thigh.rotation.x = -s * .55;
      legs.left.knee.rotation.x = Math.max(0, -c) * .45;
      legs.right.knee.rotation.x = Math.max(0, c) * .45;
      arms.left.upper.rotation.x = -s * .32; arms.right.upper.rotation.x = s * .32;
      torso.position.y += Math.abs(s) * .038;
      torso.rotation.x = .06;
    } else if (pose.type === 'showcase') {
      const p = pose.time;
      if (!warrior) {
        const lift = smooth(p / 1.0) * (1 - smooth((p - 3.35) / .9));
        const draw = smooth((p - .8) / .9) * (1 - smooth((p - 2.85) / .22));
        torso.rotation.y = -.4 * lift;
        head.rotation.y = -.45 * lift;
        arms.left.upper.rotation.z = .12 - 1.57 * lift;
        arms.left.lower.rotation.z = -.08 * lift;
        arms.left.lower.rotation.x = -.12 * (1 - lift);
        arms.right.upper.rotation.z = -.75 * lift;
        arms.right.lower.rotation.z = -1.72 * draw;
        arms.right.lower.rotation.x = -.12 * (1 - lift);
        weapon.rotation.z = .18 + 1.53 * lift;
        weapon.rotation.y = (1 - lift) * .12;
        weapon.position.x = lerp(.03, -.05, lift);
        weapon.position.y = lerp(-.02, .28, lift);
        const position = string.geometry.attributes.position;
        position.setX(1, draw * .56); position.needsUpdate = true;
        arrowMesh.visible = p > .9 && p < 2.98;
        arrowMesh.position.x = -.66 + draw * .56;
        legs.right.thigh.rotation.z = -.08 * lift;
      } else {
        const plant = smooth(p / .85) * (1 - smooth((p - 3.55) / .8));
        const salute = smooth((p - 1.8) / .38) * (1 - smooth((p - 3.1) / .4));
        weapon.rotation.z = -.15 + (Math.PI - .2) * plant;
        weapon.position.y += .3 * plant;
        arms.right.upper.rotation.z = .35 * plant;
        arms.right.upper.rotation.x = -.05 * plant;
        arms.right.lower.rotation.x = -.12 * (1 - plant);
        arms.left.upper.rotation.z = lerp(-.75, -.45, salute) * plant;
        arms.left.lower.rotation.z = lerp(1.5, 2.7, salute) * plant;
        arms.left.upper.rotation.x = -.1 * salute;
        arms.left.lower.rotation.x = -.48 * salute;
        const impact = Math.max(0, 1 - Math.abs(p - 2.36) * 10);
        torso.rotation.x = -.045 * plant + .08 * impact;
        torso.position.y -= .055 * plant;
        head.rotation.x = -.1 * salute;
        legs.left.thigh.rotation.z = .07 * plant;
        legs.right.thigh.rotation.z = -.07 * plant;
      }
    } else if (pose.type === 'attack') {
      const p = pose.time;
      if (!warrior) {
        // Archer: draw (0-.3), hold (.3-.5), release (.5-.6), recover.
        const draw = smooth(p / .3) * (1 - smooth((p - .45) / .15));
        const recoil = smooth((p - .5) / .12) * (1 - smooth((p - .7) / .3));
        torso.rotation.y = -.28 * draw;
        head.rotation.y = -.32 * draw;
        arms.left.upper.rotation.z = .12 - 1.4 * draw;
        arms.left.lower.rotation.z = -.06 * draw;
        arms.left.lower.rotation.x = -.12 * (1 - draw);
        arms.right.upper.rotation.z = -.7 * draw;
        arms.right.lower.rotation.z = -1.7 * draw;
        weapon.rotation.z = .18 + 1.4 * draw;
        weapon.position.x = lerp(.03, -.06, draw);
        weapon.position.y = lerp(-.02, .24, draw);
        if (string) { string.geometry.attributes.position.setX(1, draw * .56); string.geometry.attributes.position.needsUpdate = true; }
        if (arrowMesh) {
          arrowMesh.visible = draw > .05 && p < .52;
          arrowMesh.position.x = -.66 + draw * .56;
        }
        torso.rotation.x = .08 * recoil;
      } else {
        // Warrior: wind up (0-.3), swing down (.3-.55), impact (.55-.7), recover.
        const wind = smooth(p / .3);
        const swing = smooth((p - .3) / .25) * (1 - smooth((p - .55) / .15));
        const impact = Math.max(0, 1 - Math.abs(p - .58) * 14);
        arms.right.upper.rotation.x = -1.4 * wind;
        arms.right.upper.rotation.z = -.15 - .6 * wind;
        arms.right.lower.rotation.x = -.4 - .5 * wind;
        weapon.rotation.z = -.15 - 1.7 * wind + 3.0 * swing;
        weapon.position.y += .05 * wind - .18 * swing;
        arms.left.upper.rotation.z = .4 * wind;
        arms.left.lower.rotation.z = .5 * wind;
        torso.rotation.x = -.12 * wind + .18 * impact;
        torso.position.y -= .06 * impact;
        head.rotation.x = .08 * impact;
        legs.left.thigh.rotation.z = .1 * impact;
        legs.right.thigh.rotation.z = -.1 * impact;
      }
    } else if (!warrior) {
      string.geometry.attributes.position.setX(1, 0); string.geometry.attributes.position.needsUpdate = true;
      arrowMesh.visible = false;
    }
  }
  return {
    root, update,
    setOpacity(value) { for (const m of ownMaterials) { m.opacity = value; m.depthWrite = value > .7; } root.visible = value > .005; },
    dispose() { for (const m of ownMaterials) m.dispose(); },
  };
}
registerCharacterFactory('archer', () => createProceduralCharacter('archer'));
registerCharacterFactory('warrior', () => createProceduralCharacter('warrior'));
const characters = {};
for (const id of Object.keys(CLASS_DATA)) {
  characters[id] = await characterFactories.get(id)();
  characters[id].root.position.y = .47;
  characters[id].root.visible = id === state.selected;
  selectionWorld.add(characters[id].root);
}
// Can be called after registering a GLTF factory to hot-swap one class safely.
export async function reloadCharacter(id) {
  if (state.phase !== 'idle' || state.switchingScene) return false;
  const next = await characterFactories.get(id)();
  const previous = characters[id];
  next.root.position.copy(previous.root.position);
  next.root.rotation.copy(previous.root.rotation);
  next.root.scale.copy(previous.root.scale);
  next.root.visible = previous.root.visible;
  previous.root.parent.add(next.root);
  previous.root.removeFromParent(); previous.dispose?.();
  characters[id] = next;
  return true;
}

// Dissolve uses drifting low-poly black particles; no external textures.
const smokeRoot = group(selectionWorld, 0, .47, 0);
smokeRoot.userData.dynamic = true;
const smoke = [];
const smokeGeometry = new THREE.IcosahedronGeometry(.13, 0);
for (let i = 0; i < 58; i++) {
  const m = mesh(smokeRoot, smokeGeometry, mat(0x17271d, { transparent: true, opacity: 0, depthWrite: false }).clone(), 0, 0, 0, false);
  smoke.push({ mesh: m, angle: random() * TAU, y: random() * 2.7, radius: .2 + random() * .8, speed: .6 + random() });
}
function updateSmoke(amount) {
  smokeRoot.visible = amount > .001;
  for (const s of smoke) {
    const a = s.angle + state.time * s.speed;
    s.mesh.position.set(Math.cos(a) * s.radius * (1.2 - amount * .25), (s.y + state.time * .65) % 3.1, Math.sin(a) * s.radius);
    s.mesh.scale.setScalar(.6 + amount * 1.6);
    s.mesh.material.opacity = amount * .7;
    s.mesh.rotation.set(a, a * .7, a * .4);
  }
}

// ---------------------- THE ASHEN SANCTUARY ----------------------
const obstacles = [], pois = [], collectibleMeshes = new Map();
function obstacle(x, z, w, d) { obstacles.push({ x, z, w: w / 2, d: d / 2 }); }
function windowFrame(parent, x, y, z, w = .46, h = .85) {
  box(parent, w + .18, h + .18, .15, 0x2c342b, x, y, z);
  box(parent, w, h, .045, mat(0xdba050, { emissive: 0xdd9838, emissiveIntensity: .95 }), x, y, z + .09);
  box(parent, .045, h, .065, 0x423d28, x, y, z + .12);
  box(parent, w, .06, .07, 0x423d28, x, y + .08, z + .12);
  box(parent, w + .26, .12, .26, 0x69614a, x, y - h / 2, z + .04);
}
function building(parent, x, z, w, d, h, roofColor = 0x303b36) {
  const b = group(parent, x, 0, z);
  box(b, w + .25, .35, d + .25, 0x41493b, 0, .1);
  box(b, w, h, d, 0x515346, 0, h / 2 + .25);
  for (let i = 0; i < Math.floor(h / .55); i++) {
    box(b, w + .03, .035, d + .03, 0x394337, 0, .4 + i * .55);
    for (let j = 0; j < Math.floor(w / .7); j++) box(b, .035, .5, .035, 0x394337, -w / 2 + .3 + j * .7 + (i % 2) * .18, .65 + i * .55, d / 2 + .01);
  }
  for (const side of [-1, 1]) box(b, .22, h + .1, d + .12, 0x303d31, side * (w / 2 - .12), h / 2 + .25);
  box(b, w + .36, .18, d + .35, 0x73705a, 0, h + .23);
  const roofShape = new THREE.Shape();
  roofShape.moveTo(-w / 2 - .3, 0); roofShape.lineTo(0, w * .52); roofShape.lineTo(w / 2 + .3, 0); roofShape.closePath();
  const roof = mesh(b, new THREE.ExtrudeGeometry(roofShape, { depth: d + .48, bevelEnabled: false }), mat(roofColor), 0, h + .31, -d / 2 - .24);
  for (let i = 0; i < 6; i++) {
    const yy = i * w * .52 / 6;
    box(b, (w + .6) * (1 - i / 6), .04, d + .51, 0x4a5146, 0, h + .32 + yy);
  }
  box(b, .12, .15, d + .68, 0x777158, 0, h + .31 + w * .52);
  obstacle(x, z, w + .3, d + .3);
  return b;
}
function crate(parent, x, z, size = .65) {
  box(parent, size, size, size, 0x514633, x, size / 2, z);
  for (const s of [-1, 1]) {
    box(parent, .06, size, size + .03, 0x746045, x + s * size * .36, size / 2, z);
    box(parent, size + .025, .06, size + .025, 0x746045, x, size * (.5 + s * .37), z);
  }
}
function deadTree(parent, x, z, scale = 1) {
  const t = group(parent, x, 0, z); t.scale.setScalar(scale);
  beam(t, [0, 0, 0], [-.12, 2.7, 0], .18, .18, 0x343c2e);
  beam(t, [-.06, 1.3, 0], [-.85, 2.3, .2], .11, .1, 0x424b37);
  beam(t, [-.85, 2.3, .2], [-1.0, 3, .16], .055, .055, 0x424b37);
  beam(t, [-.09, 1.9, 0], [.62, 2.6, -.25], .1, .1, 0x424b37);
  beam(t, [.62, 2.6, -.25], [1, 2.72, -.3], .05, .05, 0x424b37);
  obstacle(x, z, .45, .45);
}
function addPoi(id, name, symbol, position, destination, onInteract, type = 'place') {
  const button = document.createElement('button');
  button.className = `poi-label ${type === 'ember' ? 'ember-label' : ''}`;
  button.dataset.poi = id;
  button.setAttribute('aria-label', `${name}，自动寻路并交互`);
  const badge = document.createElement('span'); badge.className = 'poi-symbol';
  const icon = document.createElement('i'); icon.textContent = symbol; badge.appendChild(icon);
  const label = document.createElement('span'); label.className = 'poi-name'; label.textContent = name;
  button.append(badge, label); $('#poi-labels').appendChild(button);
  const poi = { id, name, position: new THREE.Vector3(...position), destination: new THREE.Vector3(destination[0], 0, destination[1]), onInteract, button, type };
  button.addEventListener('click', () => travelToPoi(poi));
  pois.push(poi); return poi;
}

function createTown() {
  tiledFloor(townWorld, 24, -.13);
  for (let i = -10; i <= 10; i++) for (const x of [-2.8, 2.8]) box(townWorld, .16, .09, .9, 0x79715a, x, -.01, i);
  // Raised streets and retaining wall enclose a compact, readable town square.
  for (const x of [-10.5, 10.5]) {
    box(townWorld, .55, 1.0, 22, 0x434e3e, x, .3, 0);
    for (let z = -10; z <= 10; z += 1.6) box(townWorld, .72, 1.3, .6, 0x56604c, x, .48, z);
  }
  box(townWorld, 22, 1.8, .6, 0x384637, 0, .75, -10.3);
  const forge = building(townWorld, -6.8, -5.9, 4.6, 3.9, 2.7, 0x3a3530);
  windowFrame(forge, -1.25, 1.65, 2.0, .72, .75);
  const hearth = gothicArch(forge, 1.35, 1.8, .3, 0x74634d);
  hearth.position.set(.7, .15, 2.03);
  box(forge, 1.24, 1.5, .05, 0x171d17, .7, .9, 2.01);
  for (let i = 0; i < 7; i++) {
    const ember = mesh(forge, new THREE.OctahedronGeometry(.2), warmMaterial, .3 + i * .13, .4 + random() * .2, 2.14, false);
    ember.scale.y = 1.5; flames.push({ mesh: ember, phase: random() * 9, base: 1.5 });
  }
  const forgeLight = new THREE.PointLight(0xff9943, 17, 9, 2); forgeLight.position.set(-6, 1.9, -3.3); townWorld.add(forgeLight);
  box(forge, .75, 2.3, .85, 0x3a4135, -1.15, 4.4, -.55);
  box(forge, .9, .2, 1, 0x6c624c, -1.15, 5.58, -.55);
  const anvil = group(townWorld, -5.25, 0, -2.7);
  box(anvil, .65, .6, .55, 0x453b29, 0, .3);
  box(anvil, .82, .22, .43, 0x767a69, 0, .73);
  box(anvil, .41, .32, .36, 0x62695a, 0, .6);
  beam(anvil, [.32, .75, 0], [.66, .8, 0], .17, .22, 0x73796a);
  obstacle(-5.25, -2.7, 1, .9);
  const smith = createProceduralCharacter('warrior'); smith.root.position.set(-6.6, .06, -2.15); smith.root.scale.setScalar(.67); smith.root.rotation.y = .4; townWorld.add(smith.root); townNpcs.push(smith);

  const inn = building(townWorld, 6.3, -6.05, 4.5, 4.2, 3.45, 0x343c39);
  for (const x of [-1.3, 1.3]) { windowFrame(inn, x, 2.65, 2.13); windowFrame(inn, x, 1.15, 2.13, .54, .75); }
  box(inn, .86, 1.6, .08, 0x222e24, 0, .96, 2.16);
  box(inn, 1.0, .11, .4, 0x757058, 0, .22, 2.28);
  beam(inn, [.55, 2.5, 2.2], [.55, 2.5, 3.05], .06, .06, 0x504c35);
  box(inn, .76, .49, .08, 0x716245, .55, 2.16, 3.05);
  box(inn, .42, .045, .1, 0xc2ab6c, .55, 2.16, 3.1);

  const chapel = building(townWorld, 0, -9, 4.5, 2.4, 4.1, 0x333d39);
  const gate = gothicArch(chapel, 2.1, 3.65, .4, 0x77725d); gate.position.z = 1.38;
  box(chapel, 1.98, 3.2, .07, 0x12281f, 0, 1.6, 1.41);
  for (let x = -.8; x <= .8; x += .32) box(chapel, .055, 2.95, .09, 0x68684b, x, 1.5, 1.49);
  for (const side of [-1, 1]) {
    const spire = group(townWorld, side * 2.6, 0, -8.9);
    box(spire, .9, 5.1, 1, 0x535849, 0, 2.5);
    cylinder(spire, 0, .73, 2.35, 0x344139, 0, 6.05, 0, 4);
    box(spire, .055, .8, .055, 0x93835a, 0, 7.5); box(spire, .38, .055, .055, 0x93835a, 0, 7.64);
  }

  // Central sanctuary brazier, kept low to avoid hiding the player.
  for (let i = 0; i < 3; i++) cylinder(townWorld, 1.35 - i * .18, 1.35 - i * .18, .19, stoneColors[i + 1], 0, .04 + i * .19, 0, 10);
  cylinder(townWorld, .72, .45, .65, 0x4f5744, 0, .77, 0, 8);
  cylinder(townWorld, .84, .72, .15, 0x908566, 0, 1.13, 0, 8);
  cylinder(townWorld, .7, .65, .06, 0x282d20, 0, 1.2, 0, 8);
  for (let i = 0; i < 9; i++) {
    const a = i / 9 * TAU;
    const flame = mesh(townWorld, new THREE.OctahedronGeometry(.21), warmMaterial, Math.cos(a) * .35, 1.4 + random() * .18, Math.sin(a) * .35, false);
    flames.push({ mesh: flame, phase: random() * 9, base: 2.0, shrine: true });
  }
  obstacle(0, 0, 2.6, 2.6);
  const shrineLight = new THREE.PointLight(0xefc079, 15, 8, 2); shrineLight.position.set(0, 2, 0); townWorld.add(shrineLight);
  flames.push({ light: shrineLight, intensity: 15, phase: 0, shrine: true });

  // Apothecary's awning, stocked with little glass bottles.
  const stall = group(townWorld, 7.1, 0, 1.3);
  for (const x of [-1.2, 1.2]) for (const z of [-.7, .7]) box(stall, .08, 2.3, .08, 0x554d35, x, 1.15, z);
  box(stall, 2.4, .92, 1.25, 0x4b4632, 0, .46);
  box(stall, 2.65, .12, 1.4, 0x7a6950, 0, .98);
  for (let i = 0; i < 7; i++) {
    const cloth = box(stall, .39, .065, 1.9, i % 2 ? 0x60664a : 0x343f33, -1.17 + i * .39, 2.3);
    cloth.rotation.x = .14;
    box(stall, .39, .28, .05, i % 2 ? 0x60664a : 0x343f33, -1.17 + i * .39, 2.02, .95);
  }
  for (let i = 0; i < 10; i++) {
    const x = (random() - .5) * 2, z = (random() - .5) * .7;
    cylinder(stall, .045, .09, .22, i % 3 ? 0x74845d : 0x8e6651, x, 1.16, z, 5);
    cylinder(stall, .035, .035, .07, 0xb3a077, x, 1.3, z, 5);
  }
  obstacle(7.1, 1.3, 2.8, 2.1);
  const merchant = createProceduralCharacter('archer'); merchant.root.position.set(5.6, 0, 1.2); merchant.root.scale.setScalar(.63); merchant.root.rotation.y = -.9; townWorld.add(merchant.root); townNpcs.push(merchant);

  const board = group(townWorld, 4.8, 0, -2.75);
  for (const x of [-.58, .58]) box(board, .12, 2.0, .13, 0x514a35, x, 1);
  box(board, 1.45, .91, .16, 0x403c2c, 0, 1.5);
  box(board, 1.66, .12, .29, 0x7f7150, 0, 2.02);
  for (let i = 0; i < 3; i++) box(board, .3, .48 - i * .04, .02, i % 2 ? 0x9e946e : 0xb1a17a, -.43 + i * .42, 1.52, .098).rotation.z = (i - 1) * .1;
  obstacle(4.8, -2.75, 1.65, .7);
  const dummy = group(townWorld, -5.3, 0, 4.5);
  cylinder(dummy, .07, .08, 1.9, 0x686043, 0, .95);
  cylinder(dummy, .25, .27, .69, 0x9a8660, 0, 1.26, 0, 6);
  box(dummy, 1.05, .1, .12, 0x786b4e, 0, 1.5);
  cylinder(dummy, .2, .2, .32, 0xb1a078, 0, 1.78, 0, 6);
  box(dummy, .13, .13, .02, 0x594c34, 0, 1.37, .25);
  obstacle(-5.3, 4.5, .8, .8);
  townWorld.userData.dummy = dummy;
  for (const [x, z] of [[-3.6,-5.9],[3.5,-5.9],[-7,3.3],[3.7,4.7]]) candelabra(townWorld, x, z, 1.6, false);
  for (const [x, z] of [[-8.2,-2.7],[-7.5,-2.5],[8.7,-2.6],[8.6,4.5],[-7.8,6.6]]) crate(townWorld, x, z);
  for (const [x, z, s] of [[-9,3.8,1.1],[9,6.5,1.3],[-8,8.4,.9],[8.7,-9,1.2]]) deadTree(townWorld, x, z, s);
  // A foreground fence gives the diorama a miniature, layered silhouette.
  for (const side of [-1, 1]) {
    box(townWorld, 5.5, .13, .2, 0x62634b, side * 5.6, .8, 9.7);
    for (let x = 3; x < 8.5; x += .6) box(townWorld, .06, 1.4, .06, 0x384732, side * x, .65, 9.7);
  }
  for (let i = 0; i < 55; i++) {
    const x = (random() - .5) * 20, z = (random() - .5) * 19;
    if (Math.abs(x) < 2.8) continue;
    const rock = box(townWorld, .09 + random() * .22, .06, .1 + random() * .18, i % 3 ? 0x666b50 : 0x344f32, x, .02, z);
    rock.rotation.y = random() * TAU;
  }
  for (let i = 0; i < 3; i++) makeFog(townWorld, 29, .1 + .28 * i, .075);
  motes.push(makeMotes(townWorld, 95, 23, 0xc2b786));
  addPoi('smith', '铁匠铺', '⚒', [-6, 2.7, -2.3], [-5.7, -1.45], smithDialog);
  addPoi('board', '告示板', '!', [4.8, 2.7, -2.75], [4.7, -1.55], boardDialog);
  addPoi('shrine', '余火祭坛', '✦', [0, 2.6, 0], [0, 2], shrineDialog);
  addPoi('merchant', '药剂商', '+', [6.4, 2.6, 1.3], [5.0, 1.8], merchantDialog);
  addPoi('dummy', '训练木桩', '†', [-5.3, 2.6, 4.5], [-4.15, 4.6], dummyDialog);
  addPoi('gate', '深渊之门', '◇', [0, 4.3, -7.5], [0, -6.4], gateDialog);
  const locations = [[-3.2, 3.35], [3.2, 5.7], [2.2, -4.7]];
  locations.forEach(([x, z], i) => {
    const crystal = group(townWorld, x, .55, z);
    crystal.userData.dynamic = true;
    const center = mesh(crystal, new THREE.OctahedronGeometry(.19), mat(0xe6b161, { emissive: 0xd8862e, emissiveIntensity: 1.2 }));
    center.scale.y = 1.8;
    const ring = mesh(crystal, new THREE.TorusGeometry(.32, .015, 3, 16), mat(0xbe9247), 0, -.43);
    ring.rotation.x = -Math.PI / 2;
    collectibleMeshes.set(`ember${i}`, crystal);
    addPoi(`ember${i}`, '拾取余火', '·', [x, 1.35, z], [x, z], () => collectEmber(`ember${i}`), 'ember');
  });
}
createTown();

// ----------------------- DUNGEON I: THE FALLEN CHAPEL -----------------------
const dungeonPlayerPos = new THREE.Vector3(0, .05, 9);
const dungeonObstacles = [];
const enemies = [];
const projectiles = [];
const dungeonExit = new THREE.Vector3(0, .05, -11);
function dObstacle(x, z, w, d) { dungeonObstacles.push({ x, z, w: w / 2, d: d / 2 }); }
function dungeonWalkable(x, z) {
  if (x < -9.5 || x > 9.5 || z < -11.5 || z > 11.5) return false;
  return !dungeonObstacles.some(o => Math.abs(x - o.x) < o.w + .32 && Math.abs(z - o.z) < o.d + .32);
}
const dungeonGrid = { min: -11, step: .4, count: 56 };
function dGridIndex(x, z) {
  const gx = clamp(Math.round((x - dungeonGrid.min) / dungeonGrid.step), 0, dungeonGrid.count - 1);
  const gz = clamp(Math.round((z - dungeonGrid.min) / dungeonGrid.step), 0, dungeonGrid.count - 1);
  return gz * dungeonGrid.count + gx;
}
const dungeonGridArray = Array.from({ length: dungeonGrid.count * dungeonGrid.count }, () => true);

function createDungeon() {
  // Stone floor.
  tiledFloor(dungeonWorld, 22, -.15);
  // Outer walls.
  for (const side of [-1, 1]) {
    for (let z = -11; z <= 11; z += 1.6) {
      box(dungeonWorld, .6, 4.2, 1.4, 0x3a4138, side * 9.7, 2, z);
      box(dungeonWorld, .5, .4, 1.6, 0x5a5541, side * 9.8, 4.1, z);
    }
  }
  for (let x = -9; x <= 9; x += 1.6) {
    box(dungeonWorld, 1.6, 4.2, .6, 0x3a4138, x, 2, -11.3);
    box(dungeonWorld, 1.6, .4, .5, 0x5a5541, x, 4.1, -11.3);
    box(dungeonWorld, 1.6, 4.2, .6, 0x3a4138, x, 2, 11.3);
  }
  // Central nave pillars.
  for (const side of [-1, 1]) {
    for (const z of [-6, -2, 2, 6]) {
      pillar(dungeonWorld, side * 3.6, z, 4.2);
      dObstacle(side * 3.6, z, 1.1, 1.1);
    }
  }
  // Pews along the sides.
  for (const side of [-1, 1]) {
    for (let z = -7; z <= 7; z += 2.4) {
      const pew = box(dungeonWorld, 2.2, .55, .55, 0x3f3a2c, side * 6.8, .28, z);
      dObstacle(side * 6.8, z, 2.2, .55);
    }
  }
  // Rubble.
  for (let i = 0; i < 18; i++) {
    const x = (random() - .5) * 16, z = (random() - .5) * 18;
    if (Math.abs(x) > 3 && Math.abs(x) < 6) continue;
    const r = box(dungeonWorld, .2 + random() * .5, .12 + random() * .25, .2 + random() * .5, stoneColors[i % 6], x, .05, z);
    r.rotation.y = random() * TAU;
  }
  // Altar at the far end (boss dais).
  const altar = group(dungeonWorld, 0, 0, -9.5);
  box(altar, 3, .6, 1.6, 0x4c4633, 0, .3);
  box(altar, 2.6, .25, 1.2, 0x6b6144, 0, .72);
  const altarFlame = mesh(altar, new THREE.OctahedronGeometry(.28), warmMaterial, 0, 1.1, 0, false);
  flames.push({ mesh: altarFlame, phase: 0, base: 2 });
  const altarLight = new THREE.PointLight(0xff8a3c, 18, 9, 2); altarLight.position.set(0, 1.5, -9.5);
  dungeonWorld.add(altarLight); flames.push({ light: altarLight, intensity: 18, phase: 0 });
  dObstacle(0, -9.5, 3, 1.6);
  // Iron candelabras.
  for (const [x, z] of [[-5, -9], [5, -9], [-5, 9], [5, 9]]) candelabra(dungeonWorld, x, z, 1.7, true);
  // Exit marker (iron gate behind player).
  const gate = group(dungeonWorld, 0, 0, 10.8);
  for (const x of [-1.3, 0, 1.3]) box(gate, .12, 3.2, .12, 0x444030, x, 1.6);
  box(gate, 3, .12, .16, 0x6b6144, 0, 3.1);
  // Fog and dust.
  for (let i = 0; i < 4; i++) makeFog(dungeonWorld, 22, .12 + i * .3, .09);
  motes.push(makeMotes(dungeonWorld, 70, 18, 0x9fb08a));
}
createDungeon();

// Enemy: "Whisperer" — hunched hooded cultist.
function createEnemy(x, z) {
  const root = new THREE.Group();
  root.position.set(x, 0, z);
  root.userData.dynamic = true;
  const rig = group(root);
  const torso = group(rig, 0, 1.25, 0);
  torso.rotation.x = .32;
  const body = cylinder(torso, .42, .5, .78, 0x2b2230, 0, .05, 0, 6);
  box(torso, .66, .4, .45, 0x3a2d40, 0, .18, .02);
  const hood = cylinder(torso, .34, .46, .5, 0x241a2c, 0, .52, -.02, 5);
  const head = group(torso, 0, .5, .06);
  box(head, .34, .3, .3, 0x8a7a8c, 0, 0, .02);
  for (const side of [-1, 1]) box(head, .06, .05, .04, 0xff5b3c, side * .1, -.02, .17);
  const arms = {}, legs = {};
  for (const [name, side] of [['left', -1], ['right', 1]]) {
    const upper = group(torso, side * .42, .12, 0);
    box(upper, .2, .5, .22, 0x2b2230, 0, -.22);
    const lower = group(upper, 0, -.48, 0);
    box(lower, .19, .46, .21, 0x241a2c, 0, -.2);
    // Claw hands.
    for (let i = 0; i < 3; i++) box(lower, .02, .18, .02, 0xd8c2a0, (i - 1) * .05, -.55, .05).rotation.x = .4;
    arms[name] = { upper, lower };
    const thigh = group(rig, side * .2, .85, 0);
    box(thigh, .22, .5, .24, 0x1f1824, 0, -.22);
    const knee = group(thigh, 0, -.5, 0);
    box(knee, .22, .5, .24, 0x1a141e, 0, -.22);
    legs[name] = { thigh, knee };
  }
  // Glowing eye + hitbox.
  const hitMesh = box(root, 1, 2.2, 1, 0xff0000, 0, 1.1, 0);
  hitMesh.material = mat(0xff0000, { transparent: true, opacity: 0, depthWrite: false });
  hitMesh.userData.enemy = null;
  const eye = new THREE.PointLight(0xff6a4a, 6, 3, 2); eye.position.set(0, 1.62, .18); root.add(eye);
  const hpBarBg = new THREE.Mesh(new THREE.PlaneGeometry(.9, .1), mat(0x181018, { transparent: true, depthWrite: false }));
  const hpBar = new THREE.Mesh(new THREE.PlaneGeometry(.86, .06), mat(0xe05a4a, { transparent: true, depthWrite: false }));
  hpBarBg.position.y = 2.35; hpBar.position.y = 2.35; hpBarBg.position.z = .35; hpBar.position.z = .36;
  root.add(hpBarBg, hpBar);
  root.userData.dynamic = true;
  const enemy = {
    root, torso, arms, legs, head, hitMesh, eye, hpBar, hpBarBg,
    hp: 60, maxHp: 60, alive: true,
    position: root.position, yaw: 0, state: 'idle', stateTime: 0,
    attackCooldown: 0, hitFlash: 0,
  };
  hitMesh.userData.enemy = enemy;
  dungeonWorld.add(root);
  return enemy;
}

function spawnEnemies() {
  const positions = [[-4, 0], [4, 0], [-3.5, -5], [3.5, -5]];
  for (const [x, z] of positions) {
    const e = createEnemy(x, z);
    enemies.push(e);
  }
}

function resetDungeon() {
  while (enemies.length) { const e = enemies.pop(); e.root.removeFromParent(); }
  spawnEnemies();
  dungeonPlayerPos.set(0, .05, 9);
  playerYaw = Math.PI;
  for (const p of projectiles) p.mesh.removeFromParent();
  projectiles.length = 0;
  state.lockedEnemy = null;
  updateDungeonHud();
}

function updateDungeonHud() {
  $('#enemy-count').textContent = `${enemies.filter(e => e.alive).length} / ${enemies.length || 4}`;
  $('#dungeon-health-bar').style.width = `${save.hp}%`;
  $('#dungeon-health-text').textContent = `${save.hp} / 100`;
  $('#dungeon-potion-count').textContent = save.potions;
}

function setDungeonPath(target) {
  if (state.mode !== 'dungeon') return;
  // Simple direct move (no full A* needed for this level).
  state.destination = new THREE.Vector3(target.x, 0, target.z);
  state.path = [state.destination.clone()];
  moveMarker.position.copy(target); moveMarker.position.y = .02; moveMarker.visible = true;
}

function lockEnemy(enemy) {
  state.lockedEnemy = enemy;
  toast(`锁定：低语者`);
}

function playerAttack() {
  if (state.mode !== 'dungeon' || state.attacking || state.attackCooldown > 0 || state.switchingScene) return;
  state.attacking = true; state.attackTime = 0; state.attackHit = false;
  playTone(state.selected === 'archer' ? 520 : 90, .18);
}

function spawnArrow(from, target) {
  const arrow = box(dungeonWorld, .7, .03, .03, 0xd7c594);
  arrow.position.copy(from);
  const dir = target.clone().sub(from); dir.y = 0;
  arrow.userData.dir = dir.normalize();
  arrow.userData.life = 1.2;
  arrow.userData.damage = 14 + save.upgrade * 4;
  arrow.lookAt(from.clone().add(arrow.userData.dir));
  arrow.rotation.y += Math.PI / 2;
  projectiles.push({ mesh: arrow, damage: arrow.userData.damage, life: 1.2, dir: arrow.userData.dir, from: 'player' });
}

function doPlayerDamage() {
  const archer = state.selected === 'archer';
  const damage = (archer ? 14 : 22) + save.upgrade * 4;
  if (archer) {
    const from = characters[state.selected].root.position.clone(); from.y = 1.3;
    let target = state.lockedEnemy && state.lockedEnemy.alive ? state.lockedEnemy.root.position.clone() : null;
    if (!target) {
      // Fire in facing direction; find nearest enemy in front.
      const fwd = new THREE.Vector3(Math.sin(playerYaw), 0, Math.cos(playerYaw));
      let best = null, bestDot = .3;
      for (const e of enemies) {
        if (!e.alive) continue;
        const to = e.root.position.clone().sub(from); to.y = 0;
        const d = to.normalize().dot(fwd);
        if (d > bestDot) { bestDot = d; best = e.root.position.clone(); }
      }
      target = best || from.clone().add(fwd.multiplyScalar(8));
    }
    target.y = 1.3;
    spawnArrow(from, target);
  } else {
    // Melee arc in front.
    const fwd = new THREE.Vector3(Math.sin(playerYaw), 0, Math.cos(playerYaw));
    const origin = characters[state.selected].root.position.clone();
    for (const e of enemies) {
      if (!e.alive) continue;
      const to = e.root.position.clone().sub(origin); to.y = 0;
      const dist = to.length();
      if (dist < 2.1 && to.normalize().dot(fwd) > .2) damageEnemy(e, damage);
    }
    // Ground impact puff.
    const puff = mesh(dungeonWorld, new THREE.SphereGeometry(.3, 6, 4), mat(0xb9a77a, { transparent: true, opacity: .5, depthWrite: false }),
      origin.x + fwd.x * 1.4, .2, origin.z + fwd.z * 1.4, false);
    puff.userData.life = .35; puff.userData.kind = 'puff'; projectiles.push({ mesh: puff, life: .35 });
  }
}

function damageEnemy(enemy, damage) {
  if (!enemy.alive) return;
  enemy.hp -= damage; enemy.hitFlash = .18;
  enemy.hpBar.scale.x = Math.max(0, enemy.hp / enemy.maxHp);
  enemy.hpBar.position.x = -(1 - enemy.hpBar.scale.x) * .43;
  // Hit spark.
  const spark = mesh(dungeonWorld, new THREE.OctahedronGeometry(.16), mat(0xffcf6a, { emissive: 0xffb347, emissiveIntensity: 2, transparent: true, opacity: .9, depthWrite: false }),
    enemy.root.position.x, 1.4 + Math.random() * .3, enemy.root.position.z, false);
  spark.userData.life = .3; spark.userData.kind = 'spark'; projectiles.push({ mesh: spark, life: .3 });
  playTone(220, .1, .05);
  if (enemy.hp <= 0) {
    enemy.alive = false;
    enemy.root.visible = false;
    enemy.hitMesh.visible = false;
    if (state.lockedEnemy === enemy) state.lockedEnemy = null;
    const left = enemies.filter(e => e.alive).length;
    updateDungeonHud();
    if (left === 0) {
      save.gold += 90; persist(); updateHud();
      toast('圣堂已净化 · +90 余烬币。按 E 或点击「撤离圣堂」返回庇护所。');
      openDialog('圣堂已净化', '<p>低语者的呢喃终于消散。祭坛的火光重新亮起，通往庇护所的门已开启。</p>', [
        { label: '撤离圣堂', run: () => { closeDialog(); exitDungeon(); } },
      ], 'CHAPTER I · CLEARED');
    } else {
      toast(`低语者倒下 · 剩余 ${left}`);
    }
  }
}

function enemyAttack(enemy) {
  // Simple melee hit if close.
  const dist = enemy.root.position.distanceTo(dungeonPlayerPos);
  if (dist < 1.9) {
    save.hp = Math.max(0, save.hp - 7);
    updateDungeonHud(); updateHud();
    flashHit();
    playTone(140, .18, .07);
    if (save.hp <= 0) {
      save.hp = 100; persist(); updateDungeonHud(); updateHud();
      toast('你倒在了圣堂中……被余火送回庇护所。');
      exitDungeon();
    }
  }
}

function flashHit() {
  const f = $('#hit-flash'); f.classList.add('show');
  setTimeout(() => f.classList.remove('show'), 110);
}

function updateDungeon(dt) {
  const active = characters[state.selected];
  // Player movement in dungeon.
  const velocity = new THREE.Vector3();
  const up = keys.has('w') || keys.has('arrowup'), down = keys.has('s') || keys.has('arrowdown');
  const left = keys.has('a') || keys.has('arrowleft'), right = keys.has('d') || keys.has('arrowright');
  if (up || down || left || right) {
    state.path = []; state.destination = null; moveMarker.visible = false;
    // Camera-relative movement.
    const forward = new THREE.Vector3(-Math.sin(state.camYaw), 0, -Math.cos(state.camYaw));
    const rightV = new THREE.Vector3(Math.cos(state.camYaw), 0, -Math.sin(state.camYaw));
    velocity.addScaledVector(forward, Number(up) - Number(down));
    velocity.addScaledVector(rightV, Number(right) - Number(left));
  } else if (state.path.length) {
    const wp = state.path[0];
    if (dungeonPlayerPos.distanceTo(wp) < .12) state.path.shift();
    else velocity.subVectors(wp, dungeonPlayerPos);
  }
  if (velocity.lengthSq() > .001 && !state.attacking) {
    const speed = CLASS_DATA[state.selected].walkSpeed * (keys.has('shift') ? 1.5 : 1);
    velocity.normalize().multiplyScalar(Math.min(speed * dt, state.path.length ? velocity.length() : Infinity));
    const nx = dungeonPlayerPos.x + velocity.x, nz = dungeonPlayerPos.z + velocity.z;
    if (dungeonWalkable(nx, dungeonPlayerPos.z)) dungeonPlayerPos.x = nx;
    if (dungeonWalkable(dungeonPlayerPos.x, nz)) dungeonPlayerPos.z = nz;
    const targetYaw = Math.atan2(velocity.x, velocity.z);
    playerYaw += Math.atan2(Math.sin(targetYaw - playerYaw), Math.cos(targetYaw - playerYaw)) * Math.min(1, dt * 14);
    state.walkPhase += velocity.length() * 11;
    state.moving = true;
  } else {
    state.moving = false;
  }
  active.root.position.copy(dungeonPlayerPos);
  // Face locked enemy if present.
  if (state.lockedEnemy && state.lockedEnemy.alive) {
    const to = state.lockedEnemy.root.position.clone().sub(dungeonPlayerPos);
    const targetYaw = Math.atan2(to.x, to.z);
    playerYaw += Math.atan2(Math.sin(targetYaw - playerYaw), Math.cos(targetYaw - playerYaw)) * Math.min(1, dt * 10);
  }
  active.root.rotation.y = playerYaw;
  const pose = state.attacking ? { type: 'attack', time: state.attackTime }
    : state.moving ? { type: 'walk', step: state.walkPhase } : { type: 'idle' };
  active.update(dt, state.time, pose);

  // Attack timeline.
  if (state.attacking) {
    state.attackTime += dt;
    const archer = state.selected === 'archer';
    const hitTime = archer ? .5 : .55;
    if (!state.attackHit && state.attackTime >= hitTime) {
      state.attackHit = true; doPlayerDamage();
    }
    const duration = archer ? .85 : .8;
    if (state.attackTime >= duration) {
      state.attacking = false; state.attackCooldown = archer ? .15 : .25;
    }
  } else if (state.attackCooldown > 0) {
    state.attackCooldown -= dt;
  }

  // Enemies AI.
  for (const e of enemies) {
    if (!e.alive) continue;
    e.stateTime += dt;
    e.attackCooldown -= dt;
    if (e.hitFlash > 0) e.hitFlash -= dt;
    const toPlayer = dungeonPlayerPos.clone().sub(e.root.position); toPlayer.y = 0;
    const dist = toPlayer.length();
    const targetYaw = Math.atan2(toPlayer.x, toPlayer.z);
    e.yaw += Math.atan2(Math.sin(targetYaw - e.yaw), Math.cos(targetYaw - e.yaw)) * Math.min(1, dt * 6);
    e.root.rotation.y = e.yaw;
    if (dist > 1.6) {
      const step = Math.min(1.4 * dt, dist - 1.4);
      toPlayer.normalize().multiplyScalar(step);
      const nx = e.root.position.x + toPlayer.x, nz = e.root.position.z + toPlayer.z;
      if (dungeonWalkable(nx, nz)) {
        e.root.position.set(nx, 0, nz);
      } else if (dungeonWalkable(e.root.position.x + toPlayer.x, e.root.position.z)) {
        e.root.position.x += toPlayer.x;          // slide along z-axis obstacle
      } else if (dungeonWalkable(e.root.position.x, e.root.position.z + toPlayer.z)) {
        e.root.position.z += toPlayer.z;          // slide along x-axis obstacle
      }
      e.state = 'chase';
      e.arms.left.upper.rotation.x = Math.sin(e.stateTime * 8) * .4;
      e.arms.right.upper.rotation.x = -Math.sin(e.stateTime * 8) * .4;
    } else {
      e.state = 'attack';
      e.arms.left.upper.rotation.x = -1.1 + Math.sin(e.stateTime * 10) * .15;
      e.arms.right.upper.rotation.x = -1.1 - Math.sin(e.stateTime * 10) * .15;
      if (e.attackCooldown <= 0) { enemyAttack(e); e.attackCooldown = 1.1; }
    }
    // Hit flash.
    e.root.traverse(o => {
      if (o.material && o.material.emissive) {
        o.material.emissiveIntensity = e.hitFlash > 0 ? 1.2 : 0;
        o.material.emissive = new THREE.Color(0xff5533);
      }
    });
    // Billboard HP bar.
    e.hpBarBg.lookAt(camera.position); e.hpBar.lookAt(camera.position);
    e.eye.intensity = e.state === 'attack' ? 8 : 5;
  }

  // Projectiles (arrows, sparks, puffs).
  for (let i = projectiles.length - 1; i >= 0; i--) {
    const p = projectiles[i];
    p.life -= dt;
    if (p.dir && p.from === 'player') {
      p.mesh.position.addScaledVector(p.dir, 18 * dt);
      p.mesh.rotation.z += dt * 30;
      for (const e of enemies) {
        if (!e.alive) continue;
        if (p.mesh.position.distanceTo(e.root.position.clone().setY(p.mesh.position.y)) < 1.0) {
          damageEnemy(e, p.damage);
          p.life = 0; break;
        }
      }
    } else if (p.mesh.userData.kind === 'spark' || p.mesh.userData.kind === 'puff') {
      p.mesh.scale.multiplyScalar(1 + dt * 6);
      p.mesh.material.opacity = Math.max(0, p.life / .35);
    }
    if (p.life <= 0) { p.mesh.removeFromParent(); projectiles.splice(i, 1); }
  }
}

function exitDungeon() {
  if (state.mode !== 'dungeon' || state.switchingScene) return;
  changeScene('town');
}

// Hook up dungeon UI buttons.
$('#dungeon-exit').addEventListener('click', exitDungeon);
$('#dungeon-potion').addEventListener('click', usePotion);
$('#touch-attack').addEventListener('click', playerAttack);

// Make the town gate open the dungeon once the ember quest is complete.

// Bake immutable architecture by material. Dynamic rigs, flame geometry, fog
// and pickups retain their own transforms. This cuts hundreds of draw calls.
function batchArchitecture(world) {
  world.updateMatrixWorld(true);
  const animated = new Set(flames.filter(f => f.mesh).map(f => f.mesh));
  const batches = new Map(), originals = [];
  world.traverse(object => {
    if (!object.isMesh || object.isInstancedMesh || Array.isArray(object.material) || object.material.transparent || animated.has(object)) return;
    for (let parent = object; parent && parent !== world; parent = parent.parent) if (parent.userData.dynamic) return;
    const geometry = object.geometry.index ? object.geometry.toNonIndexed() : object.geometry.clone();
    geometry.applyMatrix4(object.matrixWorld);
    const key = `${object.material.id}-${object.castShadow}-${object.receiveShadow}`;
    if (!batches.has(key)) batches.set(key, { material: object.material, shadows: [object.castShadow, object.receiveShadow], geometries: [] });
    batches.get(key).geometries.push(geometry); originals.push(object);
  });
  for (const object of originals) object.removeFromParent();
  for (const batch of batches.values()) {
    const geometry = new THREE.BufferGeometry();
    for (const [attribute, size] of [['position', 3], ['normal', 3], ['uv', 2]]) {
      const length = batch.geometries.reduce((sum, g) => sum + g.attributes[attribute].array.length, 0);
      const values = new Float32Array(length); let offset = 0;
      for (const source of batch.geometries) { const array = source.attributes[attribute].array; values.set(array, offset); offset += array.length; }
      geometry.setAttribute(attribute, new THREE.BufferAttribute(values, size));
    }
    const combined = new THREE.Mesh(geometry, batch.material);
    [combined.castShadow, combined.receiveShadow] = batch.shadows;
    world.add(combined);
    for (const source of batch.geometries) source.dispose();
  }
}
// The training dummy is animated by interaction and must not be baked.
townWorld.userData.dummy.userData.dynamic = true;
batchArchitecture(selectionWorld);
batchArchitecture(townWorld);
batchArchitecture(dungeonWorld);
const moveMarker = new THREE.Mesh(new THREE.RingGeometry(.18, .23, 20), mat(0xdac08a, {
  transparent: true, opacity: .8, side: THREE.DoubleSide, depthWrite: false,
}));
moveMarker.rotation.x = -Math.PI / 2; moveMarker.visible = false; scene.add(moveMarker);
const playerPosition = new THREE.Vector3(0, .05, 6.5);
let playerYaw = Math.PI;

// A* grid with radius-expanded obstacles; diagonal corner-cutting is forbidden.
const GRID_STEP = .4, GRID_MIN = -9.6, GRID_COUNT = 49, PLAYER_RADIUS = .29;
function walkable(x, z) {
  if (x < -9.3 || x > 9.3 || z < -9.5 || z > 9.1) return false;
  return !obstacles.some(o => Math.abs(x - o.x) < o.w + PLAYER_RADIUS && Math.abs(z - o.z) < o.d + PLAYER_RADIUS);
}
function gridPoint(v) { return clamp(Math.round((v - GRID_MIN) / GRID_STEP), 0, GRID_COUNT - 1); }
function worldPoint(n) { return n * GRID_STEP + GRID_MIN; }
const grid = Array.from({ length: GRID_COUNT * GRID_COUNT }, (_, i) => walkable(worldPoint(i % GRID_COUNT), worldPoint(Math.floor(i / GRID_COUNT))));
function pathfind(start, end) {
  let sx = gridPoint(start.x), sz = gridPoint(start.z), ex = gridPoint(end.x), ez = gridPoint(end.z);
  const index = (x, z) => z * GRID_COUNT + x;
  // Use the nearest walkable cell, for clicks along walls and rounded edges.
  function nearest(x, z) {
    if (grid[index(x, z)]) return [x, z];
    for (let radius = 1; radius <= 5; radius++) {
      let best = null, distance = Infinity;
      for (let dx = -radius; dx <= radius; dx++) for (let dz = -radius; dz <= radius; dz++) {
        const xx = x + dx, zz = z + dz, d = dx * dx + dz * dz;
        if (xx >= 0 && xx < GRID_COUNT && zz >= 0 && zz < GRID_COUNT && grid[index(xx, zz)] && d < distance) { best = [xx, zz]; distance = d; }
      }
      if (best) return best;
    }
    return null;
  }
  const a = nearest(sx, sz), b = nearest(ex, ez); if (!a || !b) return [];
  [sx, sz] = a; [ex, ez] = b;
  const startId = index(sx, sz), endId = index(ex, ez);
  const open = [startId], closed = new Set(), previous = new Map(), cost = new Map([[startId, 0]]);
  const heuristic = id => Math.hypot(id % GRID_COUNT - ex, Math.floor(id / GRID_COUNT) - ez);
  let iterations = 0;
  while (open.length && iterations++ < GRID_COUNT * GRID_COUNT) {
    let best = 0;
    for (let i = 1; i < open.length; i++) if (cost.get(open[i]) + heuristic(open[i]) < cost.get(open[best]) + heuristic(open[best])) best = i;
    const current = open.splice(best, 1)[0];
    if (current === endId) {
      const points = []; let c = current;
      while (c !== startId) {
        points.push(new THREE.Vector3(worldPoint(c % GRID_COUNT), .05, worldPoint(Math.floor(c / GRID_COUNT))));
        c = previous.get(c);
      }
      points.reverse();
      if (!points.length) points.push(new THREE.Vector3(worldPoint(ex), .05, worldPoint(ez)));
      return points;
    }
    closed.add(current);
    const x = current % GRID_COUNT, z = Math.floor(current / GRID_COUNT);
    for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) {
      if (!dx && !dz) continue;
      const nx = x + dx, nz = z + dz;
      if (nx < 0 || nx >= GRID_COUNT || nz < 0 || nz >= GRID_COUNT) continue;
      const next = index(nx, nz);
      if (!grid[next] || closed.has(next)) continue;
      if (dx && dz && (!grid[index(x + dx, z)] || !grid[index(x, z + dz)])) continue;
      const newCost = cost.get(current) + (dx && dz ? Math.SQRT2 : 1);
      if (newCost < (cost.get(next) ?? Infinity)) {
        previous.set(next, current); cost.set(next, newCost);
        if (!open.includes(next)) open.push(next);
      }
    }
  }
  return [];
}
function setPath(target, destination = null) {
  const path = pathfind(playerPosition, target);
  if (!path.length) { toast('那条路已被旧日的残垣封住。'); return false; }
  state.path = path; state.destination = destination;
  moveMarker.position.copy(path[path.length - 1]); moveMarker.position.y = .02; moveMarker.visible = true;
  return true;
}
function travelToPoi(poi) {
  if (state.mode !== 'town' || state.switchingScene || !poiAvailable(poi)) return;
  closeDialog();
  if (playerPosition.distanceTo(poi.destination) < 1.0) { poi.onInteract(); return; }
  if (setPath(poi.destination, poi)) toast(`正在前往${poi.name}…`);
}
function poiAvailable(poi) { return poi.type !== 'ember' || (save.quest === 'active' && !save.embers.includes(poi.id)); }
const keys = new Set();
const forward = new THREE.Vector3(-.6, 0, -.8), right = new THREE.Vector3(.8, 0, -.6);
function updateMovement(dt) {
  const previous = playerPosition.clone();
  const velocity = new THREE.Vector3();
  if (!$('#modal').open && !state.switchingScene) {
    const up = keys.has('w') || keys.has('arrowup'), down = keys.has('s') || keys.has('arrowdown');
    const left = keys.has('a') || keys.has('arrowleft'), r = keys.has('d') || keys.has('arrowright');
    if (up || down || left || r) {
      state.path = []; state.destination = null; moveMarker.visible = false;
      velocity.addScaledVector(forward, Number(up) - Number(down));
      velocity.addScaledVector(right, Number(r) - Number(left));
    } else if (state.path.length) {
      let waypoint = state.path[0];
      if (playerPosition.distanceTo(waypoint) < .09) {
        state.path.shift(); waypoint = state.path[0];
      }
      if (waypoint) velocity.subVectors(waypoint, playerPosition);
      else {
        moveMarker.visible = false;
        const target = state.destination; state.destination = null;
        if (target && playerPosition.distanceTo(target.destination) < 1.3) target.onInteract();
      }
    }
    const remaining = velocity.length();
    if (remaining > .001) {
      const speed = CLASS_DATA[state.selected].walkSpeed * (keys.has('shift') ? 1.6 : 1);
      velocity.normalize().multiplyScalar(Math.min(speed * dt, state.path.length ? remaining : Infinity));
      if (walkable(playerPosition.x + velocity.x, playerPosition.z)) playerPosition.x += velocity.x;
      if (walkable(playerPosition.x, playerPosition.z + velocity.z)) playerPosition.z += velocity.z;
    }
  }
  const moved = playerPosition.distanceTo(previous);
  state.moving = moved > .0005;
  if (state.moving) {
    const direction = playerPosition.clone().sub(previous);
    const targetYaw = Math.atan2(direction.x, direction.z);
    playerYaw += Math.atan2(Math.sin(targetYaw - playerYaw), Math.cos(targetYaw - playerYaw)) * Math.min(1, dt * 14);
    state.walkPhase += moved * 10;
  }
  const active = characters[state.selected];
  active.root.position.copy(playerPosition); active.root.rotation.y = playerYaw;
  active.update(dt, state.time, state.moving ? { type: 'walk', step: state.walkPhase } : { type: 'idle' });
  state.near = null; let distance = 1.5;
  for (const poi of pois) {
    const d = playerPosition.distanceTo(poi.destination);
    if (poiAvailable(poi) && d < distance) { state.near = poi; distance = d; }
  }
  const prompt = $('#interaction-prompt');
  prompt.hidden = !state.near || $('#modal').open;
  if (state.near) prompt.querySelector('span').textContent = state.near.name;
  for (const poi of pois) poi.button.classList.toggle('nearby', state.near === poi);
}

// ----------------------- UI & INTERACTION -----------------------
let toastTimeout, infoTimeout, sceneTimeout, dummyTimeout;
function toast(message) {
  $('#toast').textContent = message; $('#toast').classList.add('show');
  clearTimeout(toastTimeout); toastTimeout = setTimeout(() => $('#toast').classList.remove('show'), 3100);
}
function updateClassUI() {
  const data = CLASS_DATA[state.selected];
  $('#class-name').textContent = data.name;
  $('#class-subtitle').textContent = data.subtitle;
  $('#class-description').textContent = data.description;
  $('#class-tags').replaceChildren(...data.tags.map(tag => { const el = document.createElement('span'); el.textContent = tag; return el; }));
  ['strength', 'agility', 'resilience'].forEach((key, i) => {
    $(`#stat-${key}`).style.setProperty('--value', `${data.stats[i] * 20}%`);
    $(`#value-${key}`).textContent = String(data.stats[i]).padStart(2, '0');
  });
  $('#class-trait').textContent = data.trait;
  $('#trait-description').textContent = data.motto;
  $('#trait-icon use').setAttribute('href', `#i-${data.icon}`);
  $('#player-icon use').setAttribute('href', `#i-${data.icon}`);
  $('#player-name').textContent = data.name;
  $$('.class-card').forEach(button => {
    const selected = button.dataset.class === state.selected;
    button.classList.toggle('selected', selected); button.setAttribute('aria-pressed', String(selected));
  });
}
function requestClass(id) {
  if (state.mode !== 'selection' || state.switchingScene || !CLASS_DATA[id]) return;
  if (state.phase === 'fadingOut' || state.phase === 'fadingIn') { state.pending = id; return; }
  if (id === state.selected) { startShowcase(); return; }
  state.pending = id; state.phase = 'fadingOut'; state.transitionTime = 0;
  $('#animation-status').textContent = '灵魂消散';
  $('#character-info').classList.add('changing');
  playTone(130, .32, .07);
}
function startShowcase() {
  if (state.phase === 'fadingOut' || state.phase === 'fadingIn') return;
  state.phase = 'showcase'; state.showcaseTime = 0;
  $('#animation-status').textContent = state.selected === 'archer' ? '月下引弓' : '余烬之誓';
}
function updateSelection(dt) {
  let active = characters[state.selected];
  active.root.rotation.y = state.yaw;
  if (state.phase === 'fadingOut') {
    state.transitionTime += dt;
    const p = clamp(state.transitionTime / .6, 0, 1);
    active.setOpacity(1 - smooth(p)); updateSmoke(Math.sin(p * Math.PI / 2));
    if (p >= 1) {
      active.root.visible = false;
      state.selected = state.pending; state.pending = null; state.phase = 'fadingIn'; state.transitionTime = 0;
      active = characters[state.selected]; active.root.position.set(0, .47, 0); active.setOpacity(0);
      save.selected = state.selected; persist(); updateClassUI();
      $('#character-info').classList.remove('changing');
      $('#animation-status').textContent = '灵魂凝聚';
    }
  } else if (state.phase === 'fadingIn') {
    state.transitionTime += dt;
    const p = clamp(state.transitionTime / .75, 0, 1);
    active.setOpacity(smooth(p)); updateSmoke(1 - smooth(p));
    if (p >= 1) {
      active.setOpacity(1); state.phase = 'idle'; startShowcase();
      if (state.pending && state.pending !== state.selected) { const next = state.pending; state.pending = null; requestClass(next); }
      else state.pending = null;
    }
  } else {
    updateSmoke(0);
    if (state.phase === 'showcase') {
      state.showcaseTime += dt;
      if (state.showcaseTime >= 4.4) { state.phase = 'idle'; $('#animation-status').textContent = '待机 · 呼吸'; }
    }
  }
  active.update(dt, state.time, state.phase === 'showcase' ? { type: 'showcase', time: state.showcaseTime } : { type: 'idle' });
  $('#game').dataset.state = state.phase;
}
function changeScene(mode) {
  if (mode === state.mode || state.switchingScene) return;
  state.switchingScene = true; keys.clear(); state.path = []; state.destination = null;
  clearTimeout(toastTimeout); $('#toast').classList.remove('show');
  closeDialog(); $('#scene-transition').classList.add('cover');
  sceneTimeout = setTimeout(() => {
    state.mode = mode; state.phase = 'idle'; state.pending = null;
    state.attacking = false; state.attackTime = 0; state.attackCooldown = 0; state.attackHit = false;
    state.lockedEnemy = null;
    const world = mode === 'town' ? townWorld : mode === 'dungeon' ? dungeonWorld : selectionWorld;
    for (const [id, character] of Object.entries(characters)) {
      character.setOpacity(1); character.root.visible = id === state.selected;
      character.root.removeFromParent();
      world.add(character.root);
      character.root.scale.setScalar(mode === 'selection' ? 1 : .85);
      if (mode === 'town') character.root.position.copy(playerPosition);
      else if (mode === 'dungeon') character.root.position.copy(dungeonPlayerPos);
      else character.root.position.set(0, .47, 0);
    }
    updateSmoke(0);
    selectionWorld.visible = mode === 'selection';
    townWorld.visible = mode === 'town';
    dungeonWorld.visible = mode === 'dungeon';
    $('#game').dataset.mode = mode; $('#game').dataset.state = 'idle';
    $('#selection-ui').hidden = mode !== 'selection';
    $('#town-ui').hidden = mode !== 'town';
    $('#dungeon-ui').hidden = mode !== 'dungeon';
    $('#nav-selection').classList.toggle('active', mode === 'selection');
    $('#nav-town').classList.toggle('active', mode === 'town');
    $('#nav-selection').setAttribute('aria-current', mode === 'selection' ? 'page' : 'false');
    $('#nav-town').setAttribute('aria-current', mode === 'town' ? 'page' : 'false');
    $('#footer-place').textContent = mode === 'town' ? '灰烬庇护所 · 本地存档' : mode === 'dungeon' ? '废弃圣堂 · 第一关' : '遗忘圣堂';
    $('#animation-status').textContent = '待机 · 呼吸';
    $('#character-info').classList.remove('changing');
    $('.touch-attack').classList.toggle('show', mode === 'dungeon');
    if (mode === 'dungeon') resetDungeon();
    resetCamera(mode);
    resize(); updateHud();
    $('#scene-transition').classList.remove('cover');
    state.switchingScene = false;
    if (mode === 'town') toast('欢迎来到灰烬庇护所。点击地面或使用 WASD 移动。');
    if (mode === 'dungeon') toast('废弃圣堂：清除所有低语者。空格 / J 攻击。');
  }, 460);
}
function updateHud() {
  $('#gold-count').textContent = save.gold;
  $('#potion-count').textContent = save.potions;
  $('#health-bar').style.width = `${save.hp}%`; $('#health-text').textContent = `${save.hp} / 100`;
  $('#potion-button').disabled = save.potions === 0;
  const active = save.quest === 'active', complete = save.quest === 'complete';
  $('#quest-title').textContent = complete ? '余火重燃' : '庇护所的余火';
  $('#quest-text').textContent = complete ? '祭坛再次燃起。庇护所记住了你的名字。' : active ? '找回散落在城中的三簇余火，带回中央祭坛。' : '前往告示板，听听这座城的请求。';
  $('#quest-progress').textContent = active ? `余火碎片 ${save.embers.length} / 3` : complete ? '✓ 委托已完成 · 获得 60 余烬币' : '';
  $('#track-quest').firstChild.textContent = complete ? '前往深渊之门 ' : active ? save.embers.length === 3 ? '寻路至余火祭坛 ' : '寻找下一簇余火 ' : '寻路至告示板 ';
  for (const [id, object] of collectibleMeshes) object.visible = active && !save.embers.includes(id);
}
function openDialog(title, content, actions = [], eyebrow = 'ASHEN SANCTUARY') {
  keys.clear(); state.path = []; state.destination = null; state.moving = false; moveMarker.visible = false;
  $('#modal-title').textContent = title; $('#modal-content').innerHTML = content;
  $('#modal-eyebrow').textContent = eyebrow; $('#modal-actions').replaceChildren();
  for (const action of actions) {
    const button = document.createElement('button'); button.className = `dialog-action${action.secondary ? ' secondary' : ''}`;
    button.textContent = action.label; button.disabled = Boolean(action.disabled);
    button.addEventListener('click', action.run); $('#modal-actions').appendChild(button);
  }
  if (!$('#modal').open) $('#modal').showModal();
}
function closeDialog() { if ($('#modal').open) $('#modal').close(); keys.clear(); }
function boardDialog() {
  if (save.quest === 'new') openDialog('庇护所的余火', '<p class="dialog-speaker">一张被雨水打湿的告示</p><p>“中央祭坛的火正在变冷。若还有旅人愿意帮忙，请找回散落在广场的 <strong>三簇余火</strong>。”</p><p>收集后前往余火祭坛，可获得 <strong>60 余烬币</strong>，并点亮城中的长夜。</p>', [
    { label: '接下委托', run: () => { if (save.quest !== 'new') return; save.quest = 'active'; persist(); updateHud(); closeDialog(); toast('委托已接取 · 三簇余火已在城中标记。'); playTone(330, .3); } },
    { label: '稍后再来', run: closeDialog, secondary: true },
  ], 'A REQUEST IN THE RAIN');
  else openDialog(save.quest === 'complete' ? '告示板 · 余火已归' : '告示板 · 委托进行中', `<p>${save.quest === 'complete' ? '“谢谢你，陌生人。只要余火还亮着，这里就还是我们的家。”' : `已经找回 <strong>${save.embers.length} / 3</strong> 簇余火。沿城中的金色标记寻找，完成后回到中央祭坛。`}</p>`, [{ label: '继续旅途', run: closeDialog }]);
}
function collectEmber(id) {
  if (save.quest !== 'active' || save.embers.includes(id)) return;
  save.embers.push(id); persist(); updateHud(); playTone(523, .5);
  toast(save.embers.length === 3 ? '三簇余火已集齐。回到祭坛，点亮长夜。' : `余火已拾取 · ${save.embers.length} / 3`);
}
function shrineDialog() {
  const ready = save.quest === 'active' && save.embers.length === 3;
  openDialog('余火祭坛', `<p class="dialog-speaker">石碗中传来微弱的心跳</p><p>${ready ? '你掌心的碎片与祭坛共鸣。将它们送回火中，让庇护所再次看见黎明。' : save.quest === 'complete' ? '金色的火焰轻轻摇曳。旧神的低语在这里短暂远去，你可以安心歇息。' : '火光微弱，却仍有温度。在此休憩可以恢复所有生命。'}</p>`, [
    ...(ready ? [{ label: '归还余火 · 领取 60 余烬币', run: () => {
      if (save.quest !== 'active' || save.embers.length !== 3) return;
      save.quest = 'complete'; save.gold += 60; save.hp = 100; persist(); updateHud(); closeDialog(); playTone(392, 1);
      toast('余火重燃 · 委托完成 · +60 余烬币');
    } }] : []),
    { label: '在火边休憩', run: () => { save.hp = 100; persist(); updateHud(); closeDialog(); toast('温暖驱散疲惫 · 生命已全部恢复'); } },
    { label: '离开', run: closeDialog, secondary: true },
  ], 'WHERE THE EMBERS REMAIN');
}
function smithDialog() {
  const cost = 30 + save.upgrade * 15;
  openDialog('铁匠 · 霍尔德', `<p class="dialog-speaker">“火还没灭，就有活可干。”</p><p>当前武器：<strong>${state.selected === 'archer' ? '古林长弓' : '旧国战锤'} +${save.upgrade}</strong></p><p>锻造提升训练伤害，每级增加 4 点。${save.upgrade >= 3 ? '这件武器已达到本章锻造上限。' : `下一次锻造需要 <strong>${cost} 余烬币</strong>。`}</p>`, [
    { label: save.upgrade >= 3 ? '已完成全部锻造' : `锻造武器 · ${cost} 币`, disabled: save.upgrade >= 3 || save.gold < cost, run: () => {
      const actualCost = 30 + save.upgrade * 15;
      if (save.upgrade >= 3 || save.gold < actualCost) return;
      save.gold -= actualCost; save.upgrade++; persist(); updateHud(); playTone(164, .2); smithDialog();
      toast(`锻造完成 · 武器 +${save.upgrade}`);
    } },
    { label: '离开铁匠铺', run: closeDialog, secondary: true },
  ], 'THE LAST FORGE');
}
function merchantDialog() {
  openDialog('药剂商 · 莫拉', `<p class="dialog-speaker">“把这个带上，别让夜色带走你。”</p><p>生命药剂恢复 <strong>35 点生命</strong>。可以使用快捷键 <strong>1</strong> 或右下角药剂栏饮用。</p><p>售价 <strong>20 余烬币</strong> · 行囊中已有 ${save.potions} 瓶</p>`, [
    { label: '购买药剂 · 20 币', disabled: save.gold < 20 || save.potions >= 99, run: () => {
      if (save.gold < 20 || save.potions >= 99) return;
      save.gold -= 20; save.potions++; persist(); updateHud(); merchantDialog(); toast('生命药剂已放入行囊。'); playTone(440, .15);
    } },
    { label: '离开', run: closeDialog, secondary: true },
  ], 'A SMALL REMEDY');
}
function usePotion() {
  if ((state.mode !== 'town' && state.mode !== 'dungeon') || state.switchingScene) return;
  if (save.hp >= 100) { toast('生命充盈，无需消耗药剂。'); return; }
  if (!save.potions) { toast('没有生命药剂了，前往药剂商补给。'); return; }
  save.potions--; save.hp = Math.min(100, save.hp + 35); persist();
  if (state.mode === 'dungeon') { updateDungeonHud(); } else { updateHud(); }
  playTone(587, .3); toast('饮下生命药剂 · 恢复 35 点生命');
}
function dummyDialog() {
  openDialog('训练木桩', `<p>磨砺手感，试试你手中的武器。</p><p>本次攻击造成 <strong>${(state.selected === 'archer' ? 12 : 18) + save.upgrade * 4} 点训练伤害</strong>。首次完成三次训练，可获得 <strong>20 余烬币</strong>。</p><p>${save.trainingReward ? '✓ 今日初训奖励已领取' : `训练进度 ${save.trainingHits} / 3`}</p>`, [
    { label: '攻击木桩', run: () => {
      if (!save.trainingReward) {
        save.trainingHits = Math.min(3, save.trainingHits + 1);
        if (save.trainingHits === 3) { save.trainingReward = true; save.gold += 20; }
      }
      persist(); updateHud(); closeDialog();
      const dummy = townWorld.userData.dummy; dummy.rotation.z = -.16;
      clearTimeout(dummyTimeout); dummyTimeout = setTimeout(() => { dummy.rotation.z = 0; }, 200);
      playTone(state.selected === 'archer' ? 280 : 100, .16);
      toast(`命中 · ${(state.selected === 'archer' ? 12 : 18) + save.upgrade * 4} 伤害${save.trainingHits === 3 && save.trainingReward ? ' · 初训已完成' : ` · 训练 ${save.trainingHits}/3`}`);
    } },
    { label: '离开', run: closeDialog, secondary: true },
  ], 'TEMPER YOUR RESOLVE');
}
function gateDialog() {
  const complete = save.quest === 'complete';
  openDialog('深渊之门', `<p>铁门的另一侧，是没有回声的黑暗。</p><p>${complete ? '余火已被点亮。守门人向你颔首，为你推开了第一重封印。' : '守门人低语：“先去照看城中的余火吧，旅人。”'}</p>${complete ? '<p>第一关「废弃圣堂」已开启。清除其中的低语者，可获得 <strong>90 余烬币</strong>。</p>' : ''}`, [
    ...(complete ? [{ label: '进入废弃圣堂', run: () => { closeDialog(); changeScene('dungeon'); } }] : []),
    { label: '留在庇护所', run: closeDialog },
    { label: '回到灵魂之契', run: () => changeScene('selection'), secondary: true },
  ], 'BEYOND THE VEIL');
}
function inventoryDialog() {
  openDialog('旅人的行囊', `<div class="inventory-row"><span>余烬币</span><strong>${save.gold}</strong></div><div class="inventory-row"><span>生命药剂</span><strong>${save.potions} 瓶</strong></div><div class="inventory-row"><span>余火碎片</span><strong>${save.quest === 'complete' ? '已归还' : `${save.embers.length} / 3`}</strong></div><div class="inventory-row"><span>${state.selected === 'archer' ? '古林长弓' : '旧国战锤'}</span><strong>+${save.upgrade}</strong></div><p style="margin-top:14px">旅途进度保存在当前浏览器中。</p>`, [
    { label: '使用生命药剂', disabled: save.potions === 0 || save.hp >= 100, run: () => { usePotion(); inventoryDialog(); } },
    { label: '收起行囊', run: closeDialog, secondary: true },
  ], 'WHAT YOU CARRY');
}
function mapDialog() {
  openDialog('庇护所 · 地图', '<p style="margin-bottom:16px">选择地标，自动寻路前往。途中按方向键可接管移动。</p><div class="map-grid"></div>', [], 'KNOW THESE QUIET STREETS');
  for (const poi of pois.filter(p => p.type === 'place')) {
    const button = document.createElement('button'); button.className = 'map-location';
    button.textContent = `${poi.name}`; const hint = document.createElement('span'); hint.textContent = '自动寻路 ↗'; button.appendChild(hint);
    button.addEventListener('click', () => travelToPoi(poi)); $('.map-grid').appendChild(button);
  }
}
function helpDialog() {
  openDialog('黑暗中的指引', `<div class="help-row"><span>切换职业 / 使用药剂</span><span><kbd>1</kbd> <kbd>2</kbd></span></div><div class="help-row"><span>城中行走</span><span><kbd>W A S D</kbd> / <kbd>↑ ↓ ← →</kbd></span></div><div class="help-row"><span>奔跑 / 与附近目标交互</span><span><kbd>Shift</kbd> / <kbd>E</kbd></span></div><div class="help-row"><span>行囊 / 城镇地图</span><span><kbd>B</kbd> / <kbd>M</kbd></span></div><div class="help-row"><span>关闭窗口 / 暂停</span><span><kbd>Esc</kbd></span></div><p style="margin-top:17px">拖动职业场景旋转角色。主城中点击地面行走，点击地标可自动前往并交互。</p><label class="setting-row">画面像素密度 <select id="quality-setting"><option value="pixel">经典像素</option><option value="fine">精细像素</option></select></label>`, [{ label: '回到旅途', run: closeDialog }], 'A GUIDE FOR THE WANDERER');
  $('#quality-setting').value = save.quality;
  $('#quality-setting').addEventListener('change', e => { save.quality = e.target.value; persist(); resize(); });
}
$('#close-modal').addEventListener('click', closeDialog);
$('#modal').addEventListener('close', () => keys.clear());
$('#modal').addEventListener('click', event => {
  if (event.target !== $('#modal')) return;
  const r = $('#modal').getBoundingClientRect();
  if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) closeDialog();
});
$$('.class-card').forEach(button => button.addEventListener('click', () => requestClass(button.dataset.class)));
$('#replay-animation').addEventListener('click', startShowcase);
$('#nav-town').addEventListener('click', () => changeScene('town'));
$('#enter-town').addEventListener('click', () => changeScene('town'));
$('#nav-selection').addEventListener('click', () => changeScene('selection'));
// Deliberately static, as requested. Town navigation has its own distinct entry.
$('#start-adventure').addEventListener('click', () => console.log('[失落的深渊] 开始冒险', { class: state.selected, name: CLASS_DATA[state.selected].name }));
$('#inventory-button').addEventListener('click', inventoryDialog);
$('#map-button').addEventListener('click', mapDialog);
$('#potion-button').addEventListener('click', usePotion);
$('#help-button').addEventListener('click', helpDialog);
$('#track-quest').addEventListener('click', () => {
  const id = save.quest === 'new' ? 'board' : save.quest === 'complete' ? 'gate' : save.embers.length === 3 ? 'shrine' : ['ember0', 'ember1', 'ember2'].find(id => !save.embers.includes(id));
  travelToPoi(pois.find(p => p.id === id));
});
// Camera rig controls.
$('#camera-reset').addEventListener('click', () => resetCamera());
$$('[data-cam]').forEach(button => button.addEventListener('click', () => {
  const a = button.dataset.cam;
  if (a === 'yaw-left') state.camYaw -= .35;
  else if (a === 'yaw-right') state.camYaw += .35;
  else if (a === 'pitch-up') state.camPitch = clamp(state.camPitch + .2, .12, 1.48);
  else if (a === 'pitch-down') state.camPitch = clamp(state.camPitch - .2, .12, 1.48);
  else if (a === 'zoom-in') state.camDist = clamp(state.camDist * .85, 4, 55);
  else if (a === 'zoom-out') state.camDist = clamp(state.camDist * 1.18, 4, 55);
}));
$$('[data-cam-preset]').forEach(button => button.addEventListener('click', () => setCamPreset(button.dataset.camPreset)));
// Clock toggle (pause / resume day-night).
$('#clock-toggle').addEventListener('click', () => {
  state.dayPaused = !state.dayPaused;
  toast(state.dayPaused ? '时间已暂停' : '时间继续流逝');
});

// Optional ambient audio, generated locally and activated only by a user gesture.
let audioContext, audioMaster;
function initializeAudio() {
  if (audioContext) return;
  const Context = window.AudioContext || window.webkitAudioContext;
  if (!Context) { toast('当前浏览器不支持环境音。'); return; }
  audioContext = new Context(); audioMaster = audioContext.createGain();
  audioMaster.gain.value = 0; audioMaster.connect(audioContext.destination);
  for (const frequency of [55, 82.41, 110.2]) {
    const oscillator = audioContext.createOscillator(), gain = audioContext.createGain();
    oscillator.type = 'sine'; oscillator.frequency.value = frequency; gain.gain.value = .045;
    oscillator.connect(gain); gain.connect(audioMaster); oscillator.start();
  }
}
function playTone(frequency = 330, duration = .2, strength = .06) {
  if (!state.audio || !audioContext) return;
  const oscillator = audioContext.createOscillator(), gain = audioContext.createGain();
  const t = audioContext.currentTime;
  oscillator.type = 'sine'; oscillator.frequency.setValueAtTime(frequency, t);
  oscillator.frequency.exponentialRampToValueAtTime(frequency * .7, t + duration);
  gain.gain.setValueAtTime(0, t); gain.gain.linearRampToValueAtTime(strength, t + .015);
  gain.gain.exponentialRampToValueAtTime(.001, t + duration);
  oscillator.connect(gain); gain.connect(audioMaster); oscillator.start(t); oscillator.stop(t + duration + .02);
  oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
}
$('#sound-toggle').addEventListener('click', async () => {
  try {
    initializeAudio(); if (!audioContext) return; await audioContext.resume();
    state.audio = !state.audio; audioMaster.gain.setTargetAtTime(state.audio ? .65 : 0, audioContext.currentTime, .3);
    $('#sound-toggle').classList.toggle('muted', !state.audio);
    $('#sound-toggle').setAttribute('aria-pressed', String(state.audio));
    $('#sound-toggle').setAttribute('aria-label', state.audio ? '关闭环境音' : '开启环境音');
  } catch { toast('音频暂不可用，请再次点击开启。'); }
});

window.addEventListener('keydown', event => {
  const key = event.key.toLowerCase();
  if (/^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName)) return;
  if ($('#modal').open) return;
  if (['w','a','s','d','arrowup','arrowdown','arrowleft','arrowright',' ','shift','j'].includes(key)) event.preventDefault();
  if (event.repeat && !['w','a','s','d','arrowup','arrowdown','arrowleft','arrowright','shift'].includes(key)) return;
  keys.add(key);
  if (state.switchingScene) return;
  if (key === 'escape') helpDialog();
  if (state.mode === 'selection') {
    if (key === '1') requestClass('archer');
    if (key === '2') requestClass('warrior');
  } else if (state.mode === 'town') {
    if (key === 'e' && state.near) state.near.onInteract();
    if (key === '1') usePotion();
    if (key === 'b') inventoryDialog();
    if (key === 'm') mapDialog();
  } else if (state.mode === 'dungeon') {
    if (key === ' ' || key === 'j') playerAttack();
    if (key === '1') usePotion();
    if (key === 'e') exitDungeon();
  }
});
window.addEventListener('keyup', event => keys.delete(event.key.toLowerCase()));
window.addEventListener('blur', () => { keys.clear(); state.path = []; state.destination = null; });
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { keys.clear(); audioContext?.suspend(); }
  else if (state.audio) audioContext?.resume();
});
$$('[data-move]').forEach(button => {
  button.addEventListener('pointerdown', event => { event.preventDefault(); button.setPointerCapture(event.pointerId); keys.add(button.dataset.move); });
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) button.addEventListener(name, () => keys.delete(button.dataset.move));
});
const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2();
const ground = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
let drag = null;
renderer.domElement.addEventListener('pointerdown', event => {
  if (event.button !== 0 && event.button !== 2) return;
  drag = { x: event.clientX, y: event.clientY, lastX: event.clientX, lastY: event.clientY, distance: 0 };
  renderer.domElement.setPointerCapture(event.pointerId);
});
renderer.domElement.addEventListener('pointermove', event => {
  if (!drag) return;
  const dx = event.clientX - drag.lastX, dy = event.clientY - drag.lastY;
  drag.distance += Math.abs(dx) + Math.abs(dy);
  if (!$('#modal').open) {
    state.camYaw += dx * .005;
    state.camPitch = clamp(state.camPitch + dy * .004, .12, 1.48);
  }
  drag.lastX = event.clientX; drag.lastY = event.clientY;
});
renderer.domElement.addEventListener('pointerup', event => {
  const wasClick = drag && drag.distance < 7;
  if (wasClick && !$('#modal').open && !state.switchingScene) {
    if (state.mode === 'town') {
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
      raycaster.setFromCamera(pointer, camera);
      const target = new THREE.Vector3();
      if (raycaster.ray.intersectPlane(ground, target)) setPath(target);
    } else if (state.mode === 'dungeon') {
      // Click an enemy to lock-on; otherwise move toward the point.
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
      raycaster.setFromCamera(pointer, camera);
      const hits = raycaster.intersectObjects(enemies.filter(e => e.alive).map(e => e.hitMesh), false);
      if (hits.length) lockEnemy(hits[0].object.userData.enemy);
      else {
        const target = new THREE.Vector3();
        if (raycaster.ray.intersectPlane(ground, target)) setDungeonPath(target);
      }
    }
  }
  drag = null;
});
renderer.domElement.addEventListener('contextmenu', e => e.preventDefault());
renderer.domElement.addEventListener('pointercancel', () => { drag = null; });
renderer.domElement.addEventListener('wheel', event => {
  event.preventDefault();
  state.camDist = clamp(state.camDist * (1 + Math.sign(event.deltaY) * .12), 4, 55);
}, { passive: false });

// ----------------------- RENDER LOOP -----------------------
let viewportWidth = innerWidth, viewportHeight = innerHeight;
const cameraTarget = new THREE.Vector3();
function resize() {
  viewportWidth = Math.max(1, innerWidth); viewportHeight = Math.max(1, innerHeight);
  const scale = save.quality === 'fine' ? 1 : .66;
  renderer.setSize(Math.round(viewportWidth * scale), Math.round(viewportHeight * scale), false);
  renderer.domElement.style.width = `${viewportWidth}px`; renderer.domElement.style.height = `${viewportHeight}px`;
  camera.aspect = viewportWidth / viewportHeight;
  camera.updateProjectionMatrix();
  updateCamera();
}
// Free orbit camera. Pitch from 0 (straight overhead) to ~1.4 (near ground).
// Yaw rotates around the scene target. Distance controls zoom.
const camPresets = {
  selection: { yaw: .3, pitch: .62, dist: 9, tx: 0, ty: 1.3, tz: 0 },
  town: { yaw: .5, pitch: .75, dist: 22, tx: 0, ty: .9, tz: -1 },
  dungeon: { yaw: 0, pitch: .95, dist: 14, tx: 0, ty: 1.1, tz: 0 },
  low: { pitchOffset: .55, distMul: .72 },
  classic: { pitchOffset: 0, distMul: 1 },
  eye: { pitchOffset: 1.0, distMul: 1.15 },
};
let camPreset = 'classic';
function resetCamera(mode = state.mode) {
  const p = camPresets[mode] || camPresets.town;
  state.camYaw = p.yaw; state.camPitch = p.pitch + (camPresets[camPreset]?.pitchOffset ?? 0);
  state.camDist = p.dist * (camPresets[camPreset]?.distMul ?? 1);
}
function setCamPreset(name) {
  camPreset = name;
  resetCamera();
  $$('[data-cam-preset]').forEach(b => b.classList.toggle('active', b.dataset.camPreset === name));
}
function updateCamera() {
  const breath = reducedMotion ? 0 : Math.sin(state.time * .45) * .06;
  const p = camPresets[state.mode] || camPresets.town;
  let tx = p.tx, ty = p.ty, tz = p.tz;
  if (state.mode === 'town') {
    tx += playerPosition.x * .35; tz += playerPosition.z * .35;
  } else if (state.mode === 'dungeon') {
    tx += playerPosition.x * .5; tz += playerPosition.z * .5;
  }
  cameraTarget.set(tx, ty, tz);
  const pitch = clamp(state.camPitch, .12, 1.48);
  const dist = clamp(state.camDist, 4, 55);
  const x = Math.sin(state.camYaw) * Math.cos(pitch) * dist;
  const y = Math.sin(pitch) * dist + breath;
  const z = Math.cos(state.camYaw) * Math.cos(pitch) * dist;
  camera.position.set(tx + x, ty + y, tz + z);
  camera.lookAt(cameraTarget);
  camera.updateMatrixWorld();
}
function updateLabels() {
  if (state.mode !== 'town') return;
  for (const poi of pois) {
    const visible = poiAvailable(poi);
    poi.button.hidden = !visible; if (!visible) continue;
    const projected = poi.position.clone().project(camera);
    const x = (projected.x * .5 + .5) * viewportWidth, y = (-projected.y * .5 + .5) * viewportHeight;
    poi.button.style.left = `${x}px`; poi.button.style.top = `${y}px`;
    poi.button.style.visibility = projected.z < 1 && x > 0 && x < viewportWidth && y > 80 && y < viewportHeight - 50 ? 'visible' : 'hidden';
  }
}
function updateAtmosphere(dt) {
  for (const f of flames) {
    const flicker = 1 + Math.sin(state.time * 6.4 + f.phase) * .07 + Math.sin(state.time * 11.7 + f.phase) * .06;
    const shrinePower = f.shrine && save.quest !== 'complete' ? .5 : 1;
    if (f.mesh) {
      f.mesh.scale.y = f.base * flicker * shrinePower;
      f.mesh.rotation.y += dt * .4;
    }
    if (f.light) f.light.intensity = f.intensity * flicker * shrinePower;
  }
  for (const fog of fogs) fog.uniforms.time.value = state.time;
  for (const cloud of motes) {
    if (!cloud.points.parent.visible) continue;
    const positions = cloud.points.geometry.attributes.position;
    cloud.seeds.forEach((s, i) => {
      positions.setXYZ(i, s[0] + Math.sin(state.time * .17 + s[3]) * .3, (s[1] + state.time * .065) % 7, s[2] + Math.cos(state.time * .13 + s[3]) * .2);
    });
    positions.needsUpdate = true;
  }
  for (const crystal of collectibleMeshes.values()) {
    if (!crystal.visible) continue;
    crystal.children[0].rotation.y += dt; crystal.children[0].position.y = Math.sin(state.time * 2 + crystal.position.x) * .09;
  }
  if (moveMarker.visible) moveMarker.scale.setScalar(1 + Math.sin(state.time * 6) * .15);
}
let lastTime = performance.now(), firstFrame = true;
function animate(now) {
  requestAnimationFrame(animate);
  const dt = Math.min((now - lastTime) / 1000, .05); lastTime = now;
  if (document.hidden) return;
  const paused = $('#modal').open;
  if (!paused) state.time += dt;
  updateDayNight(paused ? 0 : dt);
  updateCamera();
  if (state.mode === 'selection') { if (!paused) updateSelection(dt); }
  else if (state.mode === 'town') {
    updateMovement(paused ? 0 : dt); updateLabels();
    if (!paused) for (const npc of townNpcs) npc.update(dt, state.time + 1, { type: 'idle' });
    $('#game').dataset.state = paused ? 'paused' : state.moving ? 'walking' : 'idle';
  } else {
    if (!paused) updateDungeon(dt);
    $('#game').dataset.state = paused ? 'paused' : state.attacking ? 'attack' : state.moving ? 'walking' : 'idle';
  }
  if (!paused) updateAtmosphere(dt);
  renderer.render(scene, camera);
  if (firstFrame) {
    firstFrame = false;
    $('#loading').classList.add('loaded'); $('#animation-status').textContent = '待机 · 呼吸';
    if (storageNotice) toast(storageNotice);
  }
}
window.addEventListener('resize', resize);
renderer.domElement.addEventListener('webglcontextlost', event => {
  event.preventDefault(); $('#loading').classList.remove('loaded');
  $('#loading-message').textContent = '图形上下文已暂停。请刷新页面恢复，城镇进度已保存在本地。';
});
// Read-only public diagnostics make integration and performance checks inspectable.
window.abyss = Object.freeze({
  getSnapshot: () => ({
    mode: state.mode, phase: state.phase, selected: state.selected,
    showcaseTime: +state.showcaseTime.toFixed(2),
    visibleCharacters: Object.entries(characters).filter(([, character]) => character.root.visible).map(([id]) => id),
    position: { x: +playerPosition.x.toFixed(2), z: +playerPosition.z.toFixed(2) },
    moving: state.moving, pathLength: state.path.length, near: state.near?.id ?? null,
    dayTime: +state.dayTime.toFixed(2), dayPaused: state.dayPaused, daySpeed: state.daySpeed,
    attacking: state.mode === 'dungeon' ? state.attacking : false,
    enemiesAlive: state.mode === 'dungeon' ? enemies.filter(e => e.hp > 0).length : 0,
    enemies: state.mode === 'dungeon' ? enemies.map(e => ({ x: +e.root.position.x.toFixed(1), z: +e.root.position.z.toFixed(1), hp: e.hp, alive: e.alive })) : [],
    save: structuredClone(save), audio: state.audio, storageAvailable,
    renderer: { calls: renderer.info.render.calls, triangles: renderer.info.render.triangles },
  }),
});
updateClassUI(); updateHud(); resize(); requestAnimationFrame(animate);
