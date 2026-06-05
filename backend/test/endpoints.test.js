import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { after, before, describe, test } from "node:test";
import { startBackendServer, stopBackendServer } from "../src/app.js";

const DATA_DIR = path.resolve(process.cwd(), "data");
const DB_PATH = path.join(DATA_DIR, "store.db");
const DB_SHM_PATH = `${DB_PATH}-shm`;
const DB_WAL_PATH = `${DB_PATH}-wal`;

let baseUrl = "";

function resetDbFiles() {
  for (const filePath of [DB_PATH, DB_SHM_PATH, DB_WAL_PATH]) {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
  }
}

async function requestJson(method, pathname, token, body) {
  const headers = { "content-type": "application/json" };
  if (token) {
    headers.authorization = `Bearer ${token}`;
  }
  const response = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });
  let payload = {};
  const text = await response.text();
  if (text) {
    payload = JSON.parse(text);
  }
  return { status: response.status, payload };
}

async function registerAndLogin(username, password) {
  const register = await requestJson("POST", "/v1/auth/register", "", { username, password });
  assert.equal(register.status, 201);
  const login = await requestJson("POST", "/v1/auth/login", "", { username, password });
  assert.equal(login.status, 200);
  assert.ok(login.payload.token);
  return login.payload.token;
}

before(async () => {
  resetDbFiles();
  const started = await startBackendServer({ host: "127.0.0.1", port: 0 });
  baseUrl = `http://127.0.0.1:${started.port}`;
});

after(async () => {
  await stopBackendServer();
});

describe("backend endpoints", () => {
  test("health endpoint returns phase 4 metadata", async () => {
    const response = await requestJson("GET", "/health", "", null);
    assert.equal(response.status, 200);
    assert.equal(response.payload.ok, true);
    assert.equal(response.payload.phase, 4);
  });

  test("auth flow supports register, login, and me", async () => {
    const token = await registerAndLogin("test_owner", "secret123");
    const me = await requestJson("GET", "/v1/auth/me", token, null);
    assert.equal(me.status, 200);
    assert.equal(me.payload.username, "test_owner");
  });

  test("lobby password rules reject invalid values and accept alphanumeric 4-11", async () => {
    const token = await registerAndLogin("test_password", "secret123");

    const badPassword = await requestJson("POST", "/v1/lobbies", token, {
      roomName: "Bad Password Room",
      password: "ab!1",
      maxPlayers: 4
    });
    assert.equal(badPassword.status, 400);
    assert.match(badPassword.payload.error, /alphanumeric/i);

    const goodPassword = await requestJson("POST", "/v1/lobbies", token, {
      roomName: "Good Password Room",
      password: "abc1234",
      maxPlayers: 4
    });
    assert.equal(goodPassword.status, 201);
    assert.equal(goodPassword.payload.isPrivate, true);
    assert.equal(goodPassword.payload.state, "Waiting");
  });

  test("join/start scenarios enforce password and assign active server", async () => {
    const ownerToken = await registerAndLogin("test_owner2", "secret123");
    const joinerToken = await registerAndLogin("test_joiner", "secret123");

    const created = await requestJson("POST", "/v1/lobbies", ownerToken, {
      roomName: "Scenario Room",
      password: "room123",
      maxPlayers: 4
    });
    assert.equal(created.status, 201);
    const lobbyId = created.payload.id;

    const wrongJoin = await requestJson("POST", `/v1/lobbies/${lobbyId}/join`, joinerToken, {
      password: "wrong123"
    });
    assert.equal(wrongJoin.status, 403);

    const goodJoin = await requestJson("POST", `/v1/lobbies/${lobbyId}/join`, joinerToken, {
      password: "room123"
    });
    assert.equal(goodJoin.status, 200);
    assert.equal(goodJoin.payload.currentPlayers, 2);

    const noServerStart = await requestJson("POST", `/v1/lobbies/${lobbyId}/start`, ownerToken, {});
    assert.equal(noServerStart.status, 503);

    const registeredServer = await requestJson("POST", "/v1/servers/register", "", {
      name: "Scenario Server",
      host: "127.0.0.1",
      port: 7777,
      capacity: 4
    });
    assert.equal(registeredServer.status, 201);

    const started = await requestJson("POST", `/v1/lobbies/${lobbyId}/start`, ownerToken, {});
    assert.equal(started.status, 200);
    assert.equal(started.payload.lobby.state, "Started");
    assert.equal(started.payload.assignedServer.id, registeredServer.payload.id);
  });
});
