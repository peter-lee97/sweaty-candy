# AGENTS.md — Sweaty Candy

Boxhead-inspired isometric multiplayer horde shooter, rewritten as a web app (HTML/JS + Phaser 4.2.1, no Godot).
Authoritative game server: Nakama (Go) running a TypeScript match handler at 60Hz.
Game logic is 2D top-down; only rendering is isometric (2:1 diamond projection).
Shapes and colors identify entities instead of sprites.
Desktop uses mouse + keyboard; mobile web uses virtual twin-sticks.

## Architecture

- **`web/client/`** — Browser client. Vanilla JS ES modules + Phaser 4.2.1 (WebGL), no build step. Talks to Nakama via `@heroiclabs/nakama-js` (vendored at `web/client/vendor/`).
- **`nakama-server/`** — Nakama + Postgres stack. `docker-compose-postgres.yml` for dev, `runtime/` holds the TypeScript runtime (RPC + authoritative match handler) built with esbuild to `modules/build/index.js`. `sim.js` (the 60Hz sim) lives in `runtime/src/`.
- **`web/server.js`** — Tiny Node static server (serves `web/client/` + `/shared/` + `/health` on 8787). Replaces the old backend static serving.
- **`shared/game.js`** — Single source of truth for gameplay constants, map, obstacles, and pure helpers. Imported by the browser client (`/shared/game.js`) and the Nakama runtime (`../../../shared/game.js`).
- **`Dockerfile.nakama`** / **`Dockerfile.static`** / **`docker-compose.prod.yml`** — Production images + compose (Nakama + Postgres + static).

Key rule: **clients are never authoritative**. Input → intent → server validates → state change.
Input never directly mutates position/health on the network path.

## Authentication

Credential-less guest-first auth via Nakama custom auth. Users land on main menu and can play immediately.

- No passwords. Optional display name (3-20 chars: letters, numbers, space, underscore); auto-generated `fruit+color+number` if skipped.
- Guest identity = a stable device id (`crypto.randomUUID`) stored in `localStorage` under `sweaty.device.v1`; the account is created with `authenticateCustom(deviceId, create=true, username)`.
- Session (token + refresh token) stored in `localStorage` under key `sweaty.auth.v1` (`{ userId, username, token, refreshToken, createTime, expireTime }`). Token expiry `7200s`, refresh `604800s` (Nakama config).
- The menu pre-fills the current identity. The name field only applies when no valid token exists (`ensureIdentity` in `web/client/js/nakama.js` restores/refreshes an existing session first).
- Sessions are refreshed with `client.sessionRefresh(session)` when near expiry.
- Logout: not yet implemented in the UI. Clearing `sweaty.auth.v1` + `sweaty.device.v1` from localStorage logs out.

### Nakama API (replaces the old REST backend)

| Operation | Nakama call |
|---|---|
| Guest sign in | `client.authenticateCustom(deviceId, true, username)` |
| Restore session | `Session.restore(token, refreshToken)` |
| Refresh session | `client.sessionRefresh(session)` |
| Create room | `client.rpc(session, "create_room", { name, password, maxPlayers })` |
| List rooms | `client.listMatches(session, 50, true, "", 0, 8, "+label.game:sweaty-candy +label.state:waiting")` |
| Join / leave | `socket.joinMatch(matchId, undefined, { password })` / `socket.leaveMatch(matchId)` |
| Game messages | `socket.sendMatchState(matchId, opCode, JSON)` + `socket.onmatchdata` |

## Project Layout

```
shared/
  game.js                # CONFIG, ENEMY_TYPES, MAP, wave/difficulty formulas, collision helpers

web/client/
  index.html             # Single page: screens + canvas + HUD + touch sticks + importmap
  css/style.css
  vendor/nakama-js.esm.mjs   # @heroiclabs/nakama-js SDK (vendored, no build step)
  js/
    main.js              # Boot, auth state, screen routing, Nakama socket wiring
    auth.js              # localStorage session helpers
    nakama.js            # Nakama client: auth, session refresh, rooms, socket, OP codes
    screens/
      manager.js         # setScreen(app, name) toggles menu/lobby/waiting + tracks app.screen
      menu.js, lobby.js, waiting.js
    game/
      GameScene.js         # Phaser scene orchestration: game loop, prediction, interpolation, FX
      net.js               # Nakama socket transport: intents out, snapshots in, prediction history, RTT
      InputManager.js      # WASD/mouse + touch twin-sticks
      IsometricRenderer.js # Phaser-based isometric renderer (2:1 diamond projection)
      EntityManager.js     # Entity state management (players, enemies, projectiles, pickups)
      ParticleManager.js   # Visual effects (hit flash, death particles, FX)
      hud.js               # Health bar, banner, ping, player list, game-over overlay

nakama-server/
  docker-compose-postgres.yml  # Dev: Nakama + Postgres (7350/7351, mounts repo into /nakama/data)
  runtime/
    package.json, tsconfig.json, src/nkruntime.d.ts
    src/main.ts            # InitModule: registers create_room RPC + sweaty_candy match handler
    src/match.ts           # Authoritative match handler + RPC (port of the old game server)
    src/sim.js             # 60Hz simulation + snapshot building (full/delta), unchanged from old gameserver
  modules/build/index.js   # esbuild output (gitignored), loaded via --runtime.js_entrypoint

web/server.js              # Tiny Node static server (web/client + /shared, port 8787)
client/  server/           # Legacy Godot projects, kept for reference only (no longer run)
tools/Caddyfile.local      # Optional local proxy: /v2/* → 7350, else → 8787
dev.sh                     # Builds runtime, starts Nakama compose, starts static server
```

## Phaser Setup

The client uses Phaser 4.2.1 via CDN with an importmap for ES module loading:

- `index.html` contains importmap pointing to `https://cdn.jsdelivr.net/npm/phaser@4.2.1/dist/phaser.esm.js`
- `js/loader.js` pre-loads Phaser and exposes it as `window.Phaser`
- `js/main.js` imports Phaser from window and creates the Phaser game instance
- Game lifecycle managed through Phaser scenes (GameScene)
- The Phaser game renders into `#game-container` div, replacing the old Canvas element

## Client Screens

Menu → (auth) → Main Lobby → Waiting Room → Game → Game Over → back to Lobby.

- Menu: optional display name + Play.
- Main Lobby: room table polled every 2.5s via Nakama match listing, Create Room modal (name, optional password, max players), Refresh, Back.
- Waiting Room: player list with owner tag, Start (owner only), Leave. Driven by `OP.ROOMINFO` broadcasts; auto-starts the game on `OP_START`.
- Game Over: survived levels + shots fired, Back to Lobby.

## Rendering (Isometric)

- Projection: `screenX = (x - y) * H`, `screenY = (x + y) * V` with `H = 1.0`, `V = 0.5` (2:1 diamond). Game logic stays 2D.
- Painter's algorithm: drawables sorted by `x + y`. Obstacles drawn as extruded cubes (top face + two side faces).
- Camera follows local player with lerp; mouse wheel zooms (0.25x - 1.6x).
- Entity shapes/colors:
  - Local player: blue circle with white dot + aim tick. Remote players: light-blue circle.
  - Base enemy: red rotated square. Fast enemy: orange triangle (points at target). Tank enemy: purple hexagon.
  - Projectiles: yellow diamonds. Ghost projectiles identical until matched.
  - Health pickups: pulsing green cross.
  - Obstacles: brown cubes. Arena floor: dark diamond + subtle grid.
- Hit flash: white overlay 0.1s. Death/hit particles: expanding fading circles.
- Enemies have HP bars when damaged; player has name label.
- Rendering is handled by Phaser 4.2.1 WebGL engine with custom isometric projection in GameScene and IsometricRenderer.

## Gameplay Systems

- **Player**: WASD/arrows movement. The player faces the direction they move; projectiles fire in the facing direction. Hold left-click to fire (desktop). Twin-stick: left = move, right = fire (mobile). Move speed 300, max health 100.
- **Weapon**: single blaster. 2.5 shots/s (0.4s cooldown), 25 dmg, 500 u/s projectile, infinite ammo, 18-unit hit radius.
- **Enemies** (chase nearest living player, contact damage, knockback on hit):
  - **Base** (red square) — 50 HP, speed 125, 10 dmg
  - **Fast** (orange triangle) — 25 HP, speed 250, 8 dmg (wave 3+)
  - **Tank** (purple hexagon) — 150 HP, speed 70, 20 dmg (wave 5+)
  - Difficulty scaling: HP +5%/level, speed +1.5%/level (capped at 1.5x).
- **Levels = waves**: enemy count scales with level (5 → 6 → 8 → 8 + floor((level-7)/2)), multiplied by `1 + (players-1) * 0.5`, capped at 100. 5s start countdown, 0.35s spawn stagger, 3s between levels. Wave 3+ mixes fast, wave 5+ mixes tank (round-robin composition).
- **Pickups**: 15% drop chance on kill, +25 HP, 10s lifetime.
- **Respawn** (multiplayer only): `clamp(5 + (level-1) * 0.5, 5, 10)` seconds. Game over when all players are dead.
- **Map**: 2800×2800 arena, 7 obstacles (3 bar walls + 4 corner blocks), defined in `shared/game.js`. Obstacles block players, projectiles, and enemy contact.

## Multiplayer Systems

### Lobby Flow

1. Main Menu → Play (guest auth) → Main Lobby
2. Main Lobby → Create Room / Join Room → Waiting Room
3. Waiting Room → Start (owner) → auto-connect to Game Server

### Nakama Match (`nakama-server/runtime/src/match.ts`)

A single authoritative match handler `sweaty_candy` runs the lobby phase and the game
in the same match. It is created by the `create_room` RPC with `{ name, password, maxPlayers, ownerId }`.

- **matchInit** → state `{ matchKey, phase: "waiting", room, started, presences, baseline }`, tick rate 60, label JSON `{ game, state, name, private, maxPlayers, owner }`.
- **matchJoinAttempt** → rejects when the game already started, when full, or on wrong lobby password (passed via join `metadata`).
- **matchJoin / matchLeave** → track presences, broadcast `OP.ROOMINFO` (player list + owner), reassign owner if the owner leaves while waiting.
- **matchLoop** (60Hz):
  - waiting phase: `OP_START` from the owner starts the sim, adds all presences as players, updates the label to `state:"started"`, broadcasts `OP_START`.
  - game phase: `OP_INTENT` → `sim.submitIntent`; `OP_PING` → echo `OP_PONG`; then `sim.step(1/60)`; every 2nd tick broadcast a delta `OP_SNAPSHOT` (full first).
  - terminates when the match has no presences (or after 30s idle in waiting).
- **State round-trip**: Nakama exports match state to Go between callbacks, so state must be plain data. **Never store class instances or `Map`s in match state.** The `GameSim` lives in a module-level `Map` keyed by `state.matchKey` (each match has its own goja runtime, so the registry is per-match).

### Opcodes

| Op | Name | Direction |
|----|------|-----------|
| 1 | `INTENT` | client → server (`{ tick, move, aim, shoot, localSeq }`) |
| 2 | `PING` / `PONG` | client ↔ server (`{ t }`) |
| 4 | `SNAPSHOT` | server → client (JSON, full first then deltas) |
| 5 | `START` | server → all (game started) |
| 6 | `GAMEOVER` | server → all (reliable) |
| 7 | `ROOMINFO` | server → all (waiting-room player list + owner) |

### Game Server Behaviour

- Authoritative simulation on a fixed 60Hz tick (`match_loop` at tick rate 60, `sim.step(1/60)`).
- Per-player intent queue in the sim (cap 16, drops oldest); hold-last idle policy; per-tick intent cap (10/user).
- Snapshots: 30Hz (every 2nd tick). Full sync on the first snapshot after start; otherwise delta sync (changed entities + removed lists).
- Payloads are JSON. Snapshot shape:

```json
{
  "type": "snapshot",
  "serverTick": int, "wave": int, "phase": "countdown|spawning|active|intermission",
  "phaseTimer": float, "gameOver": bool, "full": bool,
  "players": { "id": { "position": [x,y], "aim": [x,y], "health": int, "alive": bool, "respawnTimer": float, "lastInputTick": int } },
  "enemies": { "id": { "position": [x,y], "type": "base|fast|tank", "hp": int, "maxHp": int } },
  "projectiles": { "id": { "position": [x,y], "direction": [x,y], "localSeq": int } },
  "pickups": { "id": { "position": [x,y] } },
  "removedPlayers": [], "removedEnemies": [], "removedProjectiles": [], "removedPickups": [],
  "usernames": { "id": "name" }
}
```

### Client Networking

- Transport is the Nakama socket (`socket.sendMatchState(matchId, opCode, JSON)` / `socket.onmatchdata`), decoded by `net.js`. Intents and pings go out as match messages; snapshots/pongs come back the same way.
- Local player: prediction + reconciliation. Prediction history keyed by input tick (cap 60). Error blended over 120ms; hard snap beyond 60px.
- Remote entities: snapshot buffer (cap 12) interpolated at 150ms render delay; render tick = server tick estimate - 9 ticks.
- Ghost projectiles: local shot feedback keyed by `localSeq`, dropped when the server projectile arrives, expire after 500ms.
- Ping every 1s; RTT = average of last 5 samples (drives snapshot-rate and ping color).
- `serverTickEstimate` = last snapshot tick + RTT/2, advanced by dt each frame.

## Client Input

- Desktop: WASD/arrows move (player faces movement direction), hold LMB fire, wheel zoom. Detected when not touch-capable.
- Mobile: `detectTouch()` (ontouchstart or coarse pointer + maxTouchPoints > 0). Left stick = move (player faces movement direction), right stick = fire. Sticks use Pointer Events with pointer capture; deadzone 0.15.
- Touch controls are DOM overlays (`#touch-controls`), shown only when `Input.isTouch`.

## Commands

```bash
./dev.sh                          # Build runtime, start Nakama compose + static server (8787); open http://127.0.0.1:8787
cd nakama-server/runtime && npm run build    # Rebuild the Nakama runtime bundle (esbuild → modules/build/index.js)
docker compose -f nakama-server/docker-compose-postgres.yml up -d   # Start Nakama + Postgres only
docker logs -f nakama             # Nakama logs
```

For local multiplayer testing use two different origins so localStorage identities stay isolated,
e.g. one tab at `http://127.0.0.1:8787` and one at `http://localhost:8787`.

## JS Conventions

- ES modules everywhere; browser client imports absolute `/shared/game.js`, the Nakama runtime imports `../../../shared/game.js` and is bundled with esbuild (format `cjs`, no exports in `main.ts`).
- Phaser 4.2.1 framework (loaded via CDN), no build step, no bundler on the client.
- Static typing not available in the client; name variables/params clearly.
- No comments in code unless explicitly requested.
- Pure data/helpers live in `shared/game.js`; no DOM or Node imports there.
- DOM element access via `document.getElementById` with ids defined once in `index.html`.
- `app` object in `main.js` holds cross-screen state (auth, session, socket, currentRoom, game) and is exposed as `window.__app` for debugging.
- Nakama runtime: `main.ts` must register `InitModule` as a top-level `function` (the goja AST parser rejects arrow functions and bundler wrappers); the runtime bundle is loaded via `--runtime.js_entrypoint build/index.js`.

## Common Pitfalls

- **Same-origin localStorage**: two browser tabs on the same origin share the same identity. Use different origins (127.0.0.1 vs localhost) for multi-client local tests.
- **`app.screen` must be set via `setScreen(app, name)`** in `screens/manager.js`; the waiting room live-update and auto-start logic branches on it.
- **Socket lifecycle**: connect the Nakama socket once when entering the Main Lobby (`showLobbyScreen`). Keep it open through the waiting room; it drives both the room list and the game transport.
- **Join-time `ROOMINFO` can arrive before the waiting screen**: `main.js` buffers the latest room info and seeds `app.currentRoom` in `enterWaiting`, so the player list is never empty.
- **Name field only applies to new sessions**: the menu re-validates an existing stored token and keeps it; clearing `sweaty.auth.v1` + `sweaty.device.v1` + reload is how to switch identity.
- **Never send `shoot` when dead**: the client gates firing on `myAlive`; the server ignores intent movement for dead players.
- **Snapshot `type` field is required**: `buildSnapshot`/`deltaFrom` must set `type: "snapshot"` or the client ignores the message.
- **Match state round-trips through Go**: only store plain data in match state; `GameSim` instances and `Map`s must live outside it (module-level registry keyed by `state.matchKey`).
- **Runtime bundle must expose `InitModule` at the top level**: `main.ts` uses `function InitModule(...)` (not an arrow) and no `export`; esbuild must run with `--format=cjs` and no exported entry symbols.
- **Server and client must share the same `shared/game.js`**: prediction assumes identical constants/map; drift causes visible snapping.
- **Solo death = game over**: the sim freezes when every player is dead (`gameOver`), so respawn only matters with ≥ 2 players.
- **Obstacles exist server-side too**: projectiles die on obstacles, players/enemies slide around them via `resolveCircleVsAABB`.

## Deployment

See [DEPLOY.md](./DEPLOY.md) for full production deployment instructions.

**Quick reference:**
- Client: `https://shoot.compilechicken.com` (auto-detects backend URL from `window.location.origin`)
- Nakama: Docker on `127.0.0.1:7350` (Caddy proxies `/v2/*`), console on `127.0.0.1:7351` (internal)
- Static client: Node.js on `127.0.0.1:8787` (Caddy proxies the rest), serves `web/client` + `/shared/*`
- Deploy: GitHub Actions builds `Dockerfile.nakama` + `Dockerfile.static` and runs `docker compose -f docker-compose.prod.yml up -d --force-recreate`
- Prod env: `POSTGRES_PASSWORD`, `NAKAMA_SERVER_KEY`, `NAKAMA_ENCRYPTION_KEY`, `NAKAMA_HTTP_KEY`, `CONSOLE_USERNAME`, `CONSOLE_PASSWORD`
- Caddy on host (not Docker), imports from `/etc/caddy/sites-enabled/*`
- Nakama WebSocket via TLS: Caddy proxies `shoot.compilechicken.com/v2/*` → `127.0.0.1:7350`
