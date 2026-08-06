import { ENEMY_TYPES } from '/shared/game.js';

function hashOffset(id) {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return h % 100;
}

function lerpVec(a, b, t) {
  return { x: a[0] + (b[0] - a[0]) * t, y: a[1] + (b[1] - a[1]) * t };
}

const PLAYER_LOCAL = 0x2f7bff;
const PLAYER_REMOTE = 0x7fb2ff;
const PLAYER_OUTLINE = 0xdce6ff;
const PROJECTILE_COLOR = 0xffe64d;
const PICKUP_COLOR = 0x39e675;
const ENEMY_COLOR = { base: 0xe5313a, fast: 0xff8c1a, tank: 0x9a33d1 };

export class EntityManager {
  constructor(scene) {
    this.scene = scene;
    this.players = new Map();
    this.enemies = new Map();
    this.projectiles = new Map();
    this.pickups = new Map();
    this.playerFx = new Map();
    this.enemyFx = new Map();
    this.pickupFx = new Map();
    this.ghostGfx = null;
    this.pendingDestroy = [];
  }

  iso(x, y) {
    return this.scene.isoRenderer.worldToScreen(x, y);
  }

  update(dt, time) {
    const net = this.scene.net;
    const { a, b, alpha } = net.interpolate(net.renderTick());
    const snapA = a || b;
    const snapB = b || a;

    if (snapA && snapB) {
      this.updateRemotePlayers(snapA, snapB, alpha, time);
      this.updateEnemies(snapA, snapB, alpha, time);
      this.updateProjectiles(snapA, snapB, alpha);
      this.updatePickups(snapA, snapB, alpha, time);
    }
    this.updateLocalPlayer(time);
    this.renderGhosts();
    this.applyDestroys();
  }

  updateRemotePlayers(a, b, alpha, time) {
    const net = this.scene.net;
    for (const [id, ent] of b.players) {
      if (id === net.myId) continue;
      const pa = a.players.get(id);
      const pos = pa ? lerpVec(pa.position, ent.position, alpha) : { x: ent.position[0], y: ent.position[1] };
      const old = this.playerFx.get(id);
      if (old && old.hp > ent.health) this.scene.burst(ent.position, '#dce6ff', 4, 60);
      this.playerFx.set(id, { hp: ent.health });
      let Sh = this.players.get(id);
      if (!Sh) { Sh = this.createPlayerObj(); this.players.set(id, Sh); }
      this.drawPlayer(Sh, pos, ent.aim, ent.health, ent.alive, net.roster.get(id) || '', false);
      Sh.setDepth(pos.x + pos.y);
    }
    for (const id of this.players.keys()) {
      if (!b.players.has(id) && id !== net.myId) this.markDestroy(this.players, id);
    }
  }

  updateLocalPlayer() {
    const scene = this.scene;
    const myId = scene.net.myId;
    let Sh = this.players.get(myId);
    if (!Sh) { Sh = this.createPlayerObj(); this.players.set(myId, Sh); }
    this.drawPlayer(Sh, scene.predictedPos, scene.facing, scene.myHealth, scene.myAlive, scene.myUsername, true);
    Sh.setDepth(scene.predictedPos.x + scene.predictedPos.y);
  }

  updateEnemies(a, b, alpha, time) {
    for (const [id, ent] of b.enemies) {
      const ea = a.enemies.get(id);
      const pos = ea ? lerpVec(ea.position, ent.position, alpha) : { x: ent.position[0], y: ent.position[1] };
      let angle = 0;
      if (ea) angle = Math.atan2(ent.position[1] - ea.position[1], ent.position[0] - ea.position[0]);

      const fx = this.enemyFx.get(id);
      const prevHp = fx ? fx.hp : ent.maxHp;
      if (fx && prevHp > ent.hp) this.scene.burst(pos, '#ffe64d', 5, 90);
      if (fx && prevHp > 0 && ent.hp <= 0) this.scene.burst(pos, ENEMY_TYPES[ent.type].color, 10, 140);
      this.enemyFx.set(id, { hp: ent.hp });

      let E = this.enemies.get(id);
      if (!E) { E = this.createEnemyObj(); this.enemies.set(id, E); }
      this.drawEnemy(E, pos, ent.type, ent.hp, ent.maxHp, angle);
      E.setDepth(pos.x + pos.y);
    }
    for (const id of this.enemies.keys()) {
      if (!b.enemies.has(id)) this.markDestroy(this.enemies, id);
    }
  }

  updateProjectiles(a, b, alpha) {
    for (const [id, ent] of b.projectiles) {
      const pa = a.projectiles.get(id);
      const pos = pa ? lerpVec(pa.position, ent.position, alpha) : { x: ent.position[0], y: ent.position[1] };
      let P = this.projectiles.get(id);
      if (!P) { P = this.createProjectileObj(); this.projectiles.set(id, P); }
      const s = this.iso(pos.x, pos.y);
      P.setPosition(s.x, s.y);
      P.setDepth(pos.x + pos.y);
    }
    for (const id of this.projectiles.keys()) {
      if (!b.projectiles.has(id)) this.markDestroy(this.projectiles, id);
    }
  }

  updatePickups(a, b, alpha, time) {
    for (const [id, ent] of b.pickups) {
      const pa = a.pickups.get(id);
      const pos = pa ? lerpVec(pa.position, ent.position, alpha) : { x: ent.position[0], y: ent.position[1] };
      const fx = this.pickupFx.get(id) || { t: time };
      this.pickupFx.set(id, fx);
      let K = this.pickups.get(id);
      if (!K) { K = this.createPickupObj(); this.pickups.set(id, K); }
      this.drawPickup(K, pos, time);
      K.setDepth(pos.x + pos.y);
    }
    for (const id of this.pickups.keys()) {
      if (!b.pickups.has(id)) this.markDestroy(this.pickups, id);
    }
  }

  renderGhosts() {
    if (!this.ghostGfx) this.ghostGfx = this.scene.add.graphics().setDepth(9000).setScrollFactor(1);
    this.ghostGfx.clear();
    for (const g of this.scene.ghosts) {
      const s = this.iso(g.pos.x, g.pos.y);
      this.ghostGfx.fillStyle(PROJECTILE_COLOR, 1);
      diamond(this.ghostGfx, s.x, s.y, 5);
    }
  }

  createPlayerObj() {
    const c = this.scene.add.container(0, 0).setScrollFactor(1);
    const g = this.scene.add.graphics();
    const name = this.scene.add.text(0, 0, '', { fontFamily: 'sans-serif', fontSize: '13px' }).setOrigin(0.5).setScrollFactor(1);
    const hp = this.scene.add.graphics().setScrollFactor(1);
    c.add([g, name, hp]);
    c.g = g; c.name = name; c.hp = hp;
    return c;
  }

  createEnemyObj() {
    const c = this.scene.add.container(0, 0).setScrollFactor(1);
    const g = this.scene.add.graphics();
    c.add(g);
    c.g = g;
    return c;
  }

  createProjectileObj() {
    const c = this.scene.add.container(0, 0).setScrollFactor(1);
    const g = this.scene.add.graphics();
    g.fillStyle(PROJECTILE_COLOR, 1);
    diamond(g, 0, 0, 5);
    c.add(g);
    c.g = g;
    return c;
  }

  createPickupObj() {
    const c = this.scene.add.container(0, 0).setScrollFactor(1);
    const g = this.scene.add.graphics();
    c.add(g);
    c.g = g;
    return c;
  }

  drawPlayer(Sh, pos, aim, health, alive, name, isLocal) {
    const s = this.iso(pos.x, pos.y);
    const now = this.scene.time.now / 1000;
    Sh.setPosition(s.x, s.y);
    const g = Sh.g;
    g.clear();
    const r = 16;
    const bob = alive ? Math.sin(now * 6) * 3 : 0;
    const py = -r * 0.6 + bob;

    g.fillStyle(0x000000, 0.35);
    g.fillEllipse(0, 0, r * 2.4, r * 1.1);

    if (aim && alive) {
      const a = this.iso(pos.x + aim.x, pos.y + aim.y);
      const dx = a.x - s.x;
      const dy = a.y - s.y;
      const len = Math.hypot(dx, dy) || 1;
      g.lineStyle(2, 0xffffff, 0.5);
      g.lineBetween(0, py, (dx / len) * r * 1.7, py + (dy / len) * r * 1.7);
    }

    if (!alive) {
      g.fillStyle(0x78788c, 0.35);
      g.fillCircle(0, py, r);
      Sh.name.setText(name).setPosition(0, py + r + 14).setColor('#55556a');
      Sh.hp.clear();
      return;
    }

    g.fillStyle(isLocal ? PLAYER_LOCAL : PLAYER_REMOTE, 1);
    g.fillCircle(0, py, r);
    g.lineStyle(2, PLAYER_OUTLINE, 1);
    g.strokeCircle(0, py, r);
    if (isLocal) {
      g.fillStyle(0xffffff, 1);
      g.fillCircle(0, py, r * 0.32);
    }

    Sh.name.setText(name).setPosition(0, py + r + 14).setColor(isLocal ? '#9dc0ff' : '#cfe0ff');

    Sh.hp.clear();
    if (health < 100) {
      const w = 44, h = 5, x = -w / 2, y = py - r - 16;
      const ratio = Phaser.Math.Clamp(health / 100, 0, 1);
      Sh.hp.fillStyle(0x000000, 0.6);
      Sh.hp.fillRect(x, y, w, h);
      const c = ratio > 0.5 ? 0x39e675 : ratio > 0.25 ? 0xffd24d : 0xff5d5d;
      Sh.hp.fillStyle(c, 1);
      Sh.hp.fillRect(x, y, w * ratio, h);
    }
  }

  drawEnemy(E, pos, type, hp, maxHp, angle) {
    const s = this.iso(pos.x, pos.y);
    E.setPosition(s.x, s.y);
    const def = ENEMY_TYPES[type];
    const g = E.g;
    g.clear();
    const now = this.scene.time.now / 1000;
    const size = def.size;
    const bob = Math.sin(now * 4 + hashOffset(E.id || '') * 0.01) * 2;
    const py = -size * 0.3 + bob;

    g.fillStyle(0x000000, 0.3);
    g.fillEllipse(0, 0, size * 1.4, size * 0.64);

    g.fillStyle(ENEMY_COLOR[type] || 0xff0000, 1);
    switch (type) {
      case 'base':
        g.save();
        g.translateCanvas(0, py);
        g.rotateCanvas(Math.PI / 4);
        g.fillRect(-size * 0.45, -size * 0.45, size * 0.9, size * 0.9);
        g.restore();
        break;
      case 'fast':
        g.save();
        g.translateCanvas(0, py);
        g.rotateCanvas(angle);
        g.beginPath();
        g.moveTo(size * 0.6, 0);
        g.lineTo(-size * 0.5, -size * 0.45);
        g.lineTo(-size * 0.5, size * 0.45);
        g.closePath();
        g.fillPath();
        g.restore();
        break;
      case 'tank':
        polygon(g, 0, py, size * 0.62, 6, 0);
        g.fillPath();
        break;
    }

    if (hp < maxHp) {
      const w = size * 1.1, h = 5, x = -w / 2, y = py - size * 0.7 - 6;
      const ratio = Phaser.Math.Clamp(hp / maxHp, 0, 1);
      g.fillStyle(0x000000, 0.6);
      g.fillRect(x, y, w, h);
      const c = ratio > 0.5 ? 0x39e675 : ratio > 0.25 ? 0xffd24d : 0xff5d5d;
      g.fillStyle(c, 1);
      g.fillRect(x, y, w * ratio, h);
    }
  }

  drawPickup(K, pos, time) {
    const s = this.iso(pos.x, pos.y);
    K.setPosition(s.x, s.y);
    const g = K.g;
    g.clear();
    const pulse = 0.7 + 0.3 * Math.sin(time * 4);
    const r = 11 * pulse;
    g.fillStyle(0x000000, 0.3);
    g.fillEllipse(0, 0, r * 2.8, r * 1.2);
    g.fillStyle(PICKUP_COLOR, 1);
    g.fillEllipse(0, -r, r * 2, r * 1.9);
    g.fillRect(-r * 0.25, -r * 1.4, r * 0.5, r * 0.8);
    g.fillRect(-r * 0.4, -r * 1.15, r * 0.8, r * 0.5);
  }

  markDestroy(map, id) {
    this.pendingDestroy.push([map, id]);
  }

  applyDestroys() {
    for (const [map, id] of this.pendingDestroy) {
      const obj = map.get(id);
      if (obj) { obj.destroy(); map.delete(id); }
    }
    this.pendingDestroy = [];
  }
}

function polygon(g, x, y, radius, sides, rotation) {
  g.beginPath();
  for (let i = 0; i < sides; i++) {
    const ang = rotation + (i / sides) * Math.PI * 2;
    const px = x + Math.cos(ang) * radius;
    const py = y + Math.sin(ang) * radius;
    if (i === 0) g.moveTo(px, py);
    else g.lineTo(px, py);
  }
  g.closePath();
}

function diamond(g, x, y, size) {
  g.beginPath();
  g.moveTo(x, y - size);
  g.lineTo(x + size, y);
  g.lineTo(x, y + size);
  g.lineTo(x - size, y);
  g.closePath();
  g.fillPath();
}
