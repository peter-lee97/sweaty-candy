export const CONFIG = {
  tickRate: 60,
  tickDelta: 1 / 60,
  arenaHalfSize: 1400,
  player: { moveSpeed: 300, maxHealth: 100, halfExtent: 14, knockbackForce: 300 },
  projectile: { speed: 500, damage: 25, cooldown: 0.4, hitRadius: 18, radius: 4, lifetime: 3.0, subStep: 4 },
  enemy: { hitRate: 0.5, contactRadius: 28, knockbackForce: 400 },
  wave: { delay: 3.0, spawnStagger: 0.35, startCountdown: 5.0, maxEnemies: 100, playerScale: 0.5 },
  respawn: { base: 5.0, perWave: 0.5, max: 10.0 },
  pickup: { dropChance: 0.15, heal: 25, lifetime: 10.0, radius: 24 },
  difficulty: { hpPerWave: 0.05, speedPerWave: 0.015, speedMax: 1.5 },
  net: {
    renderDelay: 0.15,
    reconcileSnap: 40,
    reconcileBlend: 0.25,
    ghostTimeout: 0.5,
    pingInterval: 1.0
  }
};

export const ENEMY_TYPES = {
  base: { hp: 50, speed: 125, damage: 10, score: 100, size: 28, half: 14, color: "#e5313a" },
  fast: { hp: 25, speed: 250, damage: 8, score: 150, size: 20, half: 10, color: "#ff8c1a" },
  tank: { hp: 150, speed: 70, damage: 20, score: 200, size: 36, half: 18, color: "#9a33d1" }
};

export const MAP = {
  halfSize: 1400,
  obstacleHeight: 70,
  obstacles: [
    { x: 0, y: 0, w: 800, h: 40 },
    { x: -400, y: 500, w: 600, h: 40 },
    { x: 400, y: -500, w: 600, h: 40 },
    { x: -1000, y: -1000, w: 140, h: 140 },
    { x: 1000, y: -1000, w: 140, h: 140 },
    { x: -1000, y: 1000, w: 140, h: 140 },
    { x: 1000, y: 1000, w: 140, h: 140 }
  ],
  playerSpawns: [
    [-400, -400],
    [400, -400],
    [-400, 400],
    [400, 400]
  ]
};

export function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function difficultyHpMultiplier(wave) {
  return 1 + (wave - 1) * CONFIG.difficulty.hpPerWave;
}

export function difficultySpeedMultiplier(wave) {
  return Math.min(CONFIG.difficulty.speedMax, 1 + (wave - 1) * CONFIG.difficulty.speedPerWave);
}

export function waveEnemyCount(wave) {
  if (wave < 3) return 5;
  if (wave < 5) return 6;
  if (wave < 7) return 8;
  return 8 + Math.floor((wave - 7) / 2);
}

export function waveTypes(wave, total = waveEnemyCount(wave)) {
  const available = ["base"];
  if (wave >= 3) available.push("fast");
  if (wave >= 5) available.push("tank");
  const types = [];
  for (let i = 0; i < total; i++) types.push(available[i % available.length]);
  return types;
}

export function waveEnemyTotal(wave, playerCount) {
  const base = waveEnemyCount(wave);
  const multiplier = 1 + (playerCount - 1) * CONFIG.wave.playerScale;
  return Math.min(CONFIG.wave.maxEnemies, Math.max(1, Math.ceil(base * multiplier)));
}

export function respawnSeconds(wave) {
  return Math.max(CONFIG.respawn.base, Math.min(CONFIG.respawn.max, CONFIG.respawn.base + (wave - 1) * CONFIG.respawn.perWave));
}

export function resolveCircleVsAABB(px, py, radius, box) {
  const minX = box.x - box.w / 2;
  const maxX = box.x + box.w / 2;
  const minY = box.y - box.h / 2;
  const maxY = box.y + box.h / 2;
  const closestX = clamp(px, minX, maxX);
  const closestY = clamp(py, minY, maxY);
  let dx = px - closestX;
  let dy = py - closestY;
  const distSq = dx * dx + dy * dy;
  if (distSq > radius * radius) return { x: px, y: py };
  if (distSq === 0) {
    const left = px - minX;
    const right = maxX - px;
    const top = py - minY;
    const bottom = maxY - py;
    const m = Math.min(left, right, top, bottom);
    if (m === left) return { x: minX - radius, y: py };
    if (m === right) return { x: maxX + radius, y: py };
    if (m === top) return { x: px, y: minY - radius };
    return { x: px, y: maxY + radius };
  }
  const dist = Math.sqrt(distSq);
  const overlap = radius - dist;
  return { x: px + (dx / dist) * overlap, y: py + (dy / dist) * overlap };
}

export function segmentIntersectsBox(x1, y1, x2, y2, minX, minY, maxX, maxY) {
  let tmin = 0;
  let tmax = 1;
  const dx = x2 - x1;
  const dy = y2 - y1;
  const p = [-dx, dx, -dy, dy];
  const q = [x1 - minX, maxX - x1, y1 - minY, maxY - y1];
  for (let i = 0; i < 4; i++) {
    if (Math.abs(p[i]) < 1e-9) {
      if (q[i] < 0) return false;
    } else {
      const t = q[i] / p[i];
      if (p[i] < 0) {
        if (t > tmax) return false;
        if (t > tmin) tmin = t;
      } else {
        if (t < tmin) return false;
        if (t < tmax) tmax = t;
      }
    }
  }
  return true;
}

export function obstaclesBlockSegment(x1, y1, x2, y2, radius, obstacles = MAP.obstacles) {
  for (const box of obstacles) {
    if (
      segmentIntersectsBox(
        x1, y1, x2, y2,
        box.x - box.w / 2 - radius,
        box.y - box.h / 2 - radius,
        box.x + box.w / 2 + radius,
        box.y + box.h / 2 + radius
      )
    ) {
      return true;
    }
  }
  return false;
}

export function moveCircle(pos, radius) {
  let x = clamp(pos.x, -(CONFIG.arenaHalfSize - radius), CONFIG.arenaHalfSize - radius);
  let y = clamp(pos.y, -(CONFIG.arenaHalfSize - radius), CONFIG.arenaHalfSize - radius);
  for (const box of MAP.obstacles) {
    const res = resolveCircleVsAABB(x, y, radius, box);
    x = res.x;
    y = res.y;
  }
  return { x, y };
}
