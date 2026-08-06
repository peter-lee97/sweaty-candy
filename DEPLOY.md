# Deployment — Sweaty Candy

## Architecture

```
┌── VPS (bare metal) ─────────────────────────────────────────────────┐
│                                                                     │
│  Caddy (port 80/443, systemd)                                       │
│    shoot.compilechicken.com                                          │
│      /            → localhost:8787 (backend: client + /shared + API)│
│    game.compilechicken.com                                           │
│      /            → localhost:7777 (game server WebSocket via TLS)  │
│                                                                     │
│  sweaty-candy-backend (Node.js, systemd)                            │
│    port 8787 — serves web/client + shared/, auth, lobbies, registry │
│                                                                     │
│  sweaty-candy-server (Node.js game server, systemd)                 │
│    port 7777 — game server WebSocket (proxied through Caddy)        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

The backend is a single origin that serves the static client (`web/client/`), the shared
module (`shared/game.js`), and the REST/WS API. No separate static file host or build step.

## Prerequisites

- VPS with Debian 12+
- Node.js 22+ (via nvm)
- Domain name (e.g. `shoot.compilechicken.com`)
- DNS A records for `shoot` and `game` pointing to VPS IP

## DNS

| Record | Type | Value |
|--------|------|-------|
| `shoot` | A | VPS IP |
| `game` | A | VPS IP |

## Firewall (Hetzner Cloud Console)

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (Let's Encrypt cert challenge) |
| 443 | TCP | HTTPS (game client, backend API, game server WebSocket via Caddy) |
| 7777 | TCP | Optional — game server WebSocket (direct, for testing without Caddy proxy) |

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
    reverse_proxy localhost:8787
}

game.compilechicken.com {
    reverse_proxy localhost:7777
}
```

`shoot.compilechicken.com` proxies the whole backend, which serves the client, the shared
module, and the `/v1/*` API on one origin. `game.compilechicken.com` provides TLS-terminated
WebSocket access to the Node.js game server. Caddy auto-provisions Let's Encrypt certs and
transparently upgrades/proxies WebSocket connections.

### Media converter site config (`/etc/caddy/sites-enabled/mc.caddy`)

```
mc.compilechicken.com, www.mc.compilechicken.com {
    handle /pricing/webhook* {
        reverse_proxy localhost:8000
    }
    handle {
        reverse_proxy localhost:3000
    }
}
```

## Node.js

### Install via nvm

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 22
```

### App files

Place the repo at `/opt/sweaty-candy/` and install dependencies:

```bash
cd /opt/sweaty-candy/backend
npm install
cd /opt/sweaty-candy/gameserver
npm install
```

The backend serves `web/client/` and `shared/` relative to its own module path, so the repo
layout must be preserved (do not copy only the `backend/` folder).

## Local Development & Testing

### Prerequisites

- Node.js 22+ installed locally
- No build step, no Godot, no Caddy required for local dev

### Start all services locally

```bash
./dev.sh
```

Starts the backend (8787) + game server (7777). Open `http://127.0.0.1:8787`.

### Test multiplayer locally

1. Open `http://127.0.0.1:8787` in one tab and `http://localhost:8787` in another
   (different origins = isolated localStorage identities).
2. Tab 1: Create a lobby → Start Game.
3. Tab 2: Join the lobby → both players should see each other in-game.

### Stop all services

```bash
pkill -f "node src/app.js"
pkill -f "node src/server.js"
```

## Production Deploy

### Prerequisites

- Node.js 22+ installed on the server
- SSH access to production server
- Repo rsync'd to `/opt/sweaty-candy/` (layout preserved)

### Upload client + server

```bash
rsync -avz -e "ssh -i ~/.ssh/id_ed25519" --exclude node_modules --exclude data ./ dev@mc.prod:/opt/sweaty-candy/
```

### Restart game server on production

```bash
ssh -i ~/.ssh/id_ed25519 dev@mc.prod "sudo systemctl restart sweaty-candy-server"
```

### Verify production

```bash
ssh -i ~/.ssh/id_ed25519 dev@mc.prod "curl -s http://localhost:8787/health && curl -s http://localhost:8787/v1/servers | head -1"
nc -z -w 3 <VPS_IP> 7777 && echo "Game server: OPEN" || echo "Game server: CLOSED"
curl -s https://shoot.compilechicken.com/ | head -1
```

## Systemd Units

### Backend (`/etc/systemd/system/sweaty-candy-backend.service`)

```ini
[Unit]
Description=Sweaty Candy Backend
After=network.target

[Service]
Type=simple
User=dev
WorkingDirectory=/opt/sweaty-candy/backend
Environment=PORT=8787
Environment=HOST=127.0.0.1
Environment=GUEST_SESSION_DURATION_MS=7200000
Environment=HOME=/home/dev
ExecStart=/home/dev/.nvm/versions/node/v22.23.0/bin/node src/app.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Game Server (`/etc/systemd/system/sweaty-candy-server.service`)

```ini
[Unit]
Description=Sweaty Candy Game Server
After=network.target sweaty-candy-backend.service

[Service]
Type=simple
User=dev
WorkingDirectory=/opt/sweaty-candy/gameserver
Environment=BACKEND_BASE_URL=http://localhost:8787
Environment=ADVERTISED_HOST=game.compilechicken.com
Environment=ADVERTISED_PORT=443
Environment=LISTEN_PORT=7777
Environment=MAX_PLAYERS=4
Environment=HOME=/home/dev
ExecStart=/home/dev/.nvm/versions/node/v22.23.0/bin/node src/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Enable services

```bash
sudo systemctl daemon-reload
sudo systemctl enable sweaty-candy-backend sweaty-candy-server --now
```

## Game Server Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_BASE_URL` | `http://127.0.0.1:8787` | Backend API URL for registration |
| `ADVERTISED_HOST` | `127.0.0.1` | Host sent to backend for clients to connect to (use `game.compilechicken.com` for production) |
| `ADVERTISED_PORT` | `LISTEN_PORT` | Port sent to backend (use `443` for Caddy proxy with TLS) |
| `LISTEN_PORT` | `7777` | WebSocket server listen port (local, behind Caddy proxy) |
| `LISTEN_HOST` | `0.0.0.0` | WebSocket bind host |
| `MAX_PLAYERS` | `4` | Max connected players |

## Client URL Detection

When running in a browser, the client uses `window.location.origin` for the backend API and
lobby events WS. The game server WebSocket URL comes from the lobby's assigned server
(`serverHost`/`serverPort`) and uses `wss://` when the port is 443, otherwise `ws://`.

## Verification Checklist

- [ ] DNS A records for `shoot` and `game` point to VPS IP
- [ ] Ports 80, 443 open in firewall (port 7777 optional)
- [ ] Caddy running: `systemctl status caddy`
- [ ] Backend healthy: `curl http://localhost:8787/health`
- [ ] Game server registered: `curl http://localhost:8787/v1/servers` shows host `game.compilechicken.com` and port `443`
- [ ] Client served: `curl -I https://shoot.compilechicken.com` returns HTML and `curl -I https://shoot.compilechicken.com/shared/game.js` returns JS
- [ ] Game WebSocket via TLS: WebSocket handshake to `wss://game.compilechicken.com` returns `101 Switching Protocols`
- [ ] Multiplayer test: two browser tabs at `https://shoot.compilechicken.com` can see each other in-game

## Known Issues

- **Caddy Debian package**: The Debian-packaged Caddy `2.6.2-5` silently ignores `reverse_proxy` subdirectives like `flush_interval` and `max_fails`. If these are needed, install from the official Caddy repo (instructions above).
