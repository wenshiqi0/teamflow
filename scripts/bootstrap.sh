#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
WORKFLOW_HOME="${WORKFLOW_HOME:-$HOME/.workflow}"

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

if [[ ! -f "$WORKFLOW_HOME/.env" ]]; then
  mkdir -p "$WORKFLOW_HOME"
  if [[ -f .workflow/.env ]]; then
    cp .workflow/.env "$WORKFLOW_HOME/.env"
    echo "Migrated model credentials to $WORKFLOW_HOME/.env."
  elif [[ -f .env ]]; then
    cp .env "$WORKFLOW_HOME/.env"
    echo "Migrated model credentials to $WORKFLOW_HOME/.env."
  else
    cp .env.example "$WORKFLOW_HOME/.env"
    echo "Created $WORKFLOW_HOME/.env; add the model API keys before running the workflow."
  fi
fi

LAUNCHER_DIR="${WORKFLOW_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER_PATH="$LAUNCHER_DIR/workflow"
if [[ -f "$LAUNCHER_PATH" ]] && ! grep -q 'agent-workflow-launcher' "$LAUNCHER_PATH"; then
  echo "warning: not replacing unrelated command: $LAUNCHER_PATH" >&2
else
  mkdir -p "$LAUNCHER_DIR"
  install -m 0755 "$ROOT_DIR/scripts/workflow" "$LAUNCHER_PATH"
  echo "Installed workflow launcher: $LAUNCHER_PATH"
fi

echo "OpenCode $(opencode --version) is available."
echo "$(basic-memory --version) is available."
echo "Next: edit .env, run setup-memory.sh and doctor.sh, then init-project.sh <target-project>."
