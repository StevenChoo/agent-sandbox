# agent-sandbox

Rootless Podman container providing an isolated development environment for AI agents (Claude Code, Gemini CLI). The agent sees only what you explicitly mount, writes only where you allow it, and cannot escalate privileges beyond the container boundary.

## Security model

Running an AI agent with access to your machine is a meaningful trust decision. This sandbox is designed so that a misbehaving or compromised agent causes the least possible damage.

**Rootless Podman — no root daemon**
The container runtime itself runs entirely as your host user. There is no root daemon (unlike Docker), so a container escape lands in your user account, not root. The attack surface for privilege escalation is significantly smaller.

**Kernel namespace isolation**
The agent runs in separate PID, mount, and network namespaces. It cannot see host processes, cannot reach the host filesystem beyond what is explicitly mounted, and cannot use host-side sudo or PAM — regardless of what UID it runs as inside the container.

**Minimal mount surface**
Only three categories of paths are visible inside the container:
- `~/.claude` and `~/.gemini` — agent credentials and config (read-write so token refreshes work)
- Named volumes for tool caches (npm, gradle, maven, uv, go) — no host path exposure
- Project directories you explicitly add in `docker-compose.override.yml`

Nothing else from your host filesystem is mounted. The agent cannot read your SSH keys, AWS credentials, other projects, or anything outside this list.

**Write access is opt-in per directory**
Project directories are mounted read-write or read-only individually in `docker-compose.override.yml`. The agent can only modify files in directories you explicitly grant write access to.

**No container socket passthrough**
The Docker/Podman socket is not mounted into the container. The agent cannot spawn sibling containers or escape via container management APIs. (This is why the Terraform MCP server is excluded — see Improvements.)

**`no-new-privileges`**
Set on the container, preventing any process inside from gaining capabilities beyond what it starts with — even if a setuid binary is present.

**Explicit port forwarding**
Only ports `3000`, `8080`, and `8443` are forwarded. Services the agent starts on other ports are not reachable from the host.

---

## Design

- `~/.claude` and `~/.gemini` mounted from the host into the container so the agent uses your existing credentials — no separate login required inside the container
- Write access scoped to project directories added via `docker-compose.override.yml`
- MCP servers run as child processes inside the container (`stdio` transport) — no host socket forwarding required
- HTTP MCP servers (e.g. runpod-docs) reach the internet directly
- Host-side MCP servers reachable via `host.containers.internal`
- Tool caches (npm, gradle, maven, uv, go) persisted in named volumes — survive container restarts

## Prerequisites

```bash
# Ubuntu 24.04
sudo apt-get install podman podman-compose

# Verify rootless setup
podman info | grep -i rootless
```

## Setup

```bash
git clone <repo> agent-sandbox
cd agent-sandbox

cp .env.example .env
# Edit .env — set CONTEXT7_API_KEY and set AGENT_UID/AGENT_GID to your host user
id -u && id -g

# Build the image (first time, takes ~10 min)
./scripts/launch.sh --rebuild
```

### Agent UID/GID

Set `AGENT_UID` and `AGENT_GID` in `.env` to match your host user (`id -u && id -g`). This allows the agent to read and write files in the mounted directories, which are owned by your host user. The isolation boundary is the container's mount namespace — not the UID — so matching UIDs does not grant the agent any host privileges beyond what is explicitly mounted.

### Adding Your Own Directory Mounts

Project-specific bind mounts live in `docker-compose.override.yml`, which is git-ignored so machine-specific paths are never committed.

```bash
cp docker-compose.override.example.yml docker-compose.override.yml
# Edit docker-compose.override.yml and add your paths
```

Each additional bind mount follows this structure:

```yaml
services:
  agent:
    volumes:
      - type: bind
        source: ${HOST_HOME}/path/to/your/directory
        target: /home/agent/path/to/your/directory
        read_only: false   # set to true for read-only access
```

`read_only: false` — agent can create, edit, and delete files here.
`read_only: true`  — agent can read but not modify.

Only paths explicitly listed here are visible inside the container. If a path is not mounted, the agent has no knowledge it exists.

## Usage

```bash
# Start and attach shell
./scripts/launch.sh

# Run a specific command
./scripts/launch.sh --exec "claude"

# Rebuild image after Dockerfile changes
./scripts/launch.sh --rebuild

# Stop the container
podman stop agent-sandbox

# Stop and remove
podman-compose -f docker-compose.yml down
```

## MCP Configuration

`config/mcp.json` contains the Claude Code MCP server config. Because `~/.claude` is mounted directly from the host user, place it there on the **host**:

```bash
# On the host
cp config/mcp.json ~/.claude/mcp.json
```

The container picks it up automatically via the bind mount.

## Toolchain

| Tool | Version |
|------|---------|
| Node.js | LTS (via nvm) |
| JDK | 17, 21, 25 (via SDKMAN, default: 21) |
| Gradle | System |
| Maven | System |
| Python | 3.x system + uv |
| Go | 1.22.x |
| AWS CLI | v2 |
| Claude Code | Latest (npm) |
| Gemini CLI | Latest (npm) |

Switch JDK inside the container:
```bash
sdk use java 17.0.11-tem
sdk use java 21.0.3-tem
```

## Port Forwarding

Default forwarded ports: `3000`, `8080`, `8443`. Add more in `docker-compose.yml` under `ports` as your projects require.

## macOS Notes

See `docs/macos-notes.md`.

---

## Improvements

### Terraform MCP server
The `hashicorp/terraform-mcp-server` MCP runs via `docker run`, which requires either Docker socket passthrough or nested container execution. Both options weaken container isolation.

**Reason excluded:** Socket passthrough gives the agent the ability to spawn arbitrary containers on the host — a partial container escape. Nested Podman requires `--privileged` or elevated capabilities, undermining the isolation model.

**When ready:** Ask for updated instructions to run the terraform MCP as an HTTP/SSE proxy on the host, reachable via `host.containers.internal`, which avoids both issues.

---

### Cross-platform support (macOS)
Launch script and bind mount paths are Linux-first. Podman on macOS runs inside a Linux VM (`podman machine`), which adds a layer of indirection for bind mounts of the Mac home directory.

**When ready:** Ask for updated macOS instructions including `podman machine` setup and bind mount path translation.
