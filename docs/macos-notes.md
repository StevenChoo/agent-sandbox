# macOS Notes

Podman on macOS runs inside a Linux VM (`podman machine`). This adds two requirements beyond the standard Linux setup: bind-mount paths must be explicitly shared into the VM, and your host UID/GID values will differ from the Linux defaults.

## Prerequisites

```bash
brew install podman podman-compose
```

## Podman Machine Setup

The Podman machine VM does **not** automatically expose your Mac filesystem. Only the paths you explicitly register are visible inside the VM — which matches the security goal of this sandbox (don't expose more than necessary).

The three paths that `docker-compose.yml` bind-mounts are:

| Host path | Purpose |
|-----------|---------|
| `~/.claude` | Claude Code config and MCP settings |
| `~/.claude.json` | Claude credentials |
| `~/.gemini` | Gemini CLI config and credentials |

Register exactly those paths with the machine. Use your actual home directory — `~` does not expand inside the `podman machine` command:

### Fresh machine

```bash
podman machine init --cpus 4 --memory 8192 \
  --volume /Users/your-username/.claude:/Users/your-username/.claude \
  --volume /Users/your-username/.claude.json:/Users/your-username/.claude.json \
  --volume /Users/your-username/.gemini:/Users/your-username/.gemini

podman machine start
```

### Existing machine (missing volume registrations)

```bash
podman machine stop

podman machine set \
  --volume /Users/your-username/.claude:/Users/your-username/.claude \
  --volume /Users/your-username/.claude.json:/Users/your-username/.claude.json \
  --volume /Users/your-username/.gemini:/Users/your-username/.gemini

podman machine start
```

Verify registrations:

```bash
podman machine inspect | grep -A 10 Volumes
```

### Adding project directories

Each directory you add to `docker-compose.override.yml` also needs a matching volume registration in the machine:

```bash
podman machine stop
podman machine set --volume /Users/your-username/path/to/project:/Users/your-username/path/to/project
podman machine start
```

## .env Configuration

macOS UIDs and GIDs differ from Linux defaults. Get your actual values:

```bash
id -u   # typically 501
id -g   # typically 20  (staff group)
```

Set them in `.env`:

```
HOST_HOME=/Users/your-username     # not /home/...
AGENT_UID=501                      # output of id -u
AGENT_GID=20                       # output of id -g
```

### GID 20 note

GID 20 is the `staff` group on macOS but is assigned to `dialout` in Ubuntu. The Dockerfile handles this automatically — it removes whichever existing group occupies the target GID before creating the `agent` group.

## File Ownership

`userns_mode: keep-id` maps the container process to the same UID on the host. For files written inside the container to appear owned by your Mac user, `AGENT_UID` in `.env` must match `id -u` exactly. With a matching UID, files created by the agent are readable on the host without any permission changes.

## MCP Config

```bash
cp config/mcp.json ~/.claude/mcp.json
```

This is picked up automatically via the `~/.claude` bind mount.

## Build and Launch

```bash
./scripts/launch.sh --rebuild
```
