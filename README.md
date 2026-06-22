# Postfix on Alpine

[![Publish Docker Image](https://github.com/croessner/docker-postfix/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/croessner/docker-postfix/actions/workflows/docker-publish.yml)
[![License: MIT](https://img.shields.io/github/license/croessner/docker-postfix)](./LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/croessner/docker-postfix)](https://github.com/croessner/docker-postfix/commits/main)
[![Stars](https://img.shields.io/github/stars/croessner/docker-postfix?style=social)](https://github.com/croessner/docker-postfix/stargazers)

This project builds a complete Postfix image on **Alpine Linux**, compiles **a pinned Postfix version directly from source**, enables **dynamic lookup tables and optional databases**, and links Postfix against **`libtlsrpt`** so that **TLSRPT** works end-to-end.

The image uses a clean multi-stage build, pinned upstream sources, predictable runtime defaults, GitHub Actions for publishing, and a runtime model that is **environment-driven first** without blocking **fully custom `main.cf`, `master.cf`, and map files** when you need exact control.

## Table of Contents

- [Goals](#goals)
- [Project Structure](#project-structure)
- [Included Components](#included-components)
- [Quick Start](#quick-start)
- [Publishing](#publishing)
- [License](#license)
- [Operating Model](#operating-model)
- [Important Volumes / Mountpoints](#important-volumes--mountpoints)
- [Environment Variables](#environment-variables)
- [Custom Configuration and Maps](#custom-configuration-and-maps)
- [TLS and TLSRPT](#tls-and-tlsrpt)
- [Container Logging](#container-logging)
- [Health Check](#health-check)
- [Development / Convenience](#development--convenience)
- [References](#references)

## Goals

- Alpine-based runtime
- Pinned Postfix source version via Docker build args
- Pinned `libtlsrpt` build and link integration
- Full-featured lookup support, including common database and dynamic map modules
- Runtime configuration via `POSTFIX_*` and `POSTFIXMASTER_*`
- Support for `_FILE` secret variants for every environment variable
- Optional full replacement of `main.cf` and `master.cf`
- Support for custom maps, map compilation hooks, and init scripts
- Clean container logging via `stdout` using `postlogd`
- GitHub Actions for publishing and upstream checks

## Project Structure

```text
.
├── Dockerfile
├── docker-entrypoint.sh
├── docker-healthcheck.sh
├── README.md
├── .env.example
├── .gitignore
├── Makefile
├── defaults
│   ├── main.cf
│   └── master.cf
├── examples
│   ├── docker-compose.yml
│   ├── custom-config
│   │   ├── main.cf.d
│   │   └── master.cf.d
│   ├── init
│   └── maps
└── .github
    └── workflows
        ├── docker-publish.yml
        └── postfix-upstream-check.yml
```

## Included Components

The image is built in two stages:

- A **builder stage** compiles Postfix from the official source tarball, builds `libtlsrpt`, and builds `tinycdb`
- A **runtime stage** keeps Alpine as the base image and only ships the required runtime libraries and the compiled Postfix payload

Current pinned defaults in this repository:

- Postfix `3.11.4`
- `libtlsrpt` `0.5.0`
- Alpine `3.23`

The running container exposes the usual built-in Postfix table types plus dynamic lookups such as:

- `cdb`
- `ldap`
- `lmdb`
- `memcache`
- `mongodb`
- `mysql`
- `nis`
- `pcre`
- `pgsql`
- `sdbm`
- `sqlite`
- and the regular built-in lookup types such as `hash`, `btree`, `cidr`, `regexp`, `socketmap`, `tcp`, `texthash`, `unionmap`, `unix`

The default `master.cf` also includes:

- `smtp`
- `submission`
- `submissions`
- `postlog` / `postlogd` for container-friendly logging

## Quick Start

### 1. Build

```bash
docker build -t postfix .
```

To pin an explicit upstream release:

```bash
docker build \
  --build-arg POSTFIX_VERSION=3.11.4 \
  --build-arg POSTFIX_SHA256=226ec59a18e43e277691005e31496f7608b9ba9210be600a267fb217a4a6cee9 \
  -t postfix:3.11.4 .
```

Multi-arch build with `buildx`:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg POSTFIX_VERSION=3.11.4 \
  --build-arg POSTFIX_SHA256=226ec59a18e43e277691005e31496f7608b9ba9210be600a267fb217a4a6cee9 \
  -t postfix:3.11.4 \
  .
```

### 2. Prepare environment

```bash
cp .env.example .env
```

### 3. Start with Compose

```bash
make compose-up
```

### 4. Inspect the running configuration

```bash
docker exec postfix postconf -n
docker exec postfix postconf -m
docker exec postfix postconf smtp_tlsrpt_enable smtp_tlsrpt_socket_name maillog_file
```

## Publishing

This repository includes a GitHub Actions workflow at `.github/workflows/docker-publish.yml` that publishes the maintainer image to Docker Hub as `chrroessner/postfix`.

It also includes `.github/workflows/postfix-upstream-check.yml`, which runs daily, checks the official Postfix release directory for a newer upstream tarball, refreshes the pinned SHA256, and opens or updates a pull request automatically when the pinned version in this repository is behind upstream.

The workflow runs:

- on pushes to `main`
- on pushes to `master`
- on Git tags matching `v*`
- daily via `schedule`
- manually via `workflow_dispatch`

Required GitHub repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Recommended Docker Hub setup:

- create a public repository in your own namespace, for example `<your-namespace>/postfix`
- create a Docker Hub access token dedicated to CI
- keep `latest` for the default branch
- publish release tags in the form `v<postfix-version>-r<revision>`, for example `v3.11.4-r1`

## License

The repository content is licensed under the MIT License. See [LICENSE](./LICENSE).

The published container image additionally includes Postfix, which is distributed under `IPL-1.0`, plus bundled runtime dependencies such as `libtlsrpt` and `tinycdb`. Because of that, the OCI image metadata declares a combined license expression.

## Operating Model

On startup, the following happens:

1. The entrypoint script prepares runtime directories under `/var/spool/postfix` and `/var/lib/postfix`.
2. It installs the base `main.cf`, `master.cf`, and `dynamicmaps.cf`.
3. If present, it overlays:
   - `/etc/postfix/custom-config/main.cf`
   - `/etc/postfix/custom-config/master.cf`
   - `/etc/postfix/custom-config/dynamicmaps.cf`
4. It appends snippet directories in lexical order:
   - `/etc/postfix/custom-config/main.cf.d/*.cf`
   - `/etc/postfix/custom-config/master.cf.d/*.cf`
   - `/etc/postfix/custom-config/dynamicmaps.cf.d/*.cf`
5. It applies runtime defaults and then processes environment variables:
   - `POSTFIX_*` for `main.cf`
   - `POSTFIXMASTER_*` for `master.cf`
6. It runs `.sh` files from `/docker-entrypoint-init.d`
7. It compiles standard maps and any maps declared in `POSTFIX_RUNTIME_POSTMAPS`
8. It runs `postfix check` and finally starts `postfix start-fg`

## Important Volumes / Mountpoints

| Path in Container | Purpose |
|---|---|
| `/etc/postfix/custom-config` | Full replacement files or config snippets |
| `/etc/postfix/maps` | Custom map files |
| `/docker-entrypoint-init.d` | Init hooks (`.sh`) |
| `/etc/postfix/certs` | TLS certificates and keys |
| `/var/spool/postfix` | Queue data if you want persistence |
| `/var/lib/postfix` | Runtime-owned Postfix data directory |

## Environment Variables

### Runtime defaults

| Variable | Default | Meaning |
|---|---:|---|
| `POSTFIX_RUNTIME_LOG_TO_STDOUT` | `true` | Enable `maillog_file = /dev/stdout` |
| `POSTFIX_RUNTIME_HOSTNAME` | derived | Sets `myhostname` |
| `POSTFIX_RUNTIME_DOMAIN` | derived | Sets `mydomain` |
| `POSTFIX_RUNTIME_DESTINATIONS` | derived | Sets `mydestination` |
| `POSTFIX_RUNTIME_MYNETWORKS` | `127.0.0.0/8 [::1]/128` | Sets `mynetworks` |
| `POSTFIX_RUNTIME_AUTO_POSTMAP_STANDARD` | `true` | Compiles standard text maps |
| `POSTFIX_RUNTIME_POSTMAPS` | empty | Comma-separated extra maps, for example `lmdb:/etc/postfix/maps/transport,lmdb:/etc/postfix/maps/routes` |
| `POSTFIX_RUNTIME_RUN_SCRIPTS` | `true` | Runs `/docker-entrypoint-init.d/*.sh` |
| `POSTFIX_RUNTIME_TLSRPT_SOCKET_NAME` | `run/tlsrpt/tlsrpt.sock` | Sets `smtp_tlsrpt_socket_name` |

### Generic `main.cf` overrides

Every variable named `POSTFIX_<parameter>` becomes:

```text
<parameter> = <value>
```

The suffix is used verbatim as the Postfix parameter name. That matters for parameters with embedded uppercase segments such as `CAfile`.

Examples:

- `POSTFIX_relayhost=[smtp.example.net]:587`
- `POSTFIX_smtpd_tls_cert_file=/etc/postfix/certs/tls.crt`
- `POSTFIX_smtpd_tls_CAfile=/etc/postfix/certs/ca.crt`
- `POSTFIX_smtp_tlsrpt_enable=yes`
- `POSTFIX_transport_maps=lmdb:/etc/postfix/maps/transport`

Every variable also supports a `_FILE` variant:

- `POSTFIX_relayhost_FILE=/run/secrets/postfix_relayhost`
- `POSTFIX_sasl_passwd_FILE=/run/secrets/postfix_sasl_passwd`

### Generic `master.cf` overrides

Every variable named `POSTFIXMASTER_<selector>` becomes a `postconf -P` update.

Encoding rules:

- `__` becomes `/`
- `___` becomes `-`

The remaining characters are preserved verbatim, so use the exact Postfix parameter spelling after the service selector.

Examples:

- `POSTFIXMASTER_submission__inet__syslog_name=postfix/submission`
- `POSTFIXMASTER_submission__inet__smtpd_tls_security_level=encrypt`
- `POSTFIXMASTER_smtps___inet__smtpd_upstream_proxy_protocol=haproxy`

## Custom Configuration and Maps

You have three supported customization levels.

### 1. Env-driven

Use `POSTFIX_*` and `POSTFIXMASTER_*` for most installations. This is the intended fast path.

### 2. File overlays

Mount custom files into `/etc/postfix/custom-config`:

- `main.cf`
- `master.cf`
- `dynamicmaps.cf`

Or mount snippets into:

- `main.cf.d`
- `master.cf.d`
- `dynamicmaps.cf.d`

### 3. Custom maps

Mount map files under `/etc/postfix/maps` and either:

- reference them directly from `POSTFIX_*`
- or request compilation via `POSTFIX_RUNTIME_POSTMAPS`

Example:

```bash
docker run --rm \
  -e POSTFIX_transport_maps=lmdb:/etc/postfix/maps/transport \
  -e POSTFIX_RUNTIME_POSTMAPS=lmdb:/etc/postfix/maps/transport \
  -v $(pwd)/examples/maps:/etc/postfix/maps \
  postfix
```

Important for generated map types such as `hash`, `cdb`, `sdbm` or `lmdb`:

- `postmap` writes the compiled database next to the source file
- the mounted map directory must therefore be writable, or you must mount precompiled map files instead

Important note when replacing `master.cf` completely:

- if `POSTFIX_RUNTIME_LOG_TO_STDOUT=true`, your custom `master.cf` should keep the `postlog` / `postlogd` services
- if you intentionally remove them, also set `POSTFIX_RUNTIME_LOG_TO_STDOUT=false`

## TLS and TLSRPT

TLSRPT support is a hard requirement in this image:

- `libtlsrpt` is built from source
- Postfix is compiled with `-DUSE_TLSRPT`
- Postfix links against `-ltlsrpt`

The container default is:

- `smtp_tlsrpt_enable = no`
- `smtp_tlsrpt_socket_name = run/tlsrpt/tlsrpt.sock`

That socket name is relative to the Postfix queue directory, so the effective default path inside the container is:

```text
/var/spool/postfix/run/tlsrpt/tlsrpt.sock
```

Typical integration pattern:

1. Run a TLSRPT collector sidecar or companion process that exposes a Unix socket.
2. Share the socket path with the Postfix container.
3. Set `POSTFIX_smtp_tlsrpt_enable=yes`.
4. If needed, override `POSTFIX_RUNTIME_TLSRPT_SOCKET_NAME`.

## Container Logging

This image follows the Postfix container logging model documented upstream:

- `postfix start-fg`
- `maillog_file = /dev/stdout`
- `postlogd` wired in through `master.cf`

That gives you standard container log collection without a syslog daemon in the image.

If you prefer a different logging setup:

- set `POSTFIX_RUNTIME_LOG_TO_STDOUT=false`
- provide your own `main.cf` / `master.cf`

## Health Check

The image includes a simple health check based on:

```bash
postfix status
```

## Development / Convenience

Build locally:

```bash
make build
```

Run a local smoke check:

```bash
make test-smoke
```

Create a local SBOM export:

```bash
make sbom-local
```

Inspect registry SBOM data after push:

```bash
make sbom-registry IMAGE_NAME=<your-namespace>/postfix TAG=latest
```

## References

- https://www.postfix.org/
- https://www.postfix.org/TLSRPT_README.html
- https://www.postfix.org/MAILLOG_README.html
- https://github.com/sys4/libtlsrpt
