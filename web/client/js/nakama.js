import { Client, Session } from "@heroiclabs/nakama-js";
import { loadAuth, saveAuth, clearAuth } from "./auth.js";

export const OP = {
  INTENT: 1,
  PING: 2,
  PONG: 3,
  SNAPSHOT: 4,
  START: 5,
  GAMEOVER: 6,
  ROOMINFO: 7
};

export const GAME = "sweaty-candy";

const FRUITS = ["apple", "banana", "cherry", "grape", "kiwi", "lemon", "mango", "orange", "peach", "plum"];
const COLORS = ["red", "blue", "green", "yellow", "purple", "orange", "pink", "white", "black", "teal"];

let client = null;
let socket = null;

function baseUrl() {
  const { protocol, hostname, port } = window.location;
  const isDev = port === "8787" || hostname === "127.0.0.1" || hostname === "localhost";
  return isDev ? `${protocol}//${hostname}:7350` : window.location.origin;
}

export function getClient() {
  if (client) return client;
  const u = new URL(baseUrl());
  const useSSL = u.protocol === "https:";
  const port = u.port || (useSSL ? "443" : "80");
  client = new Client("defaultkey", u.hostname, port, useSSL);
  return client;
}

export function decodeData(data) {
  if (typeof data === "string") return data;
  return new TextDecoder().decode(new Uint8Array(data));
}

export function getSocket() {
  return socket;
}

export async function connectSocket(session) {
  const c = getClient();
  if (socket) {
    try {
      socket.disconnect(false);
    } catch {
      /* ignore */
    }
    socket = null;
  }
  socket = c.createSocket(c.useSSL);
  await socket.connect(session);
  return socket;
}

export function persistSession(session) {
  return {
    userId: session.user_id,
    username: session.username,
    token: session.token,
    refreshToken: session.refresh_token,
    createTime: session.created_at,
    expireTime: session.expires_at
  };
}

export async function ensureIdentity(app, username) {
  const c = getClient();
  if (app.auth && app.auth.token) {
    try {
      const restored = Session.restore(app.auth.token, app.auth.refreshToken);
      const now = Date.now() / 1000;
      if (!restored.isexpired(now)) {
        app.session = restored;
        return restored;
      }
      if (restored.refresh_token && !restored.isrefreshexpired(now)) {
        const refreshed = await c.sessionRefresh(restored);
        app.session = refreshed;
        app.auth = persistSession(refreshed);
        saveAuth(app.auth);
        return refreshed;
      }
    } catch {
      /* fall through to fresh sign in */
    }
    clearAuth();
    app.auth = null;
  }
  const session = await guestSignIn(username);
  app.session = session;
  app.auth = persistSession(session);
  saveAuth(app.auth);
  return session;
}

function deviceId() {
  try {
    let id = localStorage.getItem("sweaty.device.v1");
    if (!id) {
      id = crypto.randomUUID ? crypto.randomUUID() : `dev-${Date.now()}-${Math.random()}`;
      localStorage.setItem("sweaty.device.v1", id);
    }
    return id;
  } catch {
    return `dev-${Date.now()}-${Math.random()}`;
  }
}

function genName() {
  const fruit = FRUITS[Math.floor(Math.random() * FRUITS.length)];
  const color = COLORS[Math.floor(Math.random() * COLORS.length)];
  const suffix = Math.floor(Math.random() * 900 + 100);
  return fruit + color + suffix;
}

export async function guestSignIn(username) {
  const c = getClient();
  const requested = (username || "").trim();
  if (requested && !/^[A-Za-z0-9_ ]{3,20}$/.test(requested)) {
    throw new Error("Username must be 3-20 characters (letters, numbers, space, underscore)");
  }
  const id = deviceId();
  const candidates = requested
    ? [requested, ...Array.from({ length: 20 }, genName)]
    : Array.from({ length: 50 }, genName);
  let lastErr = null;
  for (const name of candidates) {
    try {
      return await c.authenticateCustom(id, true, name);
    } catch (err) {
      lastErr = err;
      if (!(err && (err.status === 409 || err.code === 5))) {
        throw err;
      }
      if (requested && name === requested) {
        throw new Error("Username already taken");
      }
    }
  }
  throw lastErr || new Error("Could not create account");
}

export function roomFromLabel(label) {
  try {
    const parsed = typeof label === "string" ? JSON.parse(label) : label;
    if (parsed && parsed.game === GAME) {
      return parsed;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export async function listRooms(session) {
  const c = getClient();
  const res = await c.listMatches(session, 50, true, "", 0, 8, `+label.game:${GAME}`);
  const rooms = [];
  for (const m of (res.matches || [])) {
    const label = roomFromLabel(m.label);
    if (!label) continue;
    rooms.push({
      id: m.match_id,
      name: label.name,
      private: label.private,
      maxPlayers: label.maxPlayers,
      ownerId: label.owner,
      state: label.state,
      currentPlayers: m.size || 0
    });
  }
  return rooms;
}

export async function createRoom(session, opts) {
  const c = getClient();
  const res = await c.rpc(session, "create_room", {
    name: opts.name || "",
    password: opts.password || "",
    maxPlayers: opts.maxPlayers
  });
  return res.payload.matchId;
}
