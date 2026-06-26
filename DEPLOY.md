# Deployment — Sweaty Candy

## Architecture

```
┌── VPS (bare metal) ─────────────────────────────────────────────────┐
│                                                                     │
│  Caddy (port 80/443, systemd)                                       │
│    shoot.compilechicken.com                                         │
│      /            → /opt/sweaty-candy/client-export (static)        │
│      /v1/*        → localhost:8787 (backend API + WS)               │
│    game.compilechicken.com                                          │
│      /            → localhost:7777 (game server WebSocket via TLS)  │
│                                                                     │
│  sweaty-candy-backend (Node.js, systemd)                            │
│    port 8787 — auth, lobbies, server registry                      │
│                                                                     │
│  sweaty-candy-server (Godot headless, systemd)                      │
│    port 7777 — game server WebSocket (proxied through Caddy)        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- VPS with Debian 12+
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
    root * /opt/sweaty-candy/client-export
    file_server

    handle /v1/lobbies/events {
        reverse_proxy localhost:8787
    }
    handle /v1/* {
        reverse_proxy localhost:8787
    }
}

game.compilechicken.com {
    reverse_proxy localhost:7777
}
```

The `game.compilechicken.com` subdomain provides TLS-terminated WebSocket access to the game server. Caddy auto-provisions a Let's Encrypt cert and transparently proxies WebSocket connections to Godot's `WebSocketMultiplayerPeer`.

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

## Node.js (Backend)

### Install via nvm

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 22
```

### Backend files

Place `backend/` at `/opt/sweaty-candy/backend/` and install dependencies:

```bash
cd /opt/sweaty-candy/backend
npm install
```

## Local Development & Testing

### Prerequisites

- Godot 4.6.3+ installed locally
- Node.js installed locally
- Caddy installed locally: `brew install caddy` (macOS) or `sudo apt install caddy` (Linux)

### Start all services locally

```bash
# Terminal 1: Backend
cd backend && node src/app.js

# Terminal 2: Game server
godot --headless --path server/ -- --backend-base-url http://localhost:8787 --advertised-host 127.0.0.1 --advertised-port 7777 --listen-port 7777

# Terminal 3: Caddy proxy (serves client + proxies /v1/* to backend)
caddy run --config tools/Caddyfile.local
```

### Export client (HTML5/WebAssembly)

```bash
godot --headless --path client/ --export-release "Web" --quit
```

Output: `client/index.html`, `client/index.js`, `client/index.wasm`, `client/index.pck`, etc.

### Test multiplayer locally

1. Open `http://localhost:8080` in two browser tabs
2. Tab 1: Create a lobby → Start Game → you're Player 1
3. Tab 2: Join the lobby → Start Game → you should see Player 1 (blue tint)

### Stop all services

```bash
pkill -f "godot.*--path.*server"
pkill -f "node.*app.js"
pkill -f "caddy run"
```

## Production Deploy

### Prerequisites

- Godot 4.6.3+ installed locally
- Export templates for Web and Linux installed
- SSH access to production server

### Export and upload client

```bash
godot --headless --path client/ --export-release "Web" --quit
rsync -avz -e "ssh -i ~/.ssh/id_ed25519" client/index.* dev@mc.prod:/opt/sweaty-candy/client-export/
```

### Export and upload server PCK

```bash
godot --headless --path server/ --export-pack "Linux" server/build/sweaty-server.pck --quit
scp -i ~/.ssh/id_ed25519 server/build/sweaty-server.pck dev@mc.prod:/opt/sweaty-candy/server/sweaty-server.pck
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
WorkingDirectory=/opt/sweaty-candy/server
ExecStart=/opt/sweaty-candy/server/sweaty-server --headless -- --backend-base-url http://localhost:8787 --advertised-host game.compilechicken.com --advertised-port 443 --listen-port 7777
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The `--advertised-host` and `--advertised-port` tell clients to connect via `wss://game.compilechicken.com:443` (TLS-secured WebSocket through Caddy). The `--listen-port` stays on 7777 for local proxy.

### Enable services

```bash
sudo systemctl daemon-reload
sudo systemctl enable sweaty-candy-backend sweaty-candy-server --now
```

## Server CLI Arguments

The game server supports these CLI arguments (passed after `--` separator):

| Argument | Default | Description |
|----------|---------|-------------|
| `--listen-port` | `7777` | WebSocket server listen port (local, behind Caddy proxy) |
| `--advertised-host` | `127.0.0.1` | Host sent to backend for clients to connect to (use `game.compilechicken.com` for production) |
| `--advertised-port` | `0` (uses listen_port) | Port sent to backend (use `443` for Caddy proxy with TLS) |
| `--backend-base-url` | `http://127.0.0.1:8787` | Backend API URL for registration |
| `--max-players` | `4` | Max connected players |

> Godot requires the `--` separator to distinguish engine args from user args.

## Client URL Detection

When running in a browser, the client auto-detects the backend URL from `window.location.origin`. In the Godot editor, it falls back to `http://127.0.0.1:8787`.

The game server WebSocket URL uses `wss://` when the port is 443, otherwise `ws://`.

## Verification Checklist

- [ ] DNS A records for `shoot` and `game` point to VPS IP
- [ ] Ports 80, 443 open in firewall (port 7777 optional)
- [ ] Caddy running: `systemctl status caddy`
- [ ] Backend healthy: `curl http://localhost:8787/health`
- [ ] Game server registered: `curl http://localhost:8787/v1/servers` shows host `game.compilechicken.com` and port `443`
- [ ] Game site accessible: `curl -I https://shoot.compilechicken.com`
- [ ] Game WebSocket via TLS: WebSocket handshake to `wss://game.compilechicken.com` returns `101 Switching Protocols`
- [ ] Multiplayer test: two browser tabs at `https://shoot.compilechicken.com` can see each other in-game

## Known Issues

- **Caddy Debian package**: The Debian-packaged Caddy `2.6.2-5` silently ignores `reverse_proxy` subdirectives like `flush_interval` and `max_fails`. If these are needed, install from the official Caddy repo (instructions above).
