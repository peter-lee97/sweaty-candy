# Deployment — Sweaty Candy

## Architecture

```
┌── VPS (bare metal) ─────────────────────────────────────────────┐
│                                                                  │
│  Caddy (port 80/443, systemd)                                    │
│    shoot.compilechicken.com                                      │
│      /            → /opt/sweaty-candy/client-export (static)    │
│      /v1/*        → localhost:8787 (backend API + WS)           │
│                                                                  │
│  sweaty-candy-backend (Node.js, systemd)                         │
│    port 8787 — auth, lobbies, server registry                   │
│                                                                  │
│  sweaty-candy-server (Godot headless, systemd)                   │
│    port 7777 — game server WebSocket (direct, no Caddy proxy)   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- VPS with Debian 12+
- Domain name (e.g. `shoot.compilechicken.com`)
- DNS A record for `shoot` pointing to VPS IP

## Firewall (Hetzner Cloud Console)

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (Let's Encrypt cert challenge) |
| 443 | TCP | HTTPS (game client + backend API) |
| 7777 | TCP | Game server WebSocket (direct) |

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
```

> **Note on game server WebSocket**: Caddy's `reverse_proxy` cannot proxy WebSocket connections to Godot's `WebSocketMultiplayerPeer` server (returns 503). The game server is exposed directly on port 7777.

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

## Godot Builds

### Prerequisites

- Godot 4.6.3+ installed locally
- Export templates for Web and Linux installed

### Export client (HTML5/WebAssembly)

```bash
mkdir -p /tmp/sweaty-client-export
godot --headless --path client/ --export-release "Web" /tmp/sweaty-client-export/index.html
rsync -avz -e "ssh -i ~/.ssh/vm_access_key" /tmp/sweaty-client-export/ dev@mc.prod:/opt/sweaty-candy/client-export/
```

### Export server (Linux x86_64 headless)

```bash
mkdir -p /tmp/sweaty-server-build
godot --headless --path server/ --export-release "Linux" /tmp/sweaty-server-build/sweaty-server
rsync -avz -e "ssh -i ~/.ssh/vm_access_key" /tmp/sweaty-server-build/sweaty-server dev@mc.prod:/opt/sweaty-candy/server/
rsync -avz -e "ssh -i ~/.ssh/vm_access_key" /tmp/sweaty-server-build/sweaty-server.pck dev@mc.prod:/opt/sweaty-candy/server/
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
ExecStart=/opt/sweaty-candy/server/sweaty-server --headless -- --backend-base-url http://localhost:8787 --advertised-host <VPS_IP> --advertised-port 7777 --listen-port 7777
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Replace `<VPS_IP>` with the public IP of your server.

### Enable services

```bash
sudo systemctl daemon-reload
sudo systemctl enable sweaty-candy-backend sweaty-candy-server --now
```

## Server CLI Arguments

The game server supports these CLI arguments (passed after `--` separator):

| Argument | Default | Description |
|----------|---------|-------------|
| `--listen-port` | `7777` | WebSocket server listen port |
| `--advertised-host` | `127.0.0.1` | Host sent to backend for clients to connect to |
| `--advertised-port` | `0` (uses listen_port) | Port sent to backend (use 443 for Caddy proxy) |
| `--backend-base-url` | `http://127.0.0.1:8787` | Backend API URL for registration |
| `--max-players` | `4` | Max connected players |

> Godot requires the `--` separator to distinguish engine args from user args.

## Client URL Detection

When running in a browser, the client auto-detects the backend URL from `window.location.origin`. In the Godot editor, it falls back to `http://127.0.0.1:8787`.

The game server WebSocket URL uses `wss://` when the port is 443, otherwise `ws://`.

## Verification Checklist

- [ ] DNS A record for `shoot` points to VPS IP
- [ ] Ports 80, 443, 7777 open in firewall
- [ ] Caddy running: `systemctl status caddy`
- [ ] Backend healthy: `curl http://localhost:8787/health`
- [ ] Game server registered: `curl http://localhost:8787/v1/servers`
- [ ] Game site accessible: `curl -I https://shoot.compilechicken.com`
- [ ] Game server reachable: `echo -e "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n" | nc -w 3 <VPS_IP> 7777 | head -1` should return `HTTP/1.1 101 Switching Protocols`

## Known Issues

- **Godot WebSocket through Caddy**: Caddy's `reverse_proxy` cannot proxy WebSocket connections to Godot's `WebSocketMultiplayerPeer`. The game server is exposed directly on port 7777 without TLS. This is acceptable for the current phase since game traffic consists only of position updates and game commands.
- **Caddy Debian package**: The Debian-packaged Caddy `2.6.2-5` silently ignores `reverse_proxy` subdirectives like `flush_interval` and `max_fails`. If these are needed, install from the official Caddy repo (instructions above).
