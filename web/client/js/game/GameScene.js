import Phaser from 'phaser';
import { CONFIG, moveCircle } from '/shared/game.js';
import { InputManager } from './InputManager.js';
import { IsometricRenderer } from './IsometricRenderer.js';
import { EntityManager } from './EntityManager.js';
import { ParticleManager } from './ParticleManager.js';

const R = CONFIG;

export class GameScene extends Phaser.Scene {
  constructor() {
    super({ key: 'GameScene' });
    this.net = null;
    this.myUsername = '';
    this.inputManager = null;
    this.isoRenderer = null;
    this.entityManager = null;
    this.particleManager = null;
    
    this.localTick = 0;
    this.acc = 0;
    this.predictedPos = { x: 0, y: 0 };
    this.facing = { x: 0, y: 1 };
    this.myHealth = 100;
    this.myAlive = true;
    this.myRespawn = 0;
    this.correction = null;
    this.lastPing = 0;
    this.ghosts = [];
    this.shotsFired = 0;
    this.gameOverShown = false;
  }

  init(data) {
    this.net = data.net;
    this.myUsername = data.myUsername;
  }

  create() {
    this.isoRenderer = new IsometricRenderer(this);
    this.inputManager = new InputManager(this);
    this.inputManager.create();
    this.entityManager = new EntityManager(this);
    this.particleManager = new ParticleManager(this);

    this.isoRenderer.drawMap();
    
    this.predictedPos = this.snapshotMy();
    
    this.cameras.main.setZoom(0.55);

    const initScreen = this.isoRenderer.worldToScreen(this.predictedPos.x, this.predictedPos.y);
    this.cameras.main.centerOn(initScreen.x, initScreen.y);

    this.input.on('wheel', (pointer, gameObjects, deltaX, deltaY) => {
      const currentZoom = this.cameras.main.zoom;
      const newZoom = Phaser.Math.Clamp(
        currentZoom * (deltaY > 0 ? 0.9 : 1.1),
        0.25,
        1.6
      );
      this.cameras.main.setZoom(newZoom);
    });
  }

  update(time, delta) {
    const dt = delta / 1000;
    
    this.net.advanceEstimate(dt);
    
    if (this.net.connected && time - this.lastPing > R.net.pingInterval * 1000) {
      this.lastPing = time;
      this.net.sendPing(time);
    }
    
    this.sendIntents(dt);
    
    const my = this.net.players.get(this.net.myId);
    if (my) {
      const res = this.net.reconcile(my.position, my.health, my.lastInputTick);
      if (res.snap) {
        this.predictedPos = { x: my.position[0], y: my.position[1] };
        this.correction = null;
        this.myHealth = my.health;
      } else if (res.dist > 0.5) {
        this.correction = { x: res.error.x, y: res.error.y };
        this.myHealth = res.health;
      }
      
      const wasAlive = this.myAlive;
      this.myAlive = my.alive;
      this.myRespawn = my.respawnTimer;
      
      if (!wasAlive && my.alive) {
        this.predictedPos = { x: my.position[0], y: my.position[1] };
        this.correction = null;
      }
    }
    
    if (this.correction) {
      const alpha = Math.min(1, dt / R.net.reconcileBlend);
      this.predictedPos.x += this.correction.x * alpha;
      this.predictedPos.y += this.correction.y * alpha;
      this.correction.x *= 1 - alpha;
      this.correction.y *= 1 - alpha;
      if (Math.hypot(this.correction.x, this.correction.y) < 0.5) {
        this.correction = null;
      }
    }
    
    this.updateGhosts(dt);
    this.entityManager.update(dt, time / 1000);
    this.particleManager.update(dt);
    this.updateCamera(dt);
    this.updateHUD();
    this.checkGameOver();
  }

  snapshotMy() {
    const snap = this.net.history[this.net.history.length - 1];
    if (!snap) return { x: 0, y: 0 };
    const my = snap.players.get(this.net.myId);
    return my ? { x: my.position[0], y: my.position[1] } : { x: 0, y: 0 };
  }

  sendIntents(dt) {
    const move = this.inputManager.getMovement();
    
    if (move.x !== 0 || move.y !== 0) {
      this.facing = { x: move.x, y: move.y };
    }
    
    this.acc += dt;
    while (this.acc >= R.tickDelta) {
      this.acc -= R.tickDelta;
      this.localTick++;
      
      const intent = {
        tick: this.localTick,
        move: [move.x, move.y],
        aim: [this.facing.x, this.facing.y],
        shoot: this.inputManager.isShooting(),
        localSeq: ++this.net.seq
      };
      
      if (this.myAlive) {
        this.predictedPos.x += intent.move[0] * R.player.moveSpeed * R.tickDelta;
        this.predictedPos.y += intent.move[1] * R.player.moveSpeed * R.tickDelta;
        this.predictedPos = moveCircle(this.predictedPos, R.player.halfExtent);
      }
      
      this.net.recordPrediction(this.localTick, this.predictedPos, this.myHealth);
      
      if (intent.shoot && this.myAlive) {
        this.spawnGhost(intent.localSeq, this.predictedPos, this.facing);
        this.shotsFired++;
      }
      
      this.net.sendIntent(intent);
    }
  }

  spawnGhost(seq, pos, dir) {
    this.ghosts.push({
      seq,
      pos: { x: pos.x + dir.x * 22, y: pos.y + dir.y * 22 },
      dir: { x: dir.x, y: dir.y },
      born: this.time.now
    });
  }

  updateGhosts(dt) {
    const now = this.time.now;
    const matched = new Set();
    for (const proj of this.net.projectiles.values()) {
      if (proj.localSeq) matched.add(proj.localSeq);
    }
    
    this.ghosts = this.ghosts.filter((g) => {
      if (matched.has(g.seq)) return false;
      if (now - g.born > R.net.ghostTimeout * 1000) return false;
      g.pos.x += g.dir.x * R.projectile.speed * dt;
      g.pos.y += g.dir.y * R.projectile.speed * dt;
      return true;
    });
  }

  updateCamera(dt) {
    const target = this.myAlive ? this.predictedPos : { x: 0, y: 0 };
    const screen = this.isoRenderer.worldToScreen(target.x, target.y);
    
    const k = Math.min(1, dt * 6);
    const cam = this.cameras.main;
    const currentCenter = {
      x: cam.scrollX + cam.width / 2,
      y: cam.scrollY + cam.height / 2
    };
    
    const newCenter = {
      x: currentCenter.x + (screen.x - currentCenter.x) * k,
      y: currentCenter.y + (screen.y - currentCenter.y) * k
    };
    
    cam.centerOn(newCenter.x, newCenter.y);
  }

  updateHUD() {
    const hud = window.gameHUD;
    if (!hud) return;
    
    hud.setHealth(this.myHealth, R.player.maxHealth);
    hud.setPing(this.net.rtt);
    hud.setPlayerList(this.net.roster, this.buildAliveMap());
    
    const { phase, phaseTimer, wave } = this.net.stateMeta;
    
    if (this.net.stateMeta.gameOver) {
      hud.setBanner('');
      hud.setRespawn('');
      return;
    }
    
    if (!this.myAlive) {
      hud.setBanner('');
      hud.setRespawn(`Respawning in ${Math.max(0, this.myRespawn).toFixed(1)}s`);
    } else {
      hud.setRespawn('');
    }
    
    if (phase === 'countdown' && wave === 0) {
      const sec = Math.ceil(phaseTimer);
      hud.setBanner(sec > 0 ? `${sec}` : 'GO!', 'Get ready');
    } else if (phase === 'spawning') {
      hud.setBanner(`Level ${wave}`);
    } else if (phase === 'active') {
      hud.setBanner(`Level ${wave}`, `${this.net.enemies.size} monsters`);
    } else if (phase === 'intermission') {
      hud.setBanner(`Level ${wave} cleared`, `Next in ${Math.ceil(phaseTimer)}s`);
    }
  }

  buildAliveMap() {
    const m = new Map();
    for (const [id, e] of this.net.players) m.set(id, e.alive);
    return m;
  }

  checkGameOver() {
    if (this.net.stateMeta.gameOver && !this.gameOverShown) {
      this.gameOverShown = true;
      const hud = window.gameHUD;
      if (hud) {
        hud.setBanner('');
        hud.showGameOver(`You survived ${this.net.stateMeta.wave} levels\nShots fired: ${this.shotsFired}`);
      }
    }
  }

  burst(pos, color, count, speed) {
    this.particleManager.burst(pos, color, count, speed);
  }
}
