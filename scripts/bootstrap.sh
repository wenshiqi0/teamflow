#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
DEFAULT_TEAMFLOW_HOME=false
if [[ -z "${TEAMFLOW_HOME+x}" && -z "${WORKFLOW_HOME+x}" ]]; then
  DEFAULT_TEAMFLOW_HOME=true
fi
TEAMFLOW_HOME="${TEAMFLOW_HOME:-${WORKFLOW_HOME:-$HOME/.teamflow}}"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: Node.js 20+ is required" >&2
  exit 1
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if (( NODE_MAJOR < 20 )); then
  echo "error: Node.js 20+ is required; found $(node --version)" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "error: npm is required to install OpenCode" >&2
  exit 1
fi

if ! command -v opencode >/dev/null 2>&1; then
  echo "Installing OpenCode..."
  npm install --global opencode-ai@latest
else
  CURRENT_OPENCODE_VERSION="$(opencode --version)"
  if LATEST_OPENCODE_VERSION="$(npm --fetch-timeout=15000 --fetch-retries=1 view opencode-ai version 2>/dev/null)"; then
    if [[ "$CURRENT_OPENCODE_VERSION" != "$LATEST_OPENCODE_VERSION" ]]; then
      echo "Upgrading OpenCode ${CURRENT_OPENCODE_VERSION} -> ${LATEST_OPENCODE_VERSION}..."
      opencode upgrade "$LATEST_OPENCODE_VERSION" --method npm
    fi
  else
    echo "warning: could not check the latest OpenCode version; keeping ${CURRENT_OPENCODE_VERSION}" >&2
  fi
fi

if ! command -v uv >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required to install uv" >&2
    exit 1
  fi
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

UV_TOOL_BIN_DIR="$(uv tool dir --bin)"
export PATH="$UV_TOOL_BIN_DIR:$PATH"

if command -v basic-memory >/dev/null 2>&1; then
  echo "Checking for a Basic Memory upgrade..."
  BASIC_MEMORY_UPGRADE_TIMEOUT_MS="${BASIC_MEMORY_UPGRADE_TIMEOUT_MS:-120000}"
  if ! node -e '
    const { spawnSync } = require("node:child_process");
    const result = spawnSync(
      "uv",
      ["tool", "install", "--upgrade", "basic-memory"],
      { stdio: "inherit", timeout: Number(process.argv[1]) }
    );
    process.exit(result.status ?? 1);
  ' "$BASIC_MEMORY_UPGRADE_TIMEOUT_MS"; then
    echo "warning: Basic Memory upgrade check failed or timed out; keeping $(basic-memory --version)" >&2
  fi
else
  echo "Installing Basic Memory..."
  uv tool install basic-memory
fi

if [[ ! -f "$TEAMFLOW_HOME/.env" ]]; then
  mkdir -p "$TEAMFLOW_HOME"
  if [[ "$DEFAULT_TEAMFLOW_HOME" == true && -f "$HOME/.workflow/.env" ]]; then
    cp -p "$HOME/.workflow/.env" "$TEAMFLOW_HOME/.env"
    echo "Migrated legacy model credentials to $TEAMFLOW_HOME/.env."
  elif [[ -f .teamflow/.env ]]; then
    cp .teamflow/.env "$TEAMFLOW_HOME/.env"
    echo "Migrated model credentials to $TEAMFLOW_HOME/.env."
  elif [[ -f .env ]]; then
    cp .env "$TEAMFLOW_HOME/.env"
    echo "Migrated model credentials to $TEAMFLOW_HOME/.env."
  else
    cp .env.example "$TEAMFLOW_HOME/.env"
    echo "Created $TEAMFLOW_HOME/.env; add the model API keys before running teamflow."
  fi
fi

LAUNCHER_DIR="${TEAMFLOW_BIN_DIR:-${WORKFLOW_BIN_DIR:-$HOME/.local/bin}}"
LEGACY_COMMAND="$LAUNCHER_DIR/workflow"
if [[ -f "$LEGACY_COMMAND" && ! -L "$LEGACY_COMMAND" ]] && \
   grep -q 'agent-workflow-launcher' "$LEGACY_COMMAND"; then
  rm -f "$LEGACY_COMMAND"
elif [[ -e "$LEGACY_COMMAND" || -L "$LEGACY_COMMAND" ]]; then
  echo "warning: preserving unrelated legacy command: $LEGACY_COMMAND" >&2
fi
LAUNCHER_PATH="$LAUNCHER_DIR/teamflow"
if [[ -f "$LAUNCHER_PATH" ]] && ! grep -q 'agent-teamflow-launcher' "$LAUNCHER_PATH"; then
  echo "warning: not replacing unrelated command: $LAUNCHER_PATH" >&2
else
  mkdir -p "$LAUNCHER_DIR"
  install -m 0755 "$ROOT_DIR/scripts/teamflow" "$LAUNCHER_PATH"
  echo "Installed teamflow launcher: $LAUNCHER_PATH"
fi

echo "OpenCode $(opencode --version) is available."
echo "$(basic-memory --version) is available."
echo "Next: edit .env, run setup-memory.sh and doctor.sh, then init-project.sh <target-project>."
