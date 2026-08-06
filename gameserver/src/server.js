import http from "node:http";
import { URL } from "node:url";
import { WebSocketServer } from "ws";
import { CONFIG } from "../../shared/game.js";
import { GameSim, buildSnapshot, deltaFrom } from "./sim.js";

const R = CONFIG;
const BACKEND_BASE = process.env.BACKEND_BASE_URL || "http://127.0.0.1:8787";
const LISTEN_HOST = process.env.LISTEN_HOST || "0.0.0.0";
const LISTEN_PORT = Number(process.env.LISTEN_PORT || 7777);
const ADVERTISED_HOST = process.env.ADVERTISED_HOST || "127.0.0.1";
const ADVERTISED_PORT = Number(process.env.ADVERTISED_PORT || LISTEN_PORT);
const MAX_PLAYERS = Number(process.env.MAX_PLAYERS || 4);
const HEARTBEAT_SEC = 10;
const REGISTER_RETRY_SEC = 3;

const sim = new GameSim();
const roster = new Map();
const clients = new Map();
let myServerId = null;
let activeLobbyId = null;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function backendRequest(pathname, options = {}) {
  const res = await fetch(`${BACKEND_BASE}${pathname}`, options);
  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
}

async function registerServer() {
  const { status, body } = await backendRequest("/v1/servers/register", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: `game-${LISTEN_PORT}`,
      host: ADVERTISED_HOST,
      port: ADVERTISED_PORT,
      capacity: MAX_PLAYERS
    })
  });
  if (status !== 201 || !body || !body.id) {
    throw new Error(`registration failed (${status}): ${JSON.stringify(body)}`);
  }
  return body.id;
}

async function startRegistration() {
  for (;;) {
    try {
      myServerId = await registerServer();
      console.log(`Registered with backend as ${myServerId} (${ADVERTISED_HOST}:${ADVERTISED_PORT})`);
      break;
    } catch (error) {
      console.error(`Registration failed: ${error.message}`);
      await sleep(REGISTER_RETRY_SEC * 1000);
    }
  }
  setInterval(async () => {
    try {
      await backendRequest(`/v1/servers/${myServerId}/heartbeat`, { method: "POST" });
    } catch (error) {
      console.error(`Heartbeat failed: ${error.message}`);
    }
  }, HEARTBEAT_SEC * 1000);
}

async function validatePlayer(token, lobbyId) {
  if (!token || !lobbyId) return null;
  const me = await backendRequest("/v1/auth/me", {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (me.status !== 200 || !me.body || !me.body.id) return null;
  const lobbies = await backendRequest("/v1/lobbies");
  const lobby = (lobbies.body?.lobbies || []).find((l) => l.id === lobbyId);
  if (!lobby || lobby.state !== "Started" || lobby.gameServerId !== myServerId) return null;
  return { id: me.body.id, username: me.body.username };
}

function send(client, payload) {
  if (client.ws.readyState === 1) {
    client.ws.send(JSON.stringify(payload));
  }
}

function resetServer() {
  for (const [ws, client] of clients) {
    if (client.userId) {
      try {
        ws.close();
      } catch {
        /* ignore */
      }
      clients.delete(ws);
    }
  }
  sim.reset();
  roster.clear();
  activeLobbyId = null;
  console.log("Sim reset (server reclaimed)");
}

function broadcastFull() {
  const snap = buildSnapshot(sim, true);
  snap.usernames = Object.fromEntries(roster);
  for (const client of clients.values()) {
    if (!client.userId) continue;
    send(client, snap);
    client.lastSent = snap;
    client.nextFullSync = sim.tick + Math.round(R.tickRate * 1.0);
  }
}

function clientIntervalTicks(client) {
  const rtt = client.rtt;
  if (rtt <= 100) return 2;
  if (rtt <= 200) return 3;
  return 4;
}

function sendSnapshots() {
  const full = buildSnapshot(sim, true);
  full.usernames = Object.fromEntries(roster);
  for (const client of clients.values()) {
    if (!client.userId) continue;
    if (sim.tick - client.lastSendTick < clientIntervalTicks(client)) continue;
    client.lastSendTick = sim.tick;
    if (!client.lastSent || sim.tick >= client.nextFullSync) {
      send(client, full);
      client.lastSent = full;
      client.nextFullSync = sim.tick + Math.round(R.tickRate * 1.0);
    } else {
      const snap = deltaFrom(full, client.lastSent);
      send(client, snap);
      client.lastSent = full;
    }
  }
}

function createClient(ws) {
  return {
    ws,
    userId: null,
    username: "",
    lastIntent: null,
    rtt: 0,
    lastSendTick: 0,
    nextFullSync: 0,
    lastSent: null,
    intentWindowStart: performance.now(),
    intentCount: 0
  };
}

async function handleMessage(client, data) {
  let msg;
  try {
    msg = JSON.parse(data.toString());
  } catch {
    return;
  }
  if (msg.type === "hello") {
    if (client.userId) {
      send(client, { type: "kick", reason: "already joined" });
      client.ws.close();
      return;
    }
    const user = await validatePlayer(msg.token, msg.lobbyId);
    if (!user) {
      send(client, { type: "kick", reason: "invalid credentials or lobby" });
      client.ws.close();
      return;
    }
    if (activeLobbyId && activeLobbyId !== msg.lobbyId) {
      if (sim.gameOver) {
        resetServer();
      } else {
        send(client, { type: "kick", reason: "this server is already hosting another game" });
        client.ws.close();
        return;
      }
    }
    if (sim.playerCount() >= MAX_PLAYERS) {
      send(client, { type: "kick", reason: "server full" });
      client.ws.close();
      return;
    }
    if (!activeLobbyId) {
      activeLobbyId = msg.lobbyId;
    }
    client.lobbyId = msg.lobbyId;
    client.userId = user.id;
    client.username = user.username;
    sim.addPlayer(user.id, user.username);
    roster.set(user.id, user.username);
    console.log(`Player ${user.username} (${user.id}) connected`);
    send(client, { type: "welcome", playerId: user.id, players: Object.fromEntries(roster) });
    broadcastFull();
  } else if (msg.type === "intent") {
    if (!client.userId) return;
    const now = performance.now();
    if (now - client.intentWindowStart > 1000) {
      client.intentWindowStart = now;
      client.intentCount = 0;
    }
    if (client.intentCount >= 120) return;
    client.intentCount++;
    sim.submitIntent(client.userId, msg);
  } else if (msg.type === "ping") {
    send(client, { type: "pong", t: msg.t });
  }
}

function handleClose(client) {
  clients.delete(client.ws);
  if (client.userId) {
    sim.removePlayer(client.userId);
    roster.delete(client.userId);
    console.log(`Player ${client.username} disconnected`);
    if (sim.players.size === 0) {
      sim.reset();
      activeLobbyId = null;
      console.log("Sim reset (no players)");
    } else {
      broadcastFull();
    }
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, service: "game", players: sim.playerCount() }));
    return;
  }
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

const wss = new WebSocketServer({ noServer: true });
server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req);
  });
});

wss.on("connection", (ws) => {
  const client = createClient(ws);
  clients.set(ws, client);
  ws.on("message", (data) => handleMessage(client, data));
  ws.on("close", () => handleClose(client));
  ws.on("error", () => handleClose(client));
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`Game server listening on ws://${LISTEN_HOST}:${LISTEN_PORT} (tick ${R.tickRate}Hz)`);
});

startRegistration();

setInterval(() => {
  sim.step(R.tickDelta);
  sendSnapshots();
}, 1000 / R.tickRate);

process.on("SIGINT", () => {
  console.log("Shutting down game server");
  process.exit(0);
});
