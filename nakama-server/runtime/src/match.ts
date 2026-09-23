import { CONFIG } from "../../../shared/game.js";
import { GameSim, buildSnapshot, deltaFrom } from "./sim.js";

const R = CONFIG;

export const OP = {
  INTENT: 1,
  PING: 2,
  PONG: 3,
  SNAPSHOT: 4,
  START: 5,
  GAMEOVER: 6,
  ROOMINFO: 7
} as const;

const TICK_RATE = R.tickRate;
const SNAPSHOT_EVERY_TICKS = 2;
const MAX_INTENTS_PER_TICK = 10;
const WAITING_IDLE_TICKS = TICK_RATE * 30;

const sims = new Map<string, GameSim>();

interface RoomInfo {
  name: string;
  password: string;
  maxPlayers: number;
  ownerId: string;
}

interface SweatyMatchState extends nkruntime.MatchState {
  matchKey: string;
  phase: string;
  room: RoomInfo;
  started: boolean;
  presences: { [userId: string]: nkruntime.Presence };
  baseline: any;
}

function decodeData(data: ArrayBuffer): string {
  if (typeof TextDecoder !== "undefined") {
    return new TextDecoder().decode(new Uint8Array(data));
  }
  const bytes = new Uint8Array(data);
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

function parseJSON<T>(data: ArrayBuffer): T | null {
  try {
    return JSON.parse(decodeData(data)) as T;
  } catch {
    return null;
  }
}

function roomLabel(state: SweatyMatchState, gameState: string) {
  return JSON.stringify({
    game: "sweaty-candy",
    state: gameState,
    name: state.room.name,
    private: !!state.room.password,
    maxPlayers: state.room.maxPlayers,
    owner: state.room.ownerId
  });
}

function broadcastRoomInfo(state: SweatyMatchState, dispatcher: nkruntime.MatchDispatcher) {
  const players = Object.entries(state.presences).map(([userId, presence]) => ({
    userId,
    username: presence.username
  }));
  dispatcher.broadcastMessage(
    OP.ROOMINFO,
    JSON.stringify({
      name: state.room.name,
      ownerId: state.room.ownerId,
      maxPlayers: state.room.maxPlayers,
      players
    }),
    null,
    null,
    true
  );
}

function ensureOwner(state: SweatyMatchState, dispatcher: nkruntime.MatchDispatcher) {
  if (state.started) return;
  if (!state.room.ownerId || state.presences[state.room.ownerId]) return;
  const first = Object.keys(state.presences)[0];
  if (!first) return;
  state.room.ownerId = first;
  dispatcher.matchLabelUpdate(roomLabel(state, "waiting"));
}

function startGame(state: SweatyMatchState, dispatcher: nkruntime.MatchDispatcher) {
  const sim = sims.get(state.matchKey);
  if (!sim) return;
  for (const [userId, presence] of Object.entries(state.presences)) {
    sim.addPlayer(userId, presence.username);
  }
  state.started = true;
  state.phase = "countdown";
  state.baseline = null;
  dispatcher.matchLabelUpdate(roomLabel(state, "started"));
  dispatcher.broadcastMessage(OP.START, JSON.stringify({}), null, null, true);
}

function broadcastSnapshots(state: SweatyMatchState, dispatcher: nkruntime.MatchDispatcher) {
  const sim = sims.get(state.matchKey);
  if (!sim) return;
  const full: any = buildSnapshot(sim, true);
  const usernames: { [userId: string]: string } = {};
  for (const [userId, presence] of Object.entries(state.presences)) {
    usernames[userId] = presence.username;
  }
  full.usernames = usernames;
  let snap: any = full;
  if (state.baseline) {
    snap = deltaFrom(full, state.baseline);
  }
  state.baseline = full;
  const presences = Object.values(state.presences);
  for (const presence of presences) {
    dispatcher.broadcastMessage(OP.SNAPSHOT, JSON.stringify(snap), [presence], null, false);
  }
}

const matchInit: nkruntime.MatchInitFunction<SweatyMatchState> = (ctx, logger, nk, params) => {
  const name = String(params.name || "").trim() || `Room ${Math.floor(Math.random() * 100000)}`;
  const password = String(params.password || "");
  const maxPlayers = Math.max(2, Math.min(8, Number(params.maxPlayers) || 4));
  const ownerId = String(params.ownerId || "");
  const matchKey = `m${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
  sims.set(matchKey, new GameSim());
  const state: SweatyMatchState = {
    matchKey,
    phase: "waiting",
    room: { name, password, maxPlayers, ownerId },
    started: false,
    presences: {},
    baseline: null
  };
  return { state, tickRate: TICK_RATE, label: roomLabel(state, "waiting") };
};

const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<SweatyMatchState> = (
  ctx,
  logger,
  nk,
  dispatcher,
  tick,
  state,
  presence,
  metadata
) => {
  if (state.phase !== "waiting") {
    return { state, accept: false, rejectMessage: "game in progress" };
  }
  if (Object.keys(state.presences).length >= state.room.maxPlayers) {
    return { state, accept: false, rejectMessage: "room full" };
  }
  if (state.room.password && metadata?.password !== state.room.password) {
    return { state, accept: false, rejectMessage: "wrong lobby password" };
  }
  return { state, accept: true };
};

const matchJoin: nkruntime.MatchJoinFunction<SweatyMatchState> = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  for (const presence of presences) {
    state.presences[presence.userId] = presence;
  }
  ensureOwner(state, dispatcher);
  broadcastRoomInfo(state, dispatcher);
  return { state };
};

const matchLeave: nkruntime.MatchLeaveFunction<SweatyMatchState> = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  for (const presence of presences) {
    delete state.presences[presence.userId];
    if (state.started) {
      const sim = sims.get(state.matchKey);
      if (sim) {
        sim.removePlayer(presence.userId);
      }
    }
  }
  ensureOwner(state, dispatcher);
  broadcastRoomInfo(state, dispatcher);
  return { state };
};

const matchLoop: nkruntime.MatchLoopFunction<SweatyMatchState> = (ctx, logger, nk, dispatcher, tick, state, messages) => {
  if (!state.started) {
    for (const msg of messages) {
      if (msg.opCode !== OP.START) continue;
      if (msg.sender.userId !== state.room.ownerId) continue;
      startGame(state, dispatcher);
      break;
    }
    if (Object.keys(state.presences).length === 0 && tick > WAITING_IDLE_TICKS) {
      return null;
    }
    return { state };
  }

  const sim = sims.get(state.matchKey);
  if (!sim) return { state };

  const intentCounts: { [userId: string]: number } = {};
  for (const msg of messages) {
    if (msg.opCode === OP.INTENT) {
      const userId = msg.sender.userId;
      intentCounts[userId] = (intentCounts[userId] || 0) + 1;
      if (intentCounts[userId] > MAX_INTENTS_PER_TICK) continue;
      const intent = parseJSON<{ tick: number; move: number[]; aim: number[]; shoot: boolean; localSeq: number }>(msg.data);
      if (intent) {
        sim.submitIntent(userId, intent);
      }
    } else if (msg.opCode === OP.PING) {
      const ping = parseJSON<{ t: number }>(msg.data);
      dispatcher.broadcastMessage(OP.PONG, JSON.stringify({ t: ping?.t || 0 }), [msg.sender], null, true);
    }
  }

  sim.step(R.tickDelta);

  if (tick % SNAPSHOT_EVERY_TICKS === 0) {
    broadcastSnapshots(state, dispatcher);
  }

  if (Object.keys(state.presences).length === 0) {
    return null;
  }

  return { state };
};

const matchTerminate: nkruntime.MatchTerminateFunction<SweatyMatchState> = (ctx, logger, nk, dispatcher, tick, state, graceSeconds) => {
  sims.delete(state.matchKey);
  return { state };
};

const matchSignal: nkruntime.MatchSignalFunction<SweatyMatchState> = (ctx, logger, nk, dispatcher, tick, state, data) => {
  return { state, data };
};

const rpcCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }
  let body: { name?: string; password?: string; maxPlayers?: number } = {};
  try {
    body = JSON.parse(payload || "{}");
  } catch {
    body = {};
  }
  const name = String(body.name || "").trim();
  const password = String(body.password || "").trim();
  const maxPlayers = Math.max(2, Math.min(8, Number(body.maxPlayers) || 4));
  if (password && !/^[A-Za-z0-9]{4,11}$/.test(password)) {
    throw new Error("password must be alphanumeric and 4-11 chars");
  }
  const matchId = nk.matchCreate("sweaty_candy", {
    name,
    password,
    maxPlayers,
    ownerId: ctx.userId
  });
  return JSON.stringify({ matchId });
};

export const matchHandler: nkruntime.MatchHandler<SweatyMatchState> = {
  matchInit,
  matchJoinAttempt,
  matchJoin,
  matchLeave,
  matchLoop,
  matchTerminate,
  matchSignal
};

export { rpcCreateRoom };
