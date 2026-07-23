#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_INPUT=""
DRY_RUN=false
FORCE=false
TEAMFLOW_HOME="${TEAMFLOW_HOME:-${WORKFLOW_HOME:-$HOME/.teamflow}}"

usage() {
  cat <<'EOF'
Usage: ./scripts/init-project.sh [--dry-run] [--force] <target-project>

Install or update teamflow in an existing Git project.

The installer keeps every managed file below .teamflow/ and adds that directory
to the project's .gitignore. No other business files are modified.

  --dry-run  Show planned changes without writing anything.
  --force    Back up user-modified conflicts under ~/.teamflow/backups and
             replace them. Unchanged files update automatically.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$TARGET_INPUT" ]]; then
        echo "error: provide exactly one target project" >&2
        exit 1
      fi
      TARGET_INPUT="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET_INPUT" ]]; then
  usage >&2
  exit 1
fi
if [[ ! -d "$TARGET_INPUT" ]]; then
  echo "error: target directory does not exist: $TARGET_INPUT" >&2
  exit 1
fi

TARGET_ROOT="$(git -C "$TARGET_INPUT" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$TARGET_ROOT" ]]; then
  echo "error: target must be inside an existing Git repository" >&2
  exit 1
fi
TARGET_ROOT="$(cd "$TARGET_ROOT" && pwd -P)"
if [[ "$TARGET_ROOT" == "$SOURCE_ROOT" ]]; then
  echo "error: the teamflow repository is the installer, not a target project" >&2
  exit 1
fi

for command_name in node opencode basic-memory; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is required; run $SOURCE_ROOT/scripts/bootstrap.sh first" >&2
    exit 1
  fi
done

FILES=(
  ".teamflow/config.json"
  ".teamflow/instructions/AGENTS.md"
  ".teamflow/bin/teamflow"
  ".teamflow/bin/memory"
  ".teamflow/bin/memory-capture"
  ".teamflow/bin/test-patch"
  ".teamflow/experiments/bin/memory-experiment"
  ".teamflow/experiments/bin/memory-compare"
  ".teamflow/experiments/scripts/compare_stage.py"
)
while IFS= read -r relative_path; do
  FILES+=("$relative_path")
done < <(
  cd "$SOURCE_ROOT"
  find .teamflow/agents .teamflow/skills -type f \
    ! -path '*/__pycache__/*' ! -name '*.pyc' -print | sed 's#^./##' | sort
)

LEGACY_FILES=(
  "opencode.json"
  ".teamflow/opencode.json"
  ".opencode/.gitignore"
  ".opencode/workflow/AGENTS.md"
  "scripts/memory.sh"
  "scripts/opencode.sh"
  ".teamflow/bin/emotion-benchmark"
  ".teamflow/bin/memory-experiment"
  ".teamflow/bin/memory-compare"
  ".teamflow/skills/extract-memory/scripts/run_experiment.py"
  ".teamflow/skills/extract-memory/scripts/compare_stage.py"
  ".teamflow/agents/emotion-evaluator-glm.md"
  ".teamflow/agents/emotion-evaluator-mimo.md"
  ".teamflow/agents/emotion-evaluator-deepseek.md"
  ".teamflow/skills/detect-emotional-salience/scripts/run_benchmark.py"
  ".teamflow/skills/detect-emotional-salience/examples/teacher-gold-v1.json"
)
while IFS= read -r relative_path; do
  LEGACY_FILES+=("$relative_path")
done < <(
  cd "$SOURCE_ROOT"
  find .teamflow/agents .teamflow/skills -type f -print | \
    sed -e 's#^\.teamflow/agents/#.opencode/agents/#' \
        -e 's#^\.teamflow/skills/#.opencode/skills/#' | sort
)

MANIFEST_RELATIVE=".teamflow/manifest.json"
MANIFEST_PATH="$TARGET_ROOT/$MANIFEST_RELATIVE"
LEGACY_MANIFEST_PATH="$TARGET_ROOT/.opencode/workflow-manifest.json"
LEGACY_WORKFLOW_ROOT="$TARGET_ROOT/.workflow"
LEGACY_WORKFLOW_MANIFEST="$LEGACY_WORKFLOW_ROOT/manifest.json"
HAD_LEGACY_INSTALL=false
[[ -f "$LEGACY_MANIFEST_PATH" ]] && HAD_LEGACY_INSTALL=true
[[ -d "$LEGACY_WORKFLOW_ROOT" ]] && HAD_LEGACY_INSTALL=true
CONFLICTS=()
BACKUP_PATHS=()
LEGACY_DIR_CONFLICT=false

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

manifest_hash() {
  local manifest_path="$1"
  local relative_path="$2"
  if [[ ! -f "$manifest_path" ]]; then
    return 0
  fi
  node -e '
    const fs = require("node:fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(manifest.files?.[process.argv[2]] || "");
  ' "$manifest_path" "$relative_path" 2>/dev/null || true
}

for relative_path in "${FILES[@]}"; do
  source_path="$SOURCE_ROOT/$relative_path"
  destination_path="$TARGET_ROOT/$relative_path"
  if [[ ! -f "$destination_path" ]] || cmp -s "$source_path" "$destination_path"; then
    continue
  fi
  previous_hash="$(manifest_hash "$MANIFEST_PATH" "$relative_path")"
  current_hash="$(sha256_file "$destination_path")"
  if [[ -z "$previous_hash" || "$current_hash" != "$previous_hash" ]]; then
    CONFLICTS+=("$relative_path")
    BACKUP_PATHS+=("$relative_path")
  fi
done

for relative_path in "${LEGACY_FILES[@]}"; do
  destination_path="$TARGET_ROOT/$relative_path"
  [[ -f "$destination_path" ]] || continue
  legacy_hash_manifest="$LEGACY_MANIFEST_PATH"
  [[ "$relative_path" == .teamflow/* ]] && legacy_hash_manifest="$MANIFEST_PATH"
  previous_hash="$(manifest_hash "$legacy_hash_manifest" "$relative_path")"
  current_hash="$(sha256_file "$destination_path")"
  if [[ -z "$previous_hash" || "$current_hash" != "$previous_hash" ]]; then
    CONFLICTS+=("$relative_path (legacy)")
    BACKUP_PATHS+=("$relative_path")
  fi
done

LEGACY_WORKFLOW_FILES=()
if [[ -d "$LEGACY_WORKFLOW_ROOT" ]]; then
  while IFS= read -r path; do
    relative_path="${path#"$TARGET_ROOT/"}"
    [[ "$relative_path" == ".workflow/manifest.json" ]] && continue
    LEGACY_WORKFLOW_FILES+=("$relative_path")
    previous_hash="$(manifest_hash "$LEGACY_WORKFLOW_MANIFEST" "$relative_path")"
    current_hash="$(sha256_file "$path")"
    if [[ -n "$previous_hash" ]]; then
      if [[ "$current_hash" != "$previous_hash" ]]; then
        CONFLICTS+=("$relative_path (modified legacy runtime)")
        BACKUP_PATHS+=("$relative_path")
      fi
      continue
    fi

    mapped_path=".teamflow/${relative_path#.workflow/}"
    managed_collision=false
    for candidate in "${FILES[@]}"; do
      if [[ "$mapped_path" == "$candidate" ]]; then
        managed_collision=true
        break
      fi
    done
    if [[ "$managed_collision" == true ]] || \
       { [[ -f "$TARGET_ROOT/$mapped_path" ]] && ! cmp -s "$path" "$TARGET_ROOT/$mapped_path"; }; then
      CONFLICTS+=("$relative_path (unmanaged legacy collision)")
      BACKUP_PATHS+=("$relative_path")
    fi
  done < <(find "$LEGACY_WORKFLOW_ROOT" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print | sort)
fi

if [[ -d "$TARGET_ROOT/.opencode" ]]; then
  UNMANAGED_LEGACY="$(find "$TARGET_ROOT/.opencode" -type f \
    ! -path "$TARGET_ROOT/.opencode/node_modules/*" \
    ! -path "$TARGET_ROOT/.opencode/package.json" \
    ! -path "$TARGET_ROOT/.opencode/package-lock.json" \
    ! -path "$TARGET_ROOT/.opencode/bun.lock" \
    ! -path "$TARGET_ROOT/.opencode/workflow-manifest.json" \
    | while IFS= read -r path; do
        relative="${path#"$TARGET_ROOT/"}"
        managed=false
        for candidate in "${LEGACY_FILES[@]}"; do
          if [[ "$relative" == "$candidate" ]]; then managed=true; break; fi
        done
        [[ "$managed" == true ]] || printf '%s\n' "$relative"
      done)"
  if [[ -n "$UNMANAGED_LEGACY" ]]; then
    LEGACY_DIR_CONFLICT=true
    CONFLICTS+=(".opencode/ (contains unmanaged files)")
    BACKUP_PATHS+=(".opencode/")
  fi
fi

if (( ${#CONFLICTS[@]} > 0 )) && [[ "$FORCE" != true ]]; then
  echo "error: target contains user-modified or unmanaged conflicts:" >&2
  printf '  %s\n' "${CONFLICTS[@]}" >&2
  echo "Rerun with --force to back them up and replace them." >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Target: $TARGET_ROOT"
  for relative_path in "${FILES[@]}"; do
    destination_path="$TARGET_ROOT/$relative_path"
    if [[ ! -f "$destination_path" ]]; then
      action="create"
    elif cmp -s "$SOURCE_ROOT/$relative_path" "$destination_path"; then
      action="unchanged"
    else
      action="update"
    fi
    printf '%-10s %s\n' "$action" "$relative_path"
  done
  for relative_path in "${LEGACY_FILES[@]}"; do
    [[ -e "$TARGET_ROOT/$relative_path" ]] && printf '%-10s %s\n' "remove" "$relative_path"
  done
  if [[ -d "$LEGACY_WORKFLOW_ROOT" ]]; then
    printf '%-10s %s\n' "migrate" ".workflow/ runtime to .teamflow/"
  fi
  [[ -d "$TARGET_ROOT/.opencode" ]] && printf '%-10s %s\n' "remove" ".opencode/ runtime"
  if find "$TARGET_ROOT/.teamflow" -type f -name '*.pyc' -print -quit 2>/dev/null | grep -q .; then
    printf '%-10s %s\n' "remove" ".teamflow/**/__pycache__/"
  fi
  printf '%-10s %s\n' "ignore" ".teamflow/ via .gitignore"
  exit 0
fi

"$SOURCE_ROOT/scripts/setup-memory.sh" >/dev/null

BACKUP_ROOT=""
if (( ${#CONFLICTS[@]} > 0 )); then
  project_name="$(basename "$TARGET_ROOT")"
  timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
  BACKUP_ROOT="$TEAMFLOW_HOME/backups/${project_name}-${timestamp}"
  mkdir -p "$BACKUP_ROOT"
  for relative_path in "${BACKUP_PATHS[@]}"; do
    if [[ "$relative_path" == ".opencode" || "$relative_path" == ".opencode/" ]]; then
      continue
    fi
    if [[ -f "$TARGET_ROOT/$relative_path" ]]; then
      mkdir -p "$BACKUP_ROOT/$(dirname "$relative_path")"
      cp -p "$TARGET_ROOT/$relative_path" "$BACKUP_ROOT/$relative_path"
    fi
  done
  if [[ "$LEGACY_DIR_CONFLICT" == true ]]; then
    cp -R "$TARGET_ROOT/.opencode" "$BACKUP_ROOT/.opencode"
  fi
fi

if [[ -d "$LEGACY_WORKFLOW_ROOT" ]]; then
  for relative_path in "${LEGACY_WORKFLOW_FILES[@]}"; do
    previous_hash="$(manifest_hash "$LEGACY_WORKFLOW_MANIFEST" "$relative_path")"
    [[ -n "$previous_hash" ]] && continue
    mapped_path=".teamflow/${relative_path#.workflow/}"
    managed_collision=false
    for candidate in "${FILES[@]}"; do
      if [[ "$mapped_path" == "$candidate" ]]; then
        managed_collision=true
        break
      fi
    done
    [[ "$managed_collision" == true ]] && continue
    if [[ ! -e "$TARGET_ROOT/$mapped_path" ]]; then
      mkdir -p "$(dirname "$TARGET_ROOT/$mapped_path")"
      cp -p "$TARGET_ROOT/$relative_path" "$TARGET_ROOT/$mapped_path"
    fi
  done
fi

for relative_path in "${FILES[@]}"; do
  source_path="$SOURCE_ROOT/$relative_path"
  destination_path="$TARGET_ROOT/$relative_path"
  mkdir -p "$(dirname "$destination_path")"
  cp -p "$source_path" "$destination_path"
done
chmod +x "$TARGET_ROOT/.teamflow/bin/teamflow" "$TARGET_ROOT/.teamflow/bin/memory" "$TARGET_ROOT/.teamflow/bin/memory-capture" "$TARGET_ROOT/.teamflow/bin/test-patch" "$TARGET_ROOT/.teamflow/experiments/bin/memory-experiment" "$TARGET_ROOT/.teamflow/experiments/bin/memory-compare"

for relative_path in "${LEGACY_FILES[@]}"; do
  [[ -f "$TARGET_ROOT/$relative_path" ]] && rm -f "$TARGET_ROOT/$relative_path"
done
if [[ -d "$TARGET_ROOT/.opencode" ]]; then
  rm -rf "$TARGET_ROOT/.opencode"
fi
if [[ -d "$LEGACY_WORKFLOW_ROOT" ]]; then
  rm -rf "$LEGACY_WORKFLOW_ROOT"
fi
find "$TARGET_ROOT/.teamflow" -type f -name '*.pyc' -delete
find "$TARGET_ROOT/.teamflow" -type d -name '__pycache__' -empty -delete

if [[ -f "$TARGET_ROOT/.gitignore" ]]; then
  node - "$TARGET_ROOT/.gitignore" "$HAD_LEGACY_INSTALL" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const removeLegacyHarnessIgnore = process.argv[3] === "true";
let text = fs.readFileSync(file, "utf8");
text = text.replace(/(?:^|\n)# (?:OpenCode workflow|Local coding workflow|Local teamflow) runtime\n\.teamflow\/\n?/g, "\n");
if (removeLegacyHarnessIgnore) {
  text = text.replace(/(?:^|\n)# (?:OpenCode workflow|Local coding workflow) runtime\n\.workflow\/\n?/g, "\n");
  text = text.replace(/(?:^|\n)\.workflow\/\n?/g, "\n");
  text = text.replace(/(?:^|\n)\.opencode\/\n?/g, "\n");
}
if (text === ".teamflow/\n" || text === ".teamflow/") text = "";
text = text.replace(/^\n+/, "").replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "\n");
if (text.length === 0) fs.unlinkSync(file);
else fs.writeFileSync(file, text.endsWith("\n") ? text : `${text}\n`);
NODE
fi

if [[ ! -f "$TARGET_ROOT/.gitignore" ]]; then
  printf '# Local teamflow runtime\n.teamflow/\n' > "$TARGET_ROOT/.gitignore"
elif ! grep -qxF '.teamflow/' "$TARGET_ROOT/.gitignore"; then
  printf '\n# Local teamflow runtime\n.teamflow/\n' >> "$TARGET_ROOT/.gitignore"
fi

EXCLUDE_PATH="$(git -C "$TARGET_ROOT" rev-parse --git-path info/exclude)"
if [[ "$EXCLUDE_PATH" != /* ]]; then EXCLUDE_PATH="$TARGET_ROOT/$EXCLUDE_PATH"; fi
if [[ -f "$EXCLUDE_PATH" ]]; then
  node - "$EXCLUDE_PATH" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");
text = text.replace(/(?:^|\n)# Local (?:coding workflow|teamflow) runtime\n\.teamflow\/\n?/g, "\n");
text = text.replace(/(?:^|\n)# Local coding workflow runtime\n\.workflow\/\n?/g, "\n");
text = text.replace(/^\n+/, "").replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "\n");
fs.writeFileSync(file, text);
NODE
fi

mkdir -p "$(dirname "$MANIFEST_PATH")"
node - "$SOURCE_ROOT" "$MANIFEST_PATH" "${FILES[@]}" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const sourceRoot = process.argv[2];
const manifestPath = process.argv[3];
const files = process.argv.slice(4);
const hashes = {};
for (const relativePath of files) {
  const content = fs.readFileSync(path.join(sourceRoot, relativePath));
  hashes[relativePath] = crypto.createHash("sha256").update(content).digest("hex");
}
fs.writeFileSync(manifestPath, `${JSON.stringify({
  schema_version: 2,
  installed_at: new Date().toISOString(),
  source: "wenshiqi0/teamflow",
  files: hashes,
}, null, 2)}\n`);
NODE

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
  install -m 0755 "$SOURCE_ROOT/scripts/teamflow" "$LAUNCHER_PATH"
fi

VALIDATION_HOME="${TMPDIR:-/tmp}/agent-teamflow-init-validation"
mkdir -p "$VALIDATION_HOME"
SKILL_OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$SKILL_OUTPUT_FILE"' EXIT
(
  cd "$TARGET_ROOT"
  HOME="$VALIDATION_HOME" ./.teamflow/bin/teamflow debug agent planner >/dev/null
  HOME="$VALIDATION_HOME" ./.teamflow/bin/teamflow debug agent coder >/dev/null
  HOME="$VALIDATION_HOME" ./.teamflow/bin/teamflow debug agent test-writer >/dev/null
  HOME="$VALIDATION_HOME" ./.teamflow/bin/teamflow debug skill >"$SKILL_OUTPUT_FILE" 2>/dev/null
  grep -q 'plan-change' "$SKILL_OUTPUT_FILE"
  grep -q 'basic-memory-cli' "$SKILL_OUTPUT_FILE"
)

echo "Teamflow installed in: $TARGET_ROOT/.teamflow"
echo "Managed manifest: $MANIFEST_PATH"
if [[ -n "$BACKUP_ROOT" ]]; then
  echo "Replaced files were backed up to: $BACKUP_ROOT"
fi
if command -v teamflow >/dev/null 2>&1; then
  echo "Run: cd '$TARGET_ROOT' && teamflow"
else
  echo "Run: cd '$TARGET_ROOT' && ./.teamflow/bin/teamflow"
  echo "Add ${LAUNCHER_DIR} to PATH to use the 'teamflow' command globally."
fi
