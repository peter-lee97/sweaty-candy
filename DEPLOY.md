# Deployment — Sweaty Candy

## Architecture

```
┌── VPS (bare metal) ───────────────────────────────────────────────────┐
│                                                                       │
│  Caddy (port 80/443, systemd)                                         │
│    shoot.compilechicken.com                                            │
│      handle /v2/*  → reverse_proxy 127.0.0.1:7350   (Nakama API+WS)  │
│      handle *      → reverse_proxy 127.0.0.1:8787   (static client)   │
│                                                                       │
│  Docker Compose (systemd / docker compose):                           │
│    postgres  (127.0.0.1, no public port)  — Nakama database           │
│    nakama    (127.0.0.1:7350)             — auth, lobbies, game sim   │
│    static    (127.0.0.1:8787)             — web/client + /shared      │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

Nakama replaces the old Node.js backend and game server. It handles guest auth, rooms
(lobbies), and the authoritative 60Hz game simulation as match handlers. The static
client is served by a tiny Node server (`web/server.js`). `game.compilechicken.com`
is retired - gameplay runs on the same Nakama socket.

## Prerequisites

- VPS with Debian 12+
- Docker + Docker Compose plugin
- Domain name (e.g. `shoot.compilechicken.com`)
- DNS A record for `shoot` pointing to the VPS IP

## DNS

| Record | Type | Value |
|--------|------|-------|
| `shoot` | A | VPS IP |

## Firewall (Hetzner Cloud Console)

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (Let's Encrypt cert challenge) |
| 443 | TCP | HTTPS (client, Nakama API, WebSocket via Caddy) |

Nakama (7350) and the static server (8787) bind to 127.0.0.1 and are never exposed
directly. The Nakama console (7351) is internal only.

## Caddy Setup

### Install

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/deb/debian.dists/bookworm/main/sources.list' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy -y
```

### Main Caddyfile (`/etc/caddy/Caddyfile`)

```
import /etc/caddy/sites-enabled/*
```

### Sweaty Candy site config (`/etc/caddy/sites-enabled/sweaty.caddy`)

```
shoot.compilechicken.com {
    handle /v2/* {
        reverse_proxy 127.0.0.1:7350
    }
    handle {
        reverse_proxy 127.0.0.1:8787
    }
}
```

Nakama serves both its REST API and the realtime WebSocket under `/v2/*` on port 7350.
Caddy terminates TLS and proxies WebSocket upgrades transparently. The static server
(8787) serves the client and `/shared/*`.

## Docker Compose

The production stack lives in `docker-compose.prod.yml` at the repo root. The GitHub
Actions workflow (`.github/workflows/deploy.yml`) builds `Dockerfile.nakama` (Nakama +
bundled runtime) and `Dockerfile.static` (client static server), uploads them, and runs
`docker compose -f docker-compose.prod.yml up -d --force-recreate`.

The Nakama runtime source (`nakama-server/runtime/`) is bundled into the image by
`Dockerfile.nakama` with esbuild. The dev compose file (`nakama-server/docker-compose-postgres.yml`)
mounts the repo so the bundle is loaded from `nakama-server/modules/build/`.

## Environment Variables (docker-compose.prod.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_PASSWORD` | `localdb` | Postgres password (set a strong one in prod) |
| `NAKAMA_SERVER_KEY` | `defaultkey` | Nakama socket server key |
| `NAKAMA_ENCRYPTION_KEY` | `defaultencryptionkey` | Nakama session encryption key |
| `NAKAMA_HTTP_KEY` | `defaulthttpkey` | Nakama runtime HTTP key |
| `CONSOLE_USERNAME` / `CONSOLE_PASSWORD` | `admin` / `password` | Nakama console credentials |

Session lifetime is `--session.token_expiry_sec 7200` (2h, matches the old guest
session) with `--session.refresh_token_expiry_sec 604800` (7d refresh).

## Client URL Detection

The client (`web/client/js/nakama.js`) computes the Nakama base URL at runtime:

- Dev (`http://127.0.0.1:8787` or `localhost:8787`): uses `http://<hostname>:7350`.
- Prod (`https://shoot.compilechicken.com`): uses `window.location.origin` (Caddy
  proxies `/v2/*` to Nakama).

## Local Development

```bash
./dev.sh
```

`dev.sh` builds the runtime bundle, starts Nakama + Postgres via docker compose,
waits for Nakama to be healthy, and starts the static server on 8787. Open
`http://127.0.0.1:8787`. Nakama console: `http://127.0.0.1:7351` (`admin`/`password`).

For local multiplayer testing use two different origins so localStorage identities
stay isolated, e.g. one tab at `http://127.0.0.1:8787` and one at
`http://localhost:8787`.

Stop with Ctrl+C (leaves Nakama containers running; `docker compose -f
nakama-server/docker-compose-postgres.yml down` stops them).

## Production Deploy (manual)

```bash
# Build + upload + deploy via the CI workflow (master push)
git push origin master

# Or manually on the server:
cd /home/dev/sweaty-candy
docker compose -f docker-compose.prod.yml up -d --force-recreate
```

## Verification Checklist

- [ ] DNS A record for `shoot` points to VPS IP
- [ ] Ports 80, 443 open in firewall
- [ ] Caddy running: `systemctl status caddy`
- [ ] Nakama healthy: `docker compose -f /home/dev/sweaty-candy/docker-compose.prod.yml ps` shows all `Up (healthy)`
- [ ] Static served: `curl -I https://shoot.compilechicken.com` returns HTML
- [ ] Nakama API proxied: `curl -s -o /dev/null -w "%{http_code}" https://shoot.compilechicken.com/v2/health` (expect a 4xx/JSON from Nakama, not a Caddy 502)
- [ ] Client served: `curl -I https://shoot.compilechicken.com/shared/game.js` returns JS
- [ ] Multiplayer test: two browser tabs at `https://shoot.compilechicken.com` can create/join a room and play together

## Known Issues

- **Caddy Debian package**: The Debian-packaged Caddy `2.6.2-5` silently ignores
  `reverse_proxy` subdirectives like `flush_interval` and `max_fails`. If these are
  needed, install from the official Caddy repo (instructions above).
