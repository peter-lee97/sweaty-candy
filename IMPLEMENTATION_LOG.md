# Sweaty Candy Implementation Log

## 1. Performance and Rendering Optimizations (Client)

- Added render warm-up flow to reduce first-use hitches in Compatibility renderer.
- Extended warm-up to include:
  - player, weapon, enemy, pickup scenes
  - weapon projectile scenes
  - initial hit-flash trigger pass
- Optimized runtime components:
  - `HitboxComponent` only processes while cooldowns are active.
  - `HitFlashComponent` only processes during active flash windows.
  - Shared material caching for hit flash.
- Reworked death particles:
  - switched to `MultiMeshInstance3D` path
  - shared mesh/material caching to reduce allocations and draw overhead.

## 2. Loading Flow

- Added loading scene and script:
  - `client/scenes/ui/loading_screen.tscn`
  - `client/scripts/ui/loading_screen.gd`
- Main menu Start now routes through loading scene before entering game.
- Loading screen performs threaded load of game scene and displays progress percentage + bar.

## 3. Phase 3 Multiplayer Scaffold

### Server (Headless Godot)

- Added new `server/` project:
  - `server/project.godot`
  - `server/scenes/server_main.tscn`
  - `server/scripts/server_main.gd`
- Implemented WebSocket-based authoritative server scaffold:
  - peer connect/disconnect handling
  - intent RPC intake (`submit_player_intent`)
  - basic authoritative player simulation
  - periodic snapshot broadcast
  - lobby state broadcast

### Client Networking Bridge

- Added client autoload:
  - `client/scripts/autoload/network_client.gd`
- Registered in `client/project.godot`.
- Added helpers/signals for:
  - connect/disconnect
  - send intent
  - receive lobby/snapshot updates.

### In-Game Multi-Client Movement Test Path

- Updated `game_manager.gd` and `player.gd` for network test mode:
  - client sends intents each physics frame
  - spawns per-peer player nodes from server snapshots
  - camera follows local peer
  - snapshot smoothing support
  - fallback to single-player if backend/server connect fails.

## 4. Lobby UI and Room Lifecycle (Client)

- Main menu updated with Multiplayer Lobby entry.
- Added new lobby scene + script:
  - `client/scenes/ui/lobby.tscn`
  - `client/scripts/ui/lobby.gd`
- Table-form lobby list includes columns:
  - Room ID
  - Room Name
  - Current/Max players
  - Lock icon
  - State (Waiting/Started)
- Room creation supports optional room name + optional password.
- Password policy implemented client-side:
  - optional
  - alphanumeric only
  - min 4, max 11 chars.

## 5. Phase 4 Backend Scaffold

- Added standalone Node backend:
  - `backend/package.json`
  - `backend/src/app.js`
  - `backend/src/auth.js`
  - `backend/src/store.js`
  - `backend/README.md`
  - `backend/.gitignore`
  - `backend/data/.gitkeep`
- Implemented APIs:
  - health
  - auth register/login/me
  - server register/heartbeat/list
  - lobby list/create/join/leave/start
- Added server-assignment selection on lobby start based on active server load.
- Added password rule validation in backend for lobby creation:
  - alphanumeric, 4–11 characters.

## 6. Backend Persistence Upgrade (SQLite)

- Migrated backend persistence from JSON file to SQLite-backed storage.
- DB file path:
  - `backend/data/store.db`
- Added WAL-enabled SQLite key-value app-state storage.
- Included compatibility migration path from legacy `store.json` seed data.

## 7. Backend Endpoint Tests (`npm test`)

- Added test command in backend package scripts:
  - `npm test` → `node --test`
- Refactored backend startup for test lifecycle control:
  - `startBackendServer(...)`
  - `stopBackendServer()`
- Added endpoint scenario suite:
  - `backend/test/endpoints.test.js`
- Test scenarios cover:
  - health
  - auth register/login/me
  - lobby password validation behavior
  - join/start flows
  - server assignment behavior.

## 8. Client-Backend Lobby Integration

- Added client backend API autoload:
  - `client/scripts/autoload/backend_api.gd`
- Registered in `client/project.godot`.
- Lobby now uses backend APIs directly for:
  - register/login
  - list lobbies
  - create/join/start lobby
- Added lobby auth/connect controls:
  - backend URL input
  - username/password
  - register/login buttons.

## 9. Notes

- Existing docs (`AGENTS.md`) were updated to reflect new phase scaffolds and run commands.
- Validation steps run during implementation included:
  - Godot headless startup checks
  - backend endpoint smoke checks
  - backend automated tests via `npm test`.
