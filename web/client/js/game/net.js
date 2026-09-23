import { CONFIG } from "/shared/game.js";
import { OP, decodeData } from "/js/nakama.js";

const R = CONFIG;
const HISTORY_MAX = 60;
const SNAPSHOT_BUFFER = 12;
const RTT_HISTORY = 5;

export class Net {
  constructor({ socket, matchId, session }) {
    this.socket = socket;
    this.matchId = matchId;
    this.session = session;
    this.myId = session.user_id;
    this.connected = true;
    this.roster = new Map();
    this.stateMeta = { serverTick: 0, wave: 0, phase: "countdown", phaseTimer: 0, gameOver: false };
    this.players = new Map();
    this.enemies = new Map();
    this.projectiles = new Map();
    this.pickups = new Map();
    this.history = [];
    this.serverTickEstimate = 0;
    this.rtt = 0;
    this.rttSamples = [];
    this.seq = 0;
    this.on = { close: null };
    this.predictionHistory = [];
    this.onEnd = null;
    this._readyResolve = null;
    this.ready = new Promise((resolve) => {
      this._readyResolve = resolve;
    });
  }

  handleMatchData(md) {
    const data = decodeData(md.data);
    if (md.op_code === OP.SNAPSHOT) {
      try {
        this.applySnapshot(JSON.parse(data));
      } catch {
        /* ignore malformed */
      }
      if (this._readyResolve) {
        this._readyResolve();
        this._readyResolve = null;
      }
    } else if (md.op_code === OP.PONG) {
      try {
        this.pushRtt(performance.now() - JSON.parse(data).t);
      } catch {
        /* ignore */
      }
    } else if (md.op_code === OP.GAMEOVER) {
      this.stateMeta.gameOver = true;
    }
  }

  sendIntent(intent) {
    this.socket.sendMatchState(this.matchId, OP.INTENT, JSON.stringify(intent)).catch(() => {});
  }

  sendPing(t) {
    this.socket.sendMatchState(this.matchId, OP.PING, JSON.stringify({ t })).catch(() => {});
  }

  pushRtt(v) {
    this.rttSamples.push(v);
    if (this.rttSamples.length > RTT_HISTORY) this.rttSamples.shift();
    this.rtt = this.rttSamples.reduce((a, b) => a + b, 0) / this.rttSamples.length;
  }

  applySnapshot(snap) {
    this.stateMeta = {
      serverTick: snap.serverTick,
      wave: snap.wave,
      phase: snap.phase,
      phaseTimer: snap.phaseTimer,
      gameOver: snap.gameOver
    };
    this.serverTickEstimate = snap.serverTick + (this.rtt / 2 / 1000) * R.tickRate;
    if (snap.full) {
      this.players.clear();
      this.enemies.clear();
      this.projectiles.clear();
      this.pickups.clear();
      if (snap.usernames) this.roster = new Map(Object.entries(snap.usernames));
    }
    for (const [id, e] of Object.entries(snap.players || {})) this.players.set(id, e);
    for (const id of snap.removedPlayers || []) this.players.delete(id);
    for (const [id, e] of Object.entries(snap.enemies || {})) this.enemies.set(id, e);
    for (const id of snap.removedEnemies || []) this.enemies.delete(id);
    for (const [id, e] of Object.entries(snap.projectiles || {})) this.projectiles.set(id, e);
    for (const id of snap.removedProjectiles || []) this.projectiles.delete(id);
    for (const [id, e] of Object.entries(snap.pickups || {})) this.pickups.set(id, e);
    for (const id of snap.removedPickups || []) this.pickups.delete(id);
    this.history.push({
      serverTick: snap.serverTick,
      players: new Map(this.players),
      enemies: new Map(this.enemies),
      projectiles: new Map(this.projectiles),
      pickups: new Map(this.pickups)
    });
    if (this.history.length > SNAPSHOT_BUFFER) this.history.shift();
  }

  advanceEstimate(dt) {
    this.serverTickEstimate += dt * R.tickRate;
  }

  interpolate(tick) {
    const h = this.history;
    if (h.length === 0) return { a: null, b: null, alpha: 0 };
    if (h.length === 1) return { a: h[0], b: h[0], alpha: 0 };
    let i = 0;
    while (i < h.length - 1 && h[i + 1].serverTick <= tick) i++;
    const a = h[i];
    const b = h[Math.min(i + 1, h.length - 1)];
    let alpha = 0;
    if (a !== b && b.serverTick !== a.serverTick) {
      alpha = Math.max(0, Math.min(1, (tick - a.serverTick) / (b.serverTick - a.serverTick)));
    }
    return { a, b, alpha };
  }

  renderTick() {
    const delay = Math.max(0.08, Math.min(0.3, this.rtt / 1000 * 0.6 + 0.05));
    const delayTicks = Math.round(delay * R.tickRate);
    return this.serverTickEstimate - delayTicks;
  }

  recordPrediction(tick, pos, health) {
    this.predictionHistory.push({ tick, x: pos.x, y: pos.y, health });
    if (this.predictionHistory.length > HISTORY_MAX) this.predictionHistory.shift();
  }

  reconcile(serverPos, serverHealth, serverLastInputTick) {
    const entry = this.predictionHistory.find((h) => h.tick === serverLastInputTick);
    if (!entry) return { snap: false, error: { x: 0, y: 0 } };
    const ex = serverPos[0] - entry.x;
    const ey = serverPos[1] - entry.y;
    const dist = Math.hypot(ex, ey);
    if (dist > R.net.reconcileSnap) {
      return { snap: true, error: { x: 0, y: 0 }, health: serverHealth };
    }
    return { snap: false, error: { x: ex, y: ey }, dist, health: serverHealth };
  }

  close() {
    this.connected = false;
  }

  reset() {
    this.connected = false;
    this.myId = null;
    this.roster.clear();
    this.stateMeta = { serverTick: 0, wave: 0, phase: "countdown", phaseTimer: 0, gameOver: false };
    this.players.clear();
    this.enemies.clear();
    this.projectiles.clear();
    this.pickups.clear();
    this.history.length = 0;
    this.serverTickEstimate = 0;
    this.rtt = 0;
    this.rttSamples.length = 0;
    this.seq = 0;
    this.predictionHistory.length = 0;
  }
}
