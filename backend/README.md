# Sweaty Candy Backend (Phase 4 scaffold)

Standalone HTTP backend for:
- auth/session
- lobby/matchmaking orchestration
- game server registration/heartbeat
- SQLite-backed persistent storage

## Run

```bash
cd backend
npm start
```

Default address: `http://0.0.0.0:8787`

Data persistence is stored in `backend/data/store.db` (SQLite), so users/lobbies/servers survive backend restarts.

## Implemented APIs

- `GET /health`
- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `GET /v1/auth/me`
- `POST /v1/servers/register`
- `POST /v1/servers/:id/heartbeat`
- `GET /v1/servers`
- `GET /v1/lobbies`
- `POST /v1/lobbies`
- `POST /v1/lobbies/:id/join`
- `POST /v1/lobbies/:id/leave`
- `POST /v1/lobbies/:id/start`

Lobby password rule (when provided): alphanumeric, 4-11 chars.
