# nginx-proxy

This project provides a containerized NGINX reverse proxy setup, designed for dynamic configuration and automated certificate management.
This repository contains the standard CI/CD pipelines for setting up automated building and deployment on real servers.

## Big Picture Architecture

This project is a combination of a reverse proxy **NGINX in host mode**, and the `Podman-quadlet` container orchestration to manage auto-generate NGINX configs for dynamic containerized backends, also supports TLS certificate management for web servers.

It is inspired by the project [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy), but adjusted for using **nginx in host mode** and leveraging only [docker-gen](https://github.com/nginx-proxy/docker-gen) and [acme-companion](https://github.com/nginx-proxy/acme-companion) containers for automatically issuing and renewing the free certificate, thanks to [acme.sh](https://github.com/acmesh-official/acme.sh) and [Let's Encrypt](https://letsencrypt.org/).

Furthermore, this project integrates with [fail2ban](https://github.com/fail2ban/fail2ban) to enhance security by monitoring and banning suspicious requests based on custom logging rules.

To reduce the overhead of managing deployments, this project provides standard CI/CD pipelines for setting up automatic building and deployment on real servers.

## Key Features

- **Dynamic NGINX Configuration**: Automatically generates NGINX configs based on container metadata using `docker-gen`.
- **Automated SSL Management**: Issues and renews SSL certificates using `acme-companion` and `acme.sh`.
- **Podman Quadlet Orchestration**: Utilizes Podman Quadlet for defining and managing pods, networks, and containers.
- **Suspicious Request Logging**: Custom NGINX logging format to capture suspicious requests for `fail2ban` monitoring.
- **CI/CD Pipelines**: Predefined workflows for automated building and deployment.
