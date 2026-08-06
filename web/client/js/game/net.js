import { CONFIG } from "/shared/game.js";

const R = CONFIG;
const HISTORY_MAX = 60;
const SNAPSHOT_BUFFER = 12;
const RENDER_DELAY_TICKS = Math.round(R.net.renderDelay * R.tickRate);
const RTT_HISTORY = 5;

export class Net {
  constructor(url, token, lobbyId) {
    this.url = url;
    this.token = token;
    this.lobbyId = lobbyId;
    this.ws = null;
    this.connected = false;
    this.myId = null;
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
  }

  connect() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(this.url);
      this.ws = ws;
      ws.onopen = () => {
        ws.send(JSON.stringify({ type: "hello", token: this.token, lobbyId: this.lobbyId }));
      };
      ws.onmessage = (ev) => {
        let msg;
        try {
          msg = JSON.parse(ev.data);
        } catch {
          return;
        }
        if (msg.type === "welcome") {
          this.myId = msg.playerId;
          this.roster = new Map(Object.entries(msg.players || {}));
          this.connected = true;
          resolve(this);
        } else if (msg.type === "snapshot") {
          this.applySnapshot(msg);
        } else if (msg.type === "pong") {
          this.pushRtt(performance.now() - msg.t);
        } else if (msg.type === "kick") {
          this.connected = false;
          reject(new Error(msg.reason || "kicked from server"));
        }
      };
      ws.onerror = () => {
        if (!this.connected) reject(new Error("websocket error"));
      };
      ws.onclose = () => {
        this.connected = false;
        this.on.close?.();
      };
    });
  }

  pushRtt(v) {
    this.rttSamples.push(v);
    if (this.rttSamples.length > RTT_HISTORY) this.rttSamples.shift();
    this.rtt = this.rttSamples.reduce((a, b) => a + b, 0) / this.rttSamples.length;
  }

  sendIntent(intent) {
    if (!this.connected) return;
    this.ws.send(JSON.stringify({ type: "intent", ...intent }));
  }

  sendPing(t) {
    if (this.connected) this.ws.send(JSON.stringify({ type: "ping", t }));
  }

  close() {
    this.connected = false;
    try {
      this.ws.close();
    } catch {
      /* ignore */
    }
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
    return this.serverTickEstimate - RENDER_DELAY_TICKS;
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
}
