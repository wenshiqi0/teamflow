#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_INPUT=""
DRY_RUN=false
FORCE=false
WORKFLOW_HOME="${WORKFLOW_HOME:-$HOME/.workflow}"

usage() {
  cat <<'EOF'
Usage: ./scripts/init-project.sh [--dry-run] [--force] <target-project>

Install or update the coding workflow in an existing Git project.

The installer keeps every managed file below .workflow/ and adds that directory
to the project's .gitignore. No other business files are modified.

  --dry-run  Show planned changes without writing anything.
  --force    Back up user-modified conflicts under ~/.workflow/backups and
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
  echo "error: the workflow repository is the installer, not a target project" >&2
  exit 1
fi

for command_name in node opencode basic-memory; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is required; run $SOURCE_ROOT/scripts/bootstrap.sh first" >&2
    exit 1
  fi
done

FILES=(
  ".workflow/config.json"
  ".workflow/instructions/AGENTS.md"
  ".workflow/bin/workflow"
  ".workflow/bin/memory"
  ".workflow/bin/memory-capture"
  ".workflow/bin/test-patch"
  ".workflow/experiments/bin/memory-experiment"
  ".workflow/experiments/bin/memory-compare"
  ".workflow/experiments/scripts/compare_stage.py"
)
while IFS= read -r relative_path; do
  FILES+=("$relative_path")
done < <(
  cd "$SOURCE_ROOT"
  find .workflow/agents .workflow/skills -type f \
    ! -path '*/__pycache__/*' ! -name '*.pyc' -print | sed 's#^./##' | sort
)

LEGACY_FILES=(
  "opencode.json"
  ".workflow/opencode.json"
  ".opencode/.gitignore"
  ".opencode/workflow/AGENTS.md"
  "scripts/memory.sh"
  "scripts/opencode.sh"
  ".workflow/bin/emotion-benchmark"
  ".workflow/bin/memory-experiment"
  ".workflow/bin/memory-compare"
  ".workflow/skills/extract-memory/scripts/run_experiment.py"
  ".workflow/skills/extract-memory/scripts/compare_stage.py"
  ".workflow/agents/emotion-evaluator-glm.md"
  ".workflow/agents/emotion-evaluator-mimo.md"
  ".workflow/agents/emotion-evaluator-deepseek.md"
  ".workflow/skills/detect-emotional-salience/scripts/run_benchmark.py"
  ".workflow/skills/detect-emotional-salience/examples/teacher-gold-v1.json"
)
while IFS= read -r relative_path; do
  LEGACY_FILES+=("$relative_path")
done < <(
  cd "$SOURCE_ROOT"
  find .workflow/agents .workflow/skills -type f -print | \
    sed -e 's#^\.workflow/agents/#.opencode/agents/#' \
        -e 's#^\.workflow/skills/#.opencode/skills/#' | sort
)

MANIFEST_RELATIVE=".workflow/manifest.json"
MANIFEST_PATH="$TARGET_ROOT/$MANIFEST_RELATIVE"
LEGACY_MANIFEST_PATH="$TARGET_ROOT/.opencode/workflow-manifest.json"
HAD_LEGACY_INSTALL=false
[[ -f "$LEGACY_MANIFEST_PATH" ]] && HAD_LEGACY_INSTALL=true
CONFLICTS=()
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
  fi
done

for relative_path in "${LEGACY_FILES[@]}"; do
  destination_path="$TARGET_ROOT/$relative_path"
  [[ -f "$destination_path" ]] || continue
  legacy_hash_manifest="$LEGACY_MANIFEST_PATH"
  [[ "$relative_path" == .workflow/* ]] && legacy_hash_manifest="$MANIFEST_PATH"
  previous_hash="$(manifest_hash "$legacy_hash_manifest" "$relative_path")"
  current_hash="$(sha256_file "$destination_path")"
  if [[ -z "$previous_hash" || "$current_hash" != "$previous_hash" ]]; then
    CONFLICTS+=("$relative_path (legacy)")
  fi
done

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
  [[ -d "$TARGET_ROOT/.opencode" ]] && printf '%-10s %s\n' "remove" ".opencode/ runtime"
  if find "$TARGET_ROOT/.workflow" -type f -name '*.pyc' -print -quit 2>/dev/null | grep -q .; then
    printf '%-10s %s\n' "remove" ".workflow/**/__pycache__/"
  fi
  printf '%-10s %s\n' "ignore" ".workflow/ via .gitignore"
  exit 0
fi

"$SOURCE_ROOT/scripts/setup-memory.sh" >/dev/null

BACKUP_ROOT=""
if (( ${#CONFLICTS[@]} > 0 )); then
  project_name="$(basename "$TARGET_ROOT")"
  timestamp="$(date -u +'%Y%m%dT%H%M%SZ')"
  BACKUP_ROOT="$WORKFLOW_HOME/backups/${project_name}-${timestamp}"
  mkdir -p "$BACKUP_ROOT"
  for conflict in "${CONFLICTS[@]}"; do
    relative_path="${conflict% (legacy)}"
    relative_path="${relative_path%/ (contains unmanaged files)}"
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

for relative_path in "${FILES[@]}"; do
  source_path="$SOURCE_ROOT/$relative_path"
  destination_path="$TARGET_ROOT/$relative_path"
  mkdir -p "$(dirname "$destination_path")"
  cp -p "$source_path" "$destination_path"
done
chmod +x "$TARGET_ROOT/.workflow/bin/workflow" "$TARGET_ROOT/.workflow/bin/memory" "$TARGET_ROOT/.workflow/bin/memory-capture" "$TARGET_ROOT/.workflow/bin/test-patch" "$TARGET_ROOT/.workflow/experiments/bin/memory-experiment" "$TARGET_ROOT/.workflow/experiments/bin/memory-compare"

for relative_path in "${LEGACY_FILES[@]}"; do
  [[ -f "$TARGET_ROOT/$relative_path" ]] && rm -f "$TARGET_ROOT/$relative_path"
done
if [[ -d "$TARGET_ROOT/.opencode" ]]; then
  rm -rf "$TARGET_ROOT/.opencode"
fi
find "$TARGET_ROOT/.workflow" -type f -name '*.pyc' -delete
find "$TARGET_ROOT/.workflow" -type d -name '__pycache__' -empty -delete

if [[ -f "$TARGET_ROOT/.gitignore" ]]; then
  node - "$TARGET_ROOT/.gitignore" "$HAD_LEGACY_INSTALL" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const removeLegacyHarnessIgnore = process.argv[3] === "true";
let text = fs.readFileSync(file, "utf8");
text = text.replace(/(?:^|\n)# OpenCode workflow runtime\n\.workflow\/\n?/g, "\n");
if (removeLegacyHarnessIgnore) text = text.replace(/(?:^|\n)\.opencode\/\n?/g, "\n");
if (text === ".workflow/\n" || text === ".workflow/") text = "";
text = text.replace(/^\n+/, "").replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "\n");
if (text.length === 0) fs.unlinkSync(file);
else fs.writeFileSync(file, text.endsWith("\n") ? text : `${text}\n`);
NODE
fi

if [[ ! -f "$TARGET_ROOT/.gitignore" ]]; then
  printf '# Local coding workflow runtime\n.workflow/\n' > "$TARGET_ROOT/.gitignore"
elif ! grep -qxF '.workflow/' "$TARGET_ROOT/.gitignore"; then
  printf '\n# Local coding workflow runtime\n.workflow/\n' >> "$TARGET_ROOT/.gitignore"
fi

EXCLUDE_PATH="$(git -C "$TARGET_ROOT" rev-parse --git-path info/exclude)"
if [[ "$EXCLUDE_PATH" != /* ]]; then EXCLUDE_PATH="$TARGET_ROOT/$EXCLUDE_PATH"; fi
if [[ -f "$EXCLUDE_PATH" ]]; then
  node - "$EXCLUDE_PATH" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");
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

LAUNCHER_DIR="${WORKFLOW_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER_PATH="$LAUNCHER_DIR/workflow"
if [[ -f "$LAUNCHER_PATH" ]] && ! grep -q 'agent-workflow-launcher' "$LAUNCHER_PATH"; then
  echo "warning: not replacing unrelated command: $LAUNCHER_PATH" >&2
else
  mkdir -p "$LAUNCHER_DIR"
  install -m 0755 "$SOURCE_ROOT/scripts/workflow" "$LAUNCHER_PATH"
fi

VALIDATION_HOME="${TMPDIR:-/tmp}/agent-workflow-init-validation"
mkdir -p "$VALIDATION_HOME"
SKILL_OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$SKILL_OUTPUT_FILE"' EXIT
(
  cd "$TARGET_ROOT"
  HOME="$VALIDATION_HOME" ./.workflow/bin/workflow debug agent planner >/dev/null
  HOME="$VALIDATION_HOME" ./.workflow/bin/workflow debug agent coder >/dev/null
  HOME="$VALIDATION_HOME" ./.workflow/bin/workflow debug agent test-writer >/dev/null
  HOME="$VALIDATION_HOME" ./.workflow/bin/workflow debug skill >"$SKILL_OUTPUT_FILE" 2>/dev/null
  grep -q 'plan-change' "$SKILL_OUTPUT_FILE"
  grep -q 'basic-memory-cli' "$SKILL_OUTPUT_FILE"
)

echo "Workflow installed in: $TARGET_ROOT/.workflow"
echo "Managed manifest: $MANIFEST_PATH"
if [[ -n "$BACKUP_ROOT" ]]; then
  echo "Replaced files were backed up to: $BACKUP_ROOT"
fi
if command -v workflow >/dev/null 2>&1; then
  echo "Run: cd '$TARGET_ROOT' && workflow"
else
  echo "Run: cd '$TARGET_ROOT' && ./.workflow/bin/workflow"
  echo "Add ${LAUNCHER_DIR} to PATH to use the 'workflow' command globally."
fi
