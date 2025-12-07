# Howto

## Decision log

### NGINX in host mode

- For better performance and direct access to host network interfaces, NGINX is configured to run in host mode. This allows it to handle incoming requests without the overhead of network translation.
- `nginx` proxy must bind to ports `80` and `443` on the **VPS host**, which requires elevated privileges, eg: `sysctl -w net.ipv4.ip_unprivileged_port_start=80`. Running in host mode simplifies this requirement, and still able to use `Podman` in rootless mode for other containers.
- With standard security management, the upstream services should be deployed in an isolate network, that distinguishes:
  - from the host network, only exposing necessary ports for nginx proxy to access them to route the traffic and serve the user requests.
  - from other upstream service networks, unless explicitly allowed such as for internal services communication, such as database servers, cache servers, etc.

  Since Podman 5.4, `pasta` is a default network mode for rootless containers, which directly maps network traffic between the host and container using a more native approach, leveraging Linux's `unshare` and `nsenter` capabilities. That makes difficult to achieve the requirement of isolating networks above, then using `nginx in host mode` is a more straightforward solution.

- Getting real client IPs and protecting against IP spoofing:
  - Since NGINX is running in host mode, it can directly read the real client IP addresses from incoming requests without needing to rely on proxy headers.
  - To protect against IP spoofing, ensure that any upstream services are configured to only accept traffic from the NGINX proxy server's IP address. This can be enforced using firewall rules or network policies.
  - Additionally, implement logging and monitoring to detect any unusual patterns that may indicate spoofing attempts.

## Step to step guide

### Pre-requisites

- A Linux server (VPS) with Podman installed and configured for rootless containers.
- Basic knowledge of NGINX, Podman, and containerization concepts.
- Ensure that ports `80` and `443` are open and not blocked by any firewalls

### Setting up the NGINX Proxy

- Install `podman`, `nginx`, and `fail2ban` on the host machine.
- Setup podman rootless environment
  ```sh
  sudo dnf install -y podman
  export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
  loginctl enable-linger $USER
  systemctl --user start podman.socket
  ```
- Create `/app/proxy` on the host and clone this repository into it.
- Symlink these files/folders under `nginx-config` with nginx config path on the host:
    - `/etc/nginx/certs` -> `/app/proxy/nginx-config/certs`
    - `/etc/nginx/conf.d` -> `/app/proxy/nginx-config/conf.d`
    - `/etc/nginx/default.d` -> `/app/proxy/nginx-config/default.d`
    - `/etc/nginx/htpasswd` -> `/app/proxy/nginx-config/htpasswd`
    - `/etc/nginx/network_internal.conf` -> `/app/proxy/nginx-config/network_internal.conf`
    - `/etc/nginx/nginx.conf` -> `/app/proxy/nginx-config/nginx.conf`
    - `/etc/nginx/vhost.d` -> `/app/proxy/nginx-config/vhost.d`
    - `/usr/share/nginx/html` -> `/app/proxy/nginx-config/html`
- Create system service file `nginx-reload-watcher` to reload `nginx` service automatically when config or cert changes:
    ```sh
    sudo ln -sf /app/proxy/nginx-config/scripts/nginx-reload-watcher.service /etc/systemd/system/nginx-reload-watcher.service
    sudo systemctl daemon-reload
    sudo systemctl start nginx-reload-watcher.service
    ```
- Setup `fail2ban` to monitor suspicious requests:
    ```sh
    sudo ln -sf /app/proxy/fail2ban/jail.d/nginx-suspicious.local /etc/fail2ban/jail.d/nginx-suspicious.local
    sudo ln -sf /app/proxy/fail2ban/filter.d/nginx-suspicious.conf /etc/fail2ban/filter.d/nginx-suspicious.conf
    sudo systemctl restart fail2ban
    ```
- Generate and start the Podman Quadlet for `nginx-proxy`:
    ```sh
    podman --user quadlet generate /app/proxy/podman-quadlet/nginx-proxy.pod
    systemctl --user start nginx-proxy.pod
    ```
- Verify that the `nginx-proxy` pod is running:
    ```sh
    podman pod ps
    ```

- Run a test backend container with appropriate labels and environment, following [original nginx-proxy doc](https://github.com/nginx-proxy/nginx-proxy/blob/main/docs/README.md#proxyied-container), for example:
    ```sh
    # standalone network for backend container
    podman network create test-web-network

    # run with specific exposed container port but random host port
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