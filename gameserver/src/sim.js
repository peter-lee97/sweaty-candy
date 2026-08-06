import {
  CONFIG,
  ENEMY_TYPES,
  MAP,
  difficultyHpMultiplier,
  difficultySpeedMultiplier,
  respawnSeconds,
  waveEnemyTotal,
  waveTypes,
  moveCircle,
  obstaclesBlockSegment
} from "../../shared/game.js";

const R = CONFIG;

export class GameSim {
  constructor() {
    this.reset();
  }

  reset() {
    this.tick = 0;
    this.wave = 0;
    this.gameOver = false;
    this.phase = "countdown";
    this.phaseTimer = R.wave.startCountdown;
    this.players = new Map();
    this.enemies = new Map();
    this.projectiles = [];
    this.pickups = [];
    this.nextEntityId = 1;
    this.spawnQueue = [];
    this.spawnTimer = 0;
  }

  addPlayer(id, username) {
    const idx = this.players.size % MAP.playerSpawns.length;
    const spawn = MAP.playerSpawns[idx];
    const jitter = () => (Math.random() - 0.5) * 200;
    this.players.set(id, {
      id,
      username,
      spawnIndex: idx,
      position: { x: spawn[0] + jitter(), y: spawn[1] + jitter() },
      velocity: { x: 0, y: 0 },
      knockback: { x: 0, y: 0 },
      aim: { x: 0, y: 1 },
      health: R.player.maxHealth,
      alive: true,
      respawnTimer: 0,
      lastIntent: null,
      intentQueue: [],
      shootTimer: 0,
      lastInputTick: 0
    });
  }

  removePlayer(id) {
    this.players.delete(id);
  }

  playerCount() {
    return this.players.size;
  }

  submitIntent(id, intent) {
    const p = this.players.get(id);
    if (!p) return;
    if (p.intentQueue.length >= 16) p.intentQueue.shift();
    p.intentQueue.push(intent);
  }

  step(dt) {
    this.tick++;
    if (this.gameOver) return;
    this.updateWave(dt);
    this.updatePlayers(dt);
    this.updateEnemies(dt);
    this.updateProjectiles(dt);
    this.updatePickups(dt);
    this.updateRespawns(dt);
    if (this.players.size > 0 && [...this.players.values()].every((p) => !p.alive)) {
      this.gameOver = true;
    }
  }

  updateWave(dt) {
    switch (this.phase) {
      case "countdown":
      case "intermission":
        this.phaseTimer -= dt;
        if (this.phaseTimer <= 0) this.startWave();
        break;
      case "spawning":
        this.spawnTimer -= dt;
        while (this.spawnTimer <= 0 && this.spawnQueue.length > 0) {
          const type = this.spawnQueue.shift();
          this.spawnEnemy(type);
          this.spawnTimer += R.wave.spawnStagger;
        }
        if (this.spawnQueue.length === 0) {
          this.phase = "active";
        }
        break;
      case "active":
        if (this.enemies.size === 0) {
          this.phase = "intermission";
          this.phaseTimer = R.wave.delay;
        }
        break;
    }
  }

  startWave() {
    this.wave++;
    const total = waveEnemyTotal(this.wave, this.playerCount());
    this.spawnQueue = waveTypes(this.wave, total);
    this.phase = "spawning";
    this.spawnTimer = 0;
  }

  spawnEnemy(type) {
    const def = ENEMY_TYPES[type];
    const pos = this.edgeSpawnPosition();
    const hp = Math.round(def.hp * difficultyHpMultiplier(this.wave));
    const speed = def.speed * difficultySpeedMultiplier(this.wave);
    this.enemies.set(`e${this.nextEntityId++}`, {
      id: `e${this.nextEntityId - 1}`,
      type,
      position: pos,
      velocity: { x: 0, y: 0 },
      knockback: { x: 0, y: 0 },
      hp,
      maxHp: hp,
      speed,
      damage: def.damage,
      score: def.score,
      half: def.half,
      hitFlash: 0,
      damageTimer: 0
    });
  }

  edgeSpawnPosition() {
    const half = R.arenaHalfSize - 80;
    const band = 200;
    const edge = Math.floor(Math.random() * 4);
    const r = (a, b) => a + Math.random() * (b - a);
    switch (edge) {
      case 0: return { x: r(-half, half), y: r(-half, -half + band) };
      case 1: return { x: r(half - band, half), y: r(-half, half) };
      case 2: return { x: r(-half, half), y: r(half - band, half) };
      default: return { x: r(-half, -half + band), y: r(-half, half) };
    }
  }

  updatePlayers(dt) {
    for (const p of this.players.values()) {
      if (!p.alive) continue;
      const intent = p.intentQueue.length ? p.intentQueue.shift() : p.lastIntent;
      p.lastIntent = intent;
      if (intent) p.lastInputTick = intent.tick;
      p.shootTimer = Math.max(0, p.shootTimer - dt);
      let mx = 0;
      let my = 0;
      if (intent) {
        mx = intent.move[0];
        my = intent.move[1];
        const len = Math.hypot(mx, my);
        if (len > 1) {
          mx /= len;
          my /= len;
        }
        if (intent.aim && (intent.aim[0] !== 0 || intent.aim[1] !== 0)) {
          p.aim = { x: intent.aim[0], y: intent.aim[1] };
        }
        if (intent.shoot && p.shootTimer <= 0) {
          this.fireProjectile(p, intent);
          p.shootTimer = R.projectile.cooldown;
        }
      }
      p.velocity.x = mx * R.player.moveSpeed;
      p.velocity.y = my * R.player.moveSpeed;
      const kx = p.knockback.x;
      const ky = p.knockback.y;
      p.knockback.x = kx * Math.exp(-8 * dt);
      p.knockback.y = ky * Math.exp(-8 * dt);
      if (Math.hypot(p.knockback.x, p.knockback.y) < 2) {
        p.knockback.x = 0;
        p.knockback.y = 0;
      }
      const target = {
        x: p.position.x + (p.velocity.x + p.knockback.x) * dt,
        y: p.position.y + (p.velocity.y + p.knockback.y) * dt
      };
      p.position = moveCircle(target, R.player.halfExtent);
    }
  }

  fireProjectile(p, intent) {
    const dir = p.aim;
    const len = Math.hypot(dir.x, dir.y) || 1;
    const nx = dir.x / len;
    const ny = dir.y / len;
    this.projectiles.push({
      id: `p${this.nextEntityId++}`,
      ownerId: p.id,
      position: { x: p.position.x + nx * 22, y: p.position.y + ny * 22 },
      direction: { x: nx, y: ny },
      localSeq: intent ? intent.localSeq || 0 : 0,
      lifetime: R.projectile.lifetime
    });
  }

  updateProjectiles(dt) {
    const survivors = [];
    for (const proj of this.projectiles) {
      proj.lifetime -= dt;
      if (proj.lifetime <= 0) continue;
      const dist = R.projectile.speed * dt;
      const steps = Math.max(1, Math.ceil(dist / R.projectile.subStep));
      const stepDist = dist / steps;
      let dead = false;
      for (let i = 0; i < steps && !dead; i++) {
        const nx = proj.position.x + proj.direction.x * stepDist;
        const ny = proj.position.y + proj.direction.y * stepDist;
        if (Math.abs(nx) > R.arenaHalfSize - R.projectile.radius || Math.abs(ny) > R.arenaHalfSize - R.projectile.radius) {
          dead = true;
          break;
        }
        if (obstaclesBlockSegment(proj.position.x, proj.position.y, nx, ny, R.projectile.radius)) {
          dead = true;
          break;
        }
        for (const enemy of this.enemies.values()) {
          const d2 = (enemy.position.x - nx) ** 2 + (enemy.position.y - ny) ** 2;
          if (d2 < R.projectile.hitRadius ** 2) {
            this.damageEnemy(enemy, R.projectile.damage, proj.direction);
            dead = true;
            break;
          }
        }
        if (!dead) {
          proj.position.x = nx;
          proj.position.y = ny;
        }
      }
      if (!dead) survivors.push(proj);
    }
    this.projectiles = survivors;
  }

  damageEnemy(enemy, amount, dir) {
    enemy.hp -= amount;
    enemy.hitFlash = 0.1;
    const len = Math.hypot(dir.x, dir.y) || 1;
    enemy.knockback.x += (dir.x / len) * R.enemy.knockbackForce;
    enemy.knockback.y += (dir.y / len) * R.enemy.knockbackForce;
    if (enemy.hp <= 0) {
      this.enemies.delete(enemy.id);
      this.maybeDropPickup(enemy.position);
    }
  }

  maybeDropPickup(pos) {
    if (Math.random() < R.pickup.dropChance) {
      this.pickups.push({ id: `k${this.nextEntityId++}`, position: { x: pos.x, y: pos.y }, lifetime: R.pickup.lifetime });
    }
  }

  updateEnemies(dt) {
    const alivePlayers = [...this.players.values()].filter((p) => p.alive);
    for (const enemy of this.enemies.values()) {
      enemy.hitFlash = Math.max(0, enemy.hitFlash - dt);
      enemy.damageTimer = Math.max(0, enemy.damageTimer - dt);
      let target = null;
      let best = Infinity;
      for (const p of alivePlayers) {
        const d2 = (p.position.x - enemy.position.x) ** 2 + (p.position.y - enemy.position.y) ** 2;
        if (d2 < best) {
          best = d2;
          target = p;
        }
      }
      let vx = 0;
      let vy = 0;
      if (target) {
        const dx = target.position.x - enemy.position.x;
        const dy = target.position.y - enemy.position.y;
        const len = Math.hypot(dx, dy) || 1;
        vx = (dx / len) * enemy.speed;
        vy = (dy / len) * enemy.speed;
      }
      const kx = enemy.knockback.x;
      const ky = enemy.knockback.y;
      enemy.knockback.x = kx * Math.exp(-8 * dt);
      enemy.knockback.y = ky * Math.exp(-8 * dt);
      if (Math.hypot(enemy.knockback.x, enemy.knockback.y) < 2) {
        enemy.knockback.x = 0;
        enemy.knockback.y = 0;
      }
      const maxSpeed = enemy.speed * 2.5;
      const totalVx = Math.min(Math.max(vx + enemy.knockback.x, -maxSpeed), maxSpeed);
      const totalVy = Math.min(Math.max(vy + enemy.knockback.y, -maxSpeed), maxSpeed);
      const target2 = {
        x: enemy.position.x + totalVx * dt,
        y: enemy.position.y + totalVy * dt
      };
      enemy.position = moveCircle(target2, enemy.half);
      if (target && enemy.damageTimer <= 0) {
        const d2 = (target.position.x - enemy.position.x) ** 2 + (target.position.y - enemy.position.y) ** 2;
        if (d2 < R.enemy.contactRadius ** 2) {
          this.damagePlayer(target, enemy.damage, {
            x: enemy.position.x - target.position.x,
            y: enemy.position.y - target.position.y
          });
          enemy.damageTimer = R.enemy.hitRate;
        }
      }
    }
  }

  damagePlayer(p, amount, knockDir) {
    if (!p.alive) return;
    p.health = Math.max(0, p.health - amount);
    const len = Math.hypot(knockDir.x, knockDir.y) || 1;
    p.knockback.x = (knockDir.x / len) * R.player.knockbackForce;
    p.knockback.y = (knockDir.y / len) * R.player.knockbackForce;
    if (p.health <= 0) {
      p.alive = false;
      p.respawnTimer = respawnSeconds(this.wave);
    }
  }

  updatePickups(dt) {
    const survivors = [];
    for (const pickup of this.pickups) {
      pickup.lifetime -= dt;
      if (pickup.lifetime <= 0) continue;
      let collected = false;
      for (const p of this.players.values()) {
        if (!p.alive) continue;
        const d2 = (p.position.x - pickup.position.x) ** 2 + (p.position.y - pickup.position.y) ** 2;
        if (d2 < R.pickup.radius ** 2) {
          p.health = Math.min(R.player.maxHealth, p.health + R.pickup.heal);
          collected = true;
          break;
        }
      }
      if (!collected) survivors.push(pickup);
    }
    this.pickups = survivors;
  }

  updateRespawns(dt) {
    for (const p of this.players.values()) {
      if (p.alive) continue;
      p.respawnTimer -= dt;
      if (p.respawnTimer <= 0) {
        p.alive = true;
        p.health = R.player.maxHealth;
        p.intentQueue.length = 0;
        p.lastIntent = null;
        const spawn = MAP.playerSpawns[p.spawnIndex % MAP.playerSpawns.length];
        const jitter = () => (Math.random() - 0.5) * 100;
        p.position = { x: spawn[0] + jitter(), y: spawn[1] + jitter() };
        p.velocity = { x: 0, y: 0 };
        p.knockback = { x: 0, y: 0 };
      }
    }
  }
}

export function buildSnapshot(sim, full = false) {
  const snapshot = {
    type: "snapshot",
    serverTick: sim.tick,
    wave: sim.wave,
    phase: sim.phase,
    phaseTimer: sim.phaseTimer,
    gameOver: sim.gameOver,
    full,
    players: {},
    enemies: {},
    projectiles: {},
    pickups: {},
    removedPlayers: [],
    removedEnemies: [],
    removedProjectiles: [],
    removedPickups: []
  };
  for (const p of sim.players.values()) {
    snapshot.players[p.id] = {
      position: [p.position.x, p.position.y],
      aim: [p.aim.x, p.aim.y],
      health: p.health,
      alive: p.alive,
      respawnTimer: p.respawnTimer,
      lastInputTick: p.lastInputTick
    };
  }
  for (const e of sim.enemies.values()) {
    snapshot.enemies[e.id] = { position: [e.position.x, e.position.y], type: e.type, hp: e.hp, maxHp: e.maxHp };
  }
  for (const proj of sim.projectiles) {
    snapshot.projectiles[proj.id] = {
      position: [proj.position.x, proj.position.y],
      direction: [proj.direction.x, proj.direction.y],
      localSeq: proj.localSeq
    };
  }
  for (const pk of sim.pickups) {
    snapshot.pickups[pk.id] = { position: [pk.position.x, pk.position.y] };
  }
  return snapshot;
}

export function deltaFrom(full, prev) {
  const d = {
    type: "snapshot",
    serverTick: full.serverTick,
    wave: full.wave,
    phase: full.phase,
    phaseTimer: full.phaseTimer,
    gameOver: full.gameOver,
    full: false,
    players: {},
    enemies: {},
    projectiles: {},
    pickups: {},
    removedPlayers: [],
    removedEnemies: [],
    removedProjectiles: [],
    removedPickups: []
  };
  for (const [id, e] of Object.entries(full.players)) {
    const old = prev.players[id];
    if (!old || entityChanged(old, e)) d.players[id] = e;
  }
  for (const id of Object.keys(prev.players)) {
    if (!full.players[id]) d.removedPlayers.push(id);
  }
  for (const [id, e] of Object.entries(full.enemies)) {
    const old = prev.enemies[id];
    if (!old || entityChanged(old, e)) d.enemies[id] = e;
  }
  for (const id of Object.keys(prev.enemies)) {
    if (!full.enemies[id]) d.removedEnemies.push(id);
  }
  for (const [id, e] of Object.entries(full.projectiles)) {
    const old = prev.projectiles[id];
    if (!old || entityChanged(old, e)) d.projectiles[id] = e;
  }
  for (const id of Object.keys(prev.projectiles)) {
    if (!full.projectiles[id]) d.removedProjectiles.push(id);
  }
  for (const [id, e] of Object.entries(full.pickups)) {
    const old = prev.pickups[id];
    if (!old || entityChanged(old, e)) d.pickups[id] = e;
  }
  for (const id of Object.keys(prev.pickups)) {
    if (!full.pickups[id]) d.removedPickups.push(id);
  }
  return d;
}

function entityChanged(a, b) {
  const posChanged =
    Math.abs(a.position[0] - b.position[0]) > 1 || Math.abs(a.position[1] - b.position[1]) > 1;
  if (posChanged) return true;
  if ("health" in a && a.health !== b.health) return true;
  if ("maxHp" in a && a.hp !== b.hp) return true;
  if ("alive" in a && a.alive !== b.alive) return true;
  if ("respawnTimer" in a && Math.abs(a.respawnTimer - b.respawnTimer) > 0.1) return true;
  if ("aim" in a && (a.aim[0] !== b.aim[0] || a.aim[1] !== b.aim[1])) return true;
  if ("lastInputTick" in a && a.lastInputTick !== b.lastInputTick) return true;
  return false;
}
