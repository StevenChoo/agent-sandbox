# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A rootless Podman container providing an isolated development environment for AI agents (Claude Code, Gemini CLI). The container runs as user `agent` (UID/GID matching your host user, default 1000) with write access scoped to directories you explicitly mount. MCP servers run as child processes inside the container.

## Commands

### Build & Launch (from host)
```bash
# First-time setup with image rebuild (~10 min)
./scripts/launch.sh --rebuild

# Start/attach to existing container
./scripts/launch.sh

# Run a single command inside the container
./scripts/launch.sh --exec "command-here"

# Rebuild image without launching
podman-compose -f docker-compose.yml build --no-cache
```

### Container Management
```bash
podman stop agent-sandbox
podman-compose -f docker-compose.yml down
podman ps --format '{{.Names}}'
```

### Java Version Switching (inside container)
```bash
sdk use java 17.0.11-tem
sdk use java 21.0.3-tem
sdk use java 25.0.3-tem
```

## Architecture

**Runtime:** Rootless Podman (falls back to Docker). No root inside container — `agent` user has sudo only for `apt-get`.

**File System Model:**
- `~/.claude.json`, `~/.claude/`, and `~/.gemini/` from the host user mounted read-write into the container (Claude and Gemini write credential refreshes back to disk)
- Named volumes persist tool caches: npm, gradle, maven, uv, go
- User-defined project directories added via `docker-compose.override.yml` for read-write access
- Files written by agent are group-writable (umask 002); host user reads them via membership in the `agent` group

**MCP Server Model:**
- **Stdio servers** (run as child processes in container): awslabs.aws-documentation, duckduckgo, context7, memory, git, sequential-thinking
- **HTTP server** (direct internet): runpod-docs at `https://docs.runpod.io/mcp`
- **Host-side servers**: reachable via `host.containers.internal` hostname
- Config lives in `config/mcp.json` — must be copied to `~/.claude/mcp.json` inside the container

**Ports forwarded:** 3000, 8080, 8443

## Key Configuration Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 24.04 image with all tools installed |
| `docker-compose.yml` | Service definition, volumes, ports, environment |
| `docker-compose.override.example.yml` | Template for machine-specific project mounts |
| `.env` | Required secrets/config (git-ignored); copy from `.env.example` |
| `scripts/launch.sh` | Main entry point: build, start, attach |
| `config/mcp.json` | Claude Code MCP server config to copy into container |

## Initial Setup Sequence

1. `cp .env.example .env` — set `HOST_HOME`, `AGENT_UID`/`AGENT_GID`, `CONTEXT7_API_KEY`
2. Optionally: `cp docker-compose.override.example.yml docker-compose.override.yml` and add project mounts
3. `./scripts/launch.sh --rebuild`
4. On host: add your user to the `agent` group for read-back access to container-written files
5. On host: `cp config/mcp.json ~/.claude/mcp.json` — picked up automatically via the bind mount

## Tech Stack Inside Container

- **Node.js** LTS via nvm
- **Java** 17, 21, 25 via SDKMAN (default: 21)
- **Python** 3.x + `uv` package manager
- **Go** 1.26.3
- **Build tools:** Gradle, Maven, build-essential
- **CLI tools:** AWS CLI v2, jq, yq, ripgrep, fd-find, tree

## Known Constraints

- **No Terraform MCP server:** Excluded because it requires Docker socket passthrough, which would allow partial container escape. Run it as an HTTP proxy on the host instead (`host.containers.internal`).
- **macOS:** Requires explicit `podman machine` volume registration — only the three bind-mount paths (`.claude`, `.claude.json`, `.gemini`) are registered, keeping the VM's filesystem exposure minimal. Each project directory added via `docker-compose.override.yml` needs a matching `podman machine set --volume` entry. See `docs/macos-notes.md` for the full setup.
