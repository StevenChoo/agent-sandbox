#!/usr/bin/env bash
# launch.sh — Build and enter the agent sandbox container.
# Usage: ./scripts/launch.sh [--rebuild] [--exec <cmd>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
ENV_FILE="${PROJECT_DIR}/.env"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${PROJECT_DIR}/docker-compose.override.yml"
CONTAINER_NAME="agent-sandbox"

# ── Detect runtime (prefer podman, fall back to docker) ───────────────────────
if command -v podman &>/dev/null; then
  RUNTIME="podman"
  COMPOSE_CMD="podman-compose"
  # Podman-compose fallback: use podman compose subcommand if available
  if ! command -v podman-compose &>/dev/null; then
    if podman compose version &>/dev/null 2>&1; then
      COMPOSE_CMD="podman compose"
    else
      echo "ERROR: Neither podman-compose nor 'podman compose' found. Install podman-compose:" >&2
      echo "  pip install podman-compose" >&2
      exit 1
    fi
  fi
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
  COMPOSE_CMD="docker compose"
else
  echo "ERROR: Neither podman nor docker found." >&2
  exit 1
fi

echo "→ Runtime: ${RUNTIME}"

# ── Docker compatibility warning ──────────────────────────────────────────────
if [[ "${RUNTIME}" == "docker" ]]; then
  echo "WARNING: Docker detected. 'userns_mode: keep-id' is Podman-only and will" >&2
  echo "         be ignored — bind-mounted files will appear as root:root inside" >&2
  echo "         the container. Use Podman for correct file ownership." >&2
fi

# ── Build compose file args ───────────────────────────────────────────────────
COMPOSE_FILES="-f ${COMPOSE_FILE}"
if [[ -f "${OVERRIDE_FILE}" ]]; then
  COMPOSE_FILES="${COMPOSE_FILES} -f ${OVERRIDE_FILE}"
  echo "→ Override: docker-compose.override.yml loaded"
fi

# ── .env check ────────────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi

# ── Validate HOST_HOME is not a placeholder ───────────────────────────────────
HOST_HOME_VALUE=$(grep -E '^HOST_HOME=' "${ENV_FILE}" | cut -d= -f2-)
if [[ -z "${HOST_HOME_VALUE}" || \
      "${HOST_HOME_VALUE}" == "/home/johndoe" || \
      "${HOST_HOME_VALUE}" == "/Users/johndoe" ]]; then
  echo "ERROR: HOST_HOME in .env is not set or is still the placeholder value." >&2
  echo "  Linux: HOST_HOME=/home/$(whoami)" >&2
  echo "  macOS: HOST_HOME=/Users/$(whoami)" >&2
  exit 1
fi

# ── Parse args ────────────────────────────────────────────────────────────────
REBUILD=false
EXEC_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    --exec)    EXEC_CMD="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Build ─────────────────────────────────────────────────────────────────────
if [[ "${REBUILD}" == "true" ]]; then
  echo "→ Rebuilding image..."
  ${COMPOSE_CMD} ${COMPOSE_FILES} --env-file "${ENV_FILE}" build
fi

# ── Start (if not running) ────────────────────────────────────────────────────
if ${RUNTIME} ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  read -r -p "→ Container already running. Stop it and continue? [y/N] " answer
  case "${answer}" in
    [yY]|[yY][eE][sS])
      echo "→ Stopping container..."
      ${RUNTIME} stop "${CONTAINER_NAME}"
      ;;
    *)
      echo "→ Aborted."
      exit 0
      ;;
  esac
fi

# ── Pre-flight: required bind mount sources must exist as files/dirs ──────────
# If these paths are missing, Podman silently creates a directory with the same
# name, which causes Claude/Gemini auth to fail in confusing ways.
PREFLIGHT_OK=true
for required_path in \
    "${HOST_HOME_VALUE}/.claude" \
    "${HOST_HOME_VALUE}/.gemini"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "WARNING: ${required_path} does not exist on the host." >&2
    echo "         Run 'claude' or 'gemini' on the host first to create it." >&2
    PREFLIGHT_OK=false
  fi
done
# .claude.json is written only after first login — create it if missing so
# Podman mounts a file rather than creating a directory.
CLAUDE_JSON="${HOST_HOME_VALUE}/.claude.json"
if [[ ! -f "${CLAUDE_JSON}" ]]; then
  echo "→ ${CLAUDE_JSON} not found — creating empty file so Podman mounts it correctly."
  touch "${CLAUDE_JSON}"
fi
if [[ "${PREFLIGHT_OK}" == "false" ]]; then
  read -r -p "→ Some paths are missing. Continue anyway? [y/N] " answer
  case "${answer}" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "→ Aborted."; exit 1 ;;
  esac
fi

echo "→ Starting container..."
${COMPOSE_CMD} ${COMPOSE_FILES} --env-file "${ENV_FILE}" up -d
if ! ${RUNTIME} ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
  echo "ERROR: Container failed to start. Check logs with: ${RUNTIME} logs ${CONTAINER_NAME}" >&2
  exit 1
fi

# ── Exec or attach ────────────────────────────────────────────────────────────
# Set locale explicitly so the host's broken/missing locale config doesn't
# cause podman to print LC_* warnings before the container shell starts.
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [[ -n "${EXEC_CMD}" ]]; then
  ${RUNTIME} exec -it "${CONTAINER_NAME}" zsh -c "${EXEC_CMD}"
else
  echo "→ Attaching shell..."
  ${RUNTIME} exec -it "${CONTAINER_NAME}" zsh
fi
