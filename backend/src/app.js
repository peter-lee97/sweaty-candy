import http from "node:http";
import path from "node:path";
import { URL } from "node:url";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import { generateGuestId, generateGuestUsername, hashPassword, issueToken, verifyPassword } from "./auth.js";
import { readStore, writeStore } from "./store.js";

const DEFAULT_PORT = Number(process.env.PORT || 8787);
const DEFAULT_HOST = process.env.HOST || "0.0.0.0";
const SERVER_TTL_MS = 60_000;
const GUEST_SESSION_DURATION_MS = Number(process.env.GUEST_SESSION_DURATION_MS || 7200000);
let runningServer = null;
let runningWebSocketServer = null;
const websocketClients = new Set();

function json(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf-8").trim();
  if (!raw) {
    return {};
  }
  return JSON.parse(raw);
}

function parseAuthUser(req, store) {
  const auth = req.headers.authorization || "";
  const [scheme, token] = auth.split(" ");
  if (scheme !== "Bearer" || !token) {
    return null;
  }
  const userId = store.tokens[token];
  if (!userId) {
    return null;
  }
  return store.users.find((u) => u.id === userId) || null;
}

function isAlnum(value) {
  return /^[A-Za-z0-9]+$/.test(value);
}

function normalizeLobby(store, lobby) {
  const assignedServer = lobby.gameServerId ? store.servers.find((s) => s.id === lobby.gameServerId) : null;
  return {
    id: lobby.id,
    name: lobby.name,
    ownerUserId: lobby.ownerUserId,
    currentPlayers: lobby.playerIds.length,
    maxPlayers: lobby.maxPlayers,
    isPrivate: !!lobby.passwordHash,
    state: lobby.state,
    gameServerId: lobby.gameServerId,
    serverHost: assignedServer ? assignedServer.host : "",
    serverPort: assignedServer ? assignedServer.port : 0,
    createdAt: lobby.createdAt
  };
}

function activeServers(store) {
  const now = Date.now();
  return store.servers.filter((s) => now - s.lastHeartbeatAt <= SERVER_TTL_MS);
}

function pickServer(store) {
  const alive = activeServers(store);
  if (alive.length === 0) {
    return null;
  }
  const withLoad = alive.map((server) => {
    const assigned = store.lobbies.filter((lobby) => lobby.state === "Started" && lobby.gameServerId === server.id).length;
    const capacity = Math.max(1, Number(server.capacity || 1));
    return { server, assigned, ratio: assigned / capacity };
  });
  withLoad.sort((a, b) => a.ratio - b.ratio || a.assigned - b.assigned);
  return withLoad[0].server;
}

function broadcastLobbySnapshot(store, reason, lobbyId = "") {
  if (websocketClients.size === 0) {
    return;
  }
  const payload = JSON.stringify({
    type: "lobbies_updated",
    reason,
    lobbyId,
    lobbies: store.lobbies.map((lobby) => normalizeLobby(store, lobby))
  });
  for (const socket of websocketClients) {
    if (socket.readyState === 1) {
      socket.send(payload);
    }
  }
}

function setupLobbyEventsSocket(server) {
  const websocketServer = new WebSocketServer({ noServer: true });
  websocketServer.on("connection", (socket) => {
    websocketClients.add(socket);
    socket.on("close", () => {
      websocketClients.delete(socket);
    });
    const store = readStore();
    socket.send(
      JSON.stringify({
        type: "lobbies_updated",
        reason: "initial",
        lobbyId: "",
        lobbies: store.lobbies.map((lobby) => normalizeLobby(store, lobby))
      })
    );
  });

  server.on("upgrade", (req, socket, head) => {
    const requestUrl = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (requestUrl.pathname !== "/v1/lobbies/events") {
      socket.destroy();
      return;
    }
    const token = String(requestUrl.searchParams.get("token") || "");
    if (!token) {
      socket.destroy();
      return;
    }
    const store = readStore();
    const userId = store.tokens[token];
    if (!userId) {
      socket.destroy();
      return;
    }
    websocketServer.handleUpgrade(req, socket, head, (ws) => {
      websocketServer.emit("connection", ws, req);
    });
  });

  return websocketServer;
}

function createBackendServer() {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
      const { pathname } = url;
      const method = req.method || "GET";
      const store = readStore();

      if (pathname === "/health" && method === "GET") {
        return json(res, 200, { ok: true, service: "backend", phase: 4 });
      }

      if (pathname === "/v1/auth/register" && method === "POST") {
        const body = await readBody(req);
        const username = String(body.username || "").trim();
        const password = String(body.password || "");
        if (!username || password.length < 6) {
          return json(res, 400, { error: "username and password(min 6) are required" });
        }
        if (store.users.some((u) => u.username.toLowerCase() === username.toLowerCase())) {
          return json(res, 409, { error: "username already exists" });
        }
        store.lastUserId += 1;
        const user = {
          id: `u${store.lastUserId}`,
          username,
          passwordHash: hashPassword(password),
          createdAt: Date.now()
        };
        store.users.push(user);
        writeStore(store);
        return json(res, 201, { id: user.id, username: user.username });
      }

      if (pathname === "/v1/auth/login" && method === "POST") {
        const body = await readBody(req);
        const username = String(body.username || "").trim();
        const password = String(body.password || "");
        const user = store.users.find((u) => u.username.toLowerCase() === username.toLowerCase());
        if (!user || !verifyPassword(password, user.passwordHash)) {
          return json(res, 401, { error: "invalid credentials" });
        }
        const token = issueToken();
        store.tokens[token] = user.id;
        writeStore(store);
        return json(res, 200, { token, user: { id: user.id, username: user.username } });
      }

      if (pathname === "/v1/auth/guest" && method === "POST") {
        const username = generateGuestUsername(["apple", "banana", "cherry", "grape", "kiwi", "lemon", "mango", "orange", "peach", "plum"], ["red", "blue", "green", "yellow", "purple", "orange", "pink", "white", "black", "teal"]);
        if (store.users.some((u) => u.username.toLowerCase() === username.toLowerCase()) || store.guestSessions[username]) {
          return json(res, 409, { error: "username already exists, please try again" });
        }
        const guestId = generateGuestId();
        const createdAt = Date.now();
        const expiresAt = createdAt + GUEST_SESSION_DURATION_MS;
        store.users.push({
          id: guestId,
          username,
          createdAt
        });
        store.guestSessions[guestId] = { createdAt, expiresAt };
        const token = issueToken();
        store.tokens[token] = guestId;
        writeStore(store);
        return json(res, 201, { id: guestId, username, token });
      }

      if (pathname === "/v1/auth/refresh" && method === "POST") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        if (!user.id.startsWith("guest_")) {
          return json(res, 400, { error: "only guest sessions can be refreshed" });
        }
        const guestSession = store.guestSessions[user.id];
        if (!guestSession) {
          return json(res, 404, { error: "guest session not found" });
        }
        const newExpiresAt = Date.now() + GUEST_SESSION_DURATION_MS;
        guestSession.expiresAt = newExpiresAt;
        writeStore(store);
        return json(res, 200, { ok: true, expiresAt: newExpiresAt });
      }

      if (pathname === "/v1/auth/me" && method === "GET") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        return json(res, 200, { id: user.id, username: user.username });
      }

      if (pathname === "/v1/servers/register" && method === "POST") {
        const body = await readBody(req);
        const host = String(body.host || "").trim();
        const port = Number(body.port || 0);
        if (!host || port <= 0) {
          return json(res, 400, { error: "host and port are required" });
        }
        store.lastServerId += 1;
        const registered = {
          id: `s${store.lastServerId}`,
          name: String(body.name || `Server ${store.lastServerId}`),
          host,
          port,
          capacity: Number(body.capacity || 4),
          lastHeartbeatAt: Date.now(),
          createdAt: Date.now()
        };
        store.servers.push(registered);
        writeStore(store);
        broadcastLobbySnapshot(store, "server_registered");
        return json(res, 201, registered);
      }

      if (pathname.startsWith("/v1/servers/") && pathname.endsWith("/heartbeat") && method === "POST") {
        const serverId = pathname.split("/")[3];
        const found = store.servers.find((s) => s.id === serverId);
        if (!found) {
          return json(res, 404, { error: "server not found" });
        }
        found.lastHeartbeatAt = Date.now();
        writeStore(store);
        return json(res, 200, { ok: true, serverId });
      }

      if (pathname === "/v1/servers" && method === "GET") {
        return json(res, 200, { servers: activeServers(store) });
      }

      if (pathname === "/v1/lobbies" && method === "GET") {
        return json(res, 200, { lobbies: store.lobbies.map((l) => normalizeLobby(store, l)) });
      }

      if (pathname === "/v1/lobbies" && method === "POST") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        const body = await readBody(req);
        const roomNameRaw = String(body.roomName || "").trim();
        const passwordRaw = String(body.password || "").trim();
        const maxPlayers = Math.max(2, Math.min(8, Number(body.maxPlayers || 4)));
        if (passwordRaw && (!isAlnum(passwordRaw) || passwordRaw.length < 4 || passwordRaw.length > 11)) {
          return json(res, 400, { error: "password must be alphanumeric and 4-11 chars" });
        }
        store.lastLobbyId += 1;
        const lobby = {
          id: `r${store.lastLobbyId}`,
          name: roomNameRaw || `Room r${store.lastLobbyId}`,
          ownerUserId: user.id,
          playerIds: [user.id],
          maxPlayers,
          passwordHash: passwordRaw ? hashPassword(passwordRaw) : "",
          state: "Waiting",
          gameServerId: "",
          createdAt: Date.now()
        };
        store.lobbies.push(lobby);
        writeStore(store);
        broadcastLobbySnapshot(store, "lobby_created", lobby.id);
        return json(res, 201, normalizeLobby(store, lobby));
      }

      if (pathname.startsWith("/v1/lobbies/") && pathname.endsWith("/join") && method === "POST") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        const lobbyId = pathname.split("/")[3];
        const lobby = store.lobbies.find((l) => l.id === lobbyId);
        if (!lobby) {
          return json(res, 404, { error: "lobby not found" });
        }
        if (lobby.state !== "Waiting") {
          return json(res, 409, { error: "lobby already started" });
        }
        if (!lobby.playerIds.includes(user.id) && lobby.playerIds.length >= lobby.maxPlayers) {
          return json(res, 409, { error: "lobby full" });
        }
        if (lobby.passwordHash) {
          const body = await readBody(req);
          const provided = String(body.password || "");
          if (!verifyPassword(provided, lobby.passwordHash)) {
            return json(res, 403, { error: "invalid lobby password" });
          }
        }
        if (!lobby.playerIds.includes(user.id)) {
          lobby.playerIds.push(user.id);
        }
        writeStore(store);
        broadcastLobbySnapshot(store, "lobby_joined", lobby.id);
        return json(res, 200, normalizeLobby(store, lobby));
      }

      if (pathname.startsWith("/v1/lobbies/") && pathname.endsWith("/leave") && method === "POST") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        const lobbyId = pathname.split("/")[3];
        const lobby = store.lobbies.find((l) => l.id === lobbyId);
        if (!lobby) {
          return json(res, 404, { error: "lobby not found" });
        }
        lobby.playerIds = lobby.playerIds.filter((id) => id !== user.id);
        if (lobby.playerIds.length === 0) {
          store.lobbies = store.lobbies.filter((l) => l.id !== lobby.id);
        } else if (lobby.ownerUserId === user.id) {
          lobby.ownerUserId = lobby.playerIds[0];
        }
        writeStore(store);
        broadcastLobbySnapshot(store, "lobby_left", lobby.id);
        return json(res, 200, { ok: true });
      }

      if (pathname.startsWith("/v1/lobbies/") && pathname.endsWith("/start") && method === "POST") {
        const user = parseAuthUser(req, store);
        if (!user) {
          return json(res, 401, { error: "unauthorized" });
        }
        const lobbyId = pathname.split("/")[3];
        const lobby = store.lobbies.find((l) => l.id === lobbyId);
        if (!lobby) {
          return json(res, 404, { error: "lobby not found" });
        }
        if (lobby.ownerUserId !== user.id) {
          return json(res, 403, { error: "only owner can start lobby" });
        }
        if (lobby.state !== "Waiting") {
          return json(res, 409, { error: "lobby already started" });
        }
        const serverPick = pickServer(store);
        if (!serverPick) {
          return json(res, 503, { error: "no active game server available" });
        }
        lobby.state = "Started";
        lobby.gameServerId = serverPick.id;
        writeStore(store);
        broadcastLobbySnapshot(store, "lobby_started", lobby.id);
        return json(res, 200, {
          lobby: normalizeLobby(store, lobby),
          assignedServer: {
            id: serverPick.id,
            host: serverPick.host,
            port: serverPick.port
          }
        });
      }

      return json(res, 404, { error: "not found" });
    } catch (error) {
      return json(res, 500, { error: "internal server error", details: String(error.message || error) });
    }
  });
}

export async function startBackendServer(options = {}) {
  if (runningServer) {
    throw new Error("Backend server already running");
  }
  const host = options.host || DEFAULT_HOST;
  const port = Number(options.port || DEFAULT_PORT);
  const server = createBackendServer();
  const websocketServer = setupLobbyEventsSocket(server);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  runningServer = server;
  runningWebSocketServer = websocketServer;
  const address = server.address();
  return {
    server,
    host,
    port: typeof address === "object" && address ? address.port : port
  };
}

export async function stopBackendServer() {
  if (!runningServer) {
    return;
  }
  for (const socket of websocketClients) {
    socket.close();
  }
  websocketClients.clear();
  if (runningWebSocketServer) {
    runningWebSocketServer.close();
    runningWebSocketServer = null;
  }
  const server = runningServer;
  runningServer = null;
  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

function isDirectExecution() {
  if (!process.argv[1]) {
    return false;
  }
  return path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

function cleanupExpiredGuestSessions() {
  const store = readStore();
  const now = Date.now();
  let cleanedCount = 0;
  for (const [guestId, session] of Object.entries(store.guestSessions)) {
    if (session.expiresAt < now) {
      delete store.guestSessions[guestId];
      store.users = store.users.filter((u) => u.id !== guestId);
      cleanedCount++;
    }
  }
  if (cleanedCount > 0) {
    writeStore(store);
    console.log(`Cleaned up ${cleanedCount} expired guest sessions`);
  }
}

if (isDirectExecution()) {
  cleanupExpiredGuestSessions();
  startBackendServer()
    .then(({ host, port }) => {
      console.log(`Backend listening on http://${host}:${port}`);
      console.log(`Guest session duration: ${GUEST_SESSION_DURATION_MS / 1000 / 60} minutes`);
    })
    .catch((error) => {
      console.error(`Failed to start backend: ${error.message}`);
      process.exit(1);
    });
}
