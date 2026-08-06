# AGENTS.md — Sweaty Candy

Boxhead-inspired isometric multiplayer horde shooter, rewritten as a web app (HTML/JS + Phaser 4.2.1, no Godot).
Authoritative game server in Node.js.
Game logic is 2D top-down; only rendering is isometric (2:1 diamond projection).
Shapes and colors identify entities instead of sprites.
Desktop uses mouse + keyboard; mobile web uses virtual twin-sticks.

## Architecture

Four components:

- **`web/client/`** — Browser client. Vanilla JS ES modules + Phaser 4.2.1 (WebGL), no build step.
- **`gameserver/`** — Node.js authoritative game server (`ws`). Replaces the old Godot headless server.
- **`backend/`** — Node.js auth, lobby, and server registry (reused from the Godot era). Serves the client statically.
- **`shared/game.js`** — Single source of truth for gameplay constants, map, obstacles, and pure helpers. Imported by both the browser client (`/shared/game.js`) and the game server (`../../shared/game.js`).

Key rule: **clients are never authoritative**. Input → intent → server validates → state change.
Input never directly mutates position/health on the network path.

## Authentication

Credential-less guest-first auth. Users land on main menu and can play immediately.

- No passwords. Optional display name (3-20 chars: letters, numbers, space, underscore); auto-generated `fruit+color+number` if skipped.
- Guest session: 2-hour configurable lifetime (`GUEST_SESSION_DURATION_MS` env var, default 7200000ms). Stored in `localStorage` under key `sweaty.auth.v1` (`{ userId, username, token }`).
- Username collision check against both `store.users` and active `guestSessions`.
- The menu pre-fills the current identity. The name field only applies when no valid token exists (re-validate via `GET /v1/auth/me` first).
- Guest sessions can be refreshed via `POST /v1/auth/refresh` (client does not currently auto-refresh).
- Logout: not yet implemented in the UI. Clearing `sweaty.auth.v1` from localStorage logs out.

### Auth Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/v1/auth/register` | No | Create account with custom username + password (min 6 chars) |
| POST | `/v1/auth/login` | No | Login with username + password |
| POST | `/v1/auth/guest` | No | Create guest session; optional `username` field (credential-less) |
| POST | `/v1/auth/refresh` | Yes | Extend guest session (only for guests) |
| GET | `/v1/auth/me` | Yes | Get current user info |

### Auth Store Structure

```js
{
  users: [{ id, username, passwordHash?, createdAt }],
  tokens: { [token]: userId },
  guestSessions: { [guestId]: { createdAt, expiresAt, username } },
  lobbies: [...],
  servers: [...]
}
```

Backend persists state in SQLite at `backend/data/store.db` (see `backend/src/store.js`).

## Project Layout

```
shared/
  game.js                # CONFIG, ENEMY_TYPES, MAP, wave/difficulty formulas, collision helpers

web/client/
  index.html             # Single page: screens + canvas + HUD + touch sticks
  css/style.css
  js/
    main.js              # Boot, auth state, screen routing, lobby WS wiring
    auth.js              # localStorage token helpers
    api.js               # REST + lobby events WebSocket client
    screens/
      manager.js         # setScreen(app, name) toggles menu/lobby/waiting + tracks app.screen
      menu.js, lobby.js, waiting.js
    game/
      GameScene.js         # Phaser scene orchestration: game loop, prediction, interpolation, FX
      net.js               # Game WS: intents out, snapshots in, prediction history, RTT
      InputManager.js      # WASD/mouse + touch twin-sticks
      IsometricRenderer.js # Phaser-based isometric renderer (2:1 diamond projection)
      EntityManager.js     # Entity state management (players, enemies, projectiles, pickups)
      ParticleManager.js   # Visual effects (hit flash, death particles, FX)
      hud.js               # Health bar, banner, ping, player list, game-over overlay

gameserver/
  package.json
  src/
    server.js            # ws endpoint, backend registration + heartbeat, lobby validation
    sim.js               # 60Hz simulation + snapshot building (full/delta)

backend/
  src/
    app.js               # HTTP server: API + static file serving (web/client + shared/)
    auth.js              # Password hashing, token generation, guest ID/username generation
    store.js             # SQLite-backed key-value store
  package.json

client/  server/          # Legacy Godot projects, kept for reference only (no longer run)
tools/Caddyfile.local     # Optional local HTTPS/proxy config
dev.sh                    # Starts backend + game server
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
- Main Lobby: live room table via WS events, Create Room modal (name, optional password, max players), Refresh, Back.
- Waiting Room: player list with owner tag, Start (owner only), Leave. Live-updates via WS; auto-starts the game when the lobby flips to Started.
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

### Lobby Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/v1/lobbies` | No | List all lobbies |
| POST | `/v1/lobbies` | Yes | Create lobby (auto-joins as owner) |
| POST | `/v1/lobbies/:id/join` | Yes | Join lobby (password required for private) |
| POST | `/v1/lobbies/:id/leave` | Yes | Leave lobby (auto-deletes if empty, reassigns owner) |
| POST | `/v1/lobbies/:id/start` | Yes | Start lobby (owner only, assigns game server) |
| WS | `/v1/lobbies/events?token=...` | Yes | Real-time lobby updates |

Lobby payloads include `players: [{ id, username }]` (used by the waiting room).

### Server Registration

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/v1/servers/register` | No | Register game server |
| POST | `/v1/servers/:id/heartbeat` | No | Server heartbeat (10s interval, 60s TTL) |
| GET | `/v1/servers` | No | List active servers |

### Game Server (`gameserver/`)

- Authoritative simulation on a fixed 60Hz timestep (`setInterval`, one `sim.step(1/60)` per tick).
- One game per server instance: first connecting lobby claims the server; other lobbies are rejected with a kick.
- Per-player intent queue (cap 16, drops oldest); hold-last idle policy; 120 intents/s rate limit.
- Clients validated via backend `GET /v1/auth/me` + lobby must be `Started` and assigned to this server id.
- Snapshots: 30Hz default, adaptive 20/15Hz for RTT > 100/200ms. Full sync every 1s; otherwise delta sync (changed entities + removed lists).
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
./dev.sh                          # Start backend (8787) + game server (7777); open http://127.0.0.1:8787
cd backend && npm start           # Backend only
cd gameserver && npm start        # Game server only
GUEST_SESSION_DURATION_MS=3600000 npm start  # Backend with 1h guest sessions
```

For local multiplayer testing use two different origins so localStorage identities stay isolated,
e.g. one tab at `http://127.0.0.1:8787` and one at `http://localhost:8787`.

## JS Conventions

- ES modules everywhere; browser client imports absolute `/shared/game.js`, game server imports `../../shared/game.js`.
- Phaser 4.2.1 framework (loaded via CDN), no build step, no bundler.
- Static typing not available; name variables/params clearly.
- No comments in code unless explicitly requested.
- Pure data/helpers live in `shared/game.js`; no DOM or Node imports there.
- DOM element access via `document.getElementById` with ids defined once in `index.html`.
- `app` object in `main.js` holds cross-screen state (auth, currentLobby, lobbyWs, game) and is exposed as `window.__app` for debugging.

## Common Pitfalls

- **Same-origin localStorage**: two browser tabs on the same origin share the same identity. Use different origins (127.0.0.1 vs localhost) for multi-client local tests.
- **`app.screen` must be set via `setScreen(app, name)`** in `screens/manager.js`; the waiting room live-update and auto-start logic branches on it.
- **Lobby WS lifecycle**: connect once when entering the Main Lobby (`showLobbyScreen`). Keep it open through the waiting room; it drives both the room list and the auto-start.
- **Name field only applies to new sessions**: the menu re-validates an existing stored token and keeps it; clearing `sweaty.auth.v1` + reload is how to switch identity.
- **Never send `shoot` when dead**: the client gates firing on `myAlive`; the server ignores intent movement for dead players.
- **Snapshot `type` field is required**: `buildSnapshot`/`deltaFrom` must set `type: "snapshot"` or the client ignores the message.
- **One game per server**: a game server rejects clients whose lobby differs from the active one. Backend `pickServer` spreads load but each server instance is single-game.
- **Server and client must share the same `shared/game.js`**: prediction assumes identical constants/map; drift causes visible snapping.
- **Solo death = game over**: the sim freezes when every player is dead (`gameOver`), so respawn only matters with ≥ 2 players.
- **Obstacles exist server-side too** (unlike the old Godot server): projectiles die on obstacles, players/enemies slide around them via `resolveCircleVsAABB`.

## Deployment

See [DEPLOY.md](./DEPLOY.md) for full production deployment instructions.

**Quick reference:**
- Client: `https://shoot.compilechicken.com` (auto-detects backend URL from `window.location.origin`)
- Backend: Node.js on `localhost:8787` (systemd `sweaty-candy-backend`), serves the client + `/shared/*`
- Game server: Node.js on port 7777, proxied through Caddy at `wss://game.compilechicken.com` (systemd `sweaty-candy-server`)
- Game server env: `BACKEND_BASE_URL`, `ADVERTISED_HOST`, `ADVERTISED_PORT`, `LISTEN_PORT`, `MAX_PLAYERS`
- Caddy on host (not Docker), imports from `/etc/caddy/sites-enabled/*`
- Game WebSocket via TLS: Caddy proxies `game.compilechicken.com:443` → `localhost:7777`
