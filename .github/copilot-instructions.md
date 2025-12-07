# AI Agent Instructions for nginx-proxy

## Project Overview
NGINX reverse proxy in **host mode** with Podman-managed containers (`docker-gen` + `acme-companion`) for automatic config generation and SSL certificate management. Inspired by nginx-proxy/nginx-proxy but optimized for rootless Podman with NGINX running directly on the host.

## Big Picture Architecture
**Key Design Decision**: NGINX runs on the host (not containerized) to:
- Bind directly to ports 80/443 without privilege escalation
- Get real client IPs without proxy header spoofing
- Work with Podman's `pasta` network mode limitations (Podman 5.4+)

**Component Interaction Flow**:
1. **Backend containers** expose services with labels (`VIRTUAL_HOST`, `VIRTUAL_PORT`, etc.)
2. **nginx-proxy-gen** (docker-gen) watches Podman socket → generates `conf.d/default.conf` from `nginx-config/tmpl/nginx.tmpl`
3. **notify_nginx_on_host.sh** writes `.signal` file → **nginx-reload-watcher.service** (systemd) reloads host NGINX
4. **nginx-proxy-acme** (acme-companion) issues/renews Let's Encrypt certs → triggers reload via same signal mechanism
5. **Host NGINX** reads config from `/app/proxy/nginx-config/` (symlinked to `/etc/nginx/`)

**Directory Structure**:
- `nginx-config/`: All NGINX files (conf, certs, vhosts) - **symlinked to /etc/nginx/**
  - `tmpl/nginx.tmpl`: Go template for dynamic config generation
  - `conf.d/00-request-logging.conf`: Suspicious request detection for fail2ban
  - `scripts/`: reload watcher and notification scripts
- `podman-quadlet/`: Container definitions (.container, .pod, .network, .env files)
- `fail2ban/`: jail/filter configs for blocking scanners
- `docs/HOWTO.md`: Complete setup guide with symlink instructions

## Critical Workflows

### Setup (see docs/HOWTO.md for full guide)
```sh
# 1. Symlink nginx-config/ to /etc/nginx/
sudo ln -sf /app/proxy/nginx-config/nginx.conf /etc/nginx/nginx.conf
sudo ln -sf /app/proxy/nginx-config/conf.d /etc/nginx/conf.d
# ... (repeat for certs/, vhost.d/, htpasswd/, etc.)

# 2. Install reload watcher as systemd service
sudo ln -sf /app/proxy/nginx-config/scripts/nginx-reload-watcher.service /etc/systemd/system/
sudo systemctl enable --now nginx-reload-watcher.service

# 3. Setup fail2ban
sudo ln -sf /app/proxy/fail2ban/jail.d/nginx-suspicious.local /etc/fail2ban/jail.d/
sudo systemctl restart fail2ban

# 4. Start Podman pod (rootless)
podman quadlet generate /app/proxy/podman-quadlet/nginx-proxy.pod
systemctl --user start nginx-proxy.pod
```

### Config Changes
- Edit `nginx-config/tmpl/nginx.tmpl` or `.env` files in `podman-quadlet/`
- docker-gen auto-regenerates config → triggers reload (no manual intervention)
- For static overrides: edit `nginx-config/conf.d/00-request-logging.conf` directly

### Testing Backend Containers
```sh
# Create standalone network for backend
podman network create test-web-network

# Run test container with proxy labels (connects to systemd-nginx-proxy network)
podman run -d --replace --name test-web \
  -e VIRTUAL_HOST=test.example.com \
  -e VIRTUAL_PORT=80 \
  -e LETSENCRYPT_HOST=test.example.com \
  -e LETSENCRYPT_EMAIL=admin@example.com \
  -p 80 \
  --network systemd-nginx-proxy \
  --network test-web-network \
  docker.io/library/nginx:latest
```

### Debugging
```sh
# Check generated config
cat /app/proxy/nginx-config/conf.d/default.conf

# Watch reload signals
journalctl -u nginx-reload-watcher.service -f

# Verify containers
podman pod ps
podman logs nginx-proxy-gen
podman logs nginx-proxy-acme
```

## Project-Specific Conventions

### Environment Variables (podman-quadlet/*.env)
- `NGINX_ON_HOST=true`: Critical - tells docker-gen to use `127.0.0.1:hostPort` instead of container IPs
- `TRUST_DOWNSTREAM_PROXY=false`: Reject spoofed X-Forwarded-* headers (host mode gets real IPs)
- See `nginx-config/tmpl/nginx.tmpl` for full variable reference (lines 17-40)

### Backend Container Labels
Set on containers to auto-generate proxy config (see docs/HOWTO.md for full example):
```sh
VIRTUAL_HOST=example.com        # required: domain name
VIRTUAL_PORT=8080               # defaults to exposed port or 80
VIRTUAL_PATH=/api               # optional: path-based routing
NETWORK_ACCESS=internal         # restrict to internal IPs (network_internal.conf)
LETSENCRYPT_HOST=example.com    # enable SSL cert for this domain
LETSENCRYPT_EMAIL=admin@...     # contact email for Let's Encrypt
```
Backend containers must connect to `systemd-nginx-proxy` network (generated from nginx-proxy.pod)

### Per-Vhost Customization
- `nginx-config/vhost.d/<hostname>`: Custom location blocks (included before default locations)
- `nginx-config/htpasswd/<hostname>`: Basic auth for specific vhost
- Never edit `conf.d/default.conf` - regenerated on every container change

### Fail2ban Integration
- Suspicious requests: 4xx/5xx on malicious URIs OR scanner user-agents (even on 200)
- Filter regex in `fail2ban/filter.d/nginx-suspicious.conf` matches log format from `00-request-logging.conf`
- Threshold: 4 requests/120s → 24h ban (recidive: 4 weeks)

## Key Files Reference
- `podman-quadlet/nginx-proxy-proxy-gen.container`: docker-gen container def (note `EnvironmentFile` path)
- `podman-quadlet/nginx-proxy-proxy-acme.container`: acme-companion with `ACME_POST_HOOK` for reloads
- `nginx-config/network_internal.conf`: IP whitelist for `NETWORK_ACCESS=internal` services
- `nginx-config/scripts/notify_nginx_on_host.sh`: Signal writer (called by docker-gen & acme-companion)
- `docs/HOWTO.md`: Authoritative setup guide with rationale for host-mode decision