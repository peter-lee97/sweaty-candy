import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const DATA_DIR = path.resolve(process.cwd(), "data");
const DB_PATH = path.join(DATA_DIR, "store.db");
const LEGACY_JSON_PATH = path.join(DATA_DIR, "store.json");

const EMPTY_STORE = {
  users: [],
  tokens: {},
  guestSessions: {},
  lobbies: [],
  servers: [],
  lastUserId: 0,
  lastLobbyId: 0,
  lastServerId: 0
};

let db = null;

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function getDb() {
  if (db) {
    return db;
  }
  ensureDataDir();
  db = new DatabaseSync(DB_PATH);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS key_value (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `);
  ensureAppStateSeeded(db);
  return db;
}

function ensureAppStateSeeded(database) {
  const existing = database.prepare("SELECT value FROM key_value WHERE key = ?").get("app_state");
  if (existing) {
    return;
  }
  const migrated = readLegacyStore();
  const seeded = migrated || EMPTY_STORE;
  database
    .prepare(`
      INSERT INTO key_value (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `)
    .run("app_state", JSON.stringify(seeded));
}

function readLegacyStore() {
  if (!fs.existsSync(LEGACY_JSON_PATH)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(LEGACY_JSON_PATH, "utf-8");
    const parsed = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) {
      return null;
    }
    return {
      ...EMPTY_STORE,
      ...parsed,
      guestSessions: parsed.guestSessions || {}
    };
  } catch {
    return null;
  }
}

export function readStore() {
  const database = getDb();
  const row = database.prepare("SELECT value FROM key_value WHERE key = ?").get("app_state");
  if (!row) {
    return { ...EMPTY_STORE };
  }
  const store = JSON.parse(row.value);
  return {
    ...EMPTY_STORE,
    ...store,
    guestSessions: store.guestSessions || {}
  };
}

export function writeStore(store) {
  const database = getDb();
  database
    .prepare(`
      INSERT INTO key_value (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `)
    .run("app_state", JSON.stringify(store));
}
