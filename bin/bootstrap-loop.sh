#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="${BOOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_ROOT="${BOOT_RUN_ROOT:-$PLUGIN_ROOT/.runtime/live/$RUN_ID}"

LOOP_ENGINE_CLI="${LOOP_ENGINE_CLI:-/data/code/self/loop-engine/dist/cli.js}"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-/data/code/self/loop-engine/dist/lib/store-cli.js}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "[bootstrap-loop] missing $label: $path" >&2
    echo "[bootstrap-loop] build Loop Engine first: cd /data/code/self/loop-engine && npm run build" >&2
    exit 3
  fi
}

require_file "$LOOP_ENGINE_CLI" "LOOP_ENGINE_CLI"
require_file "$LOOP_STORE_CLI" "LOOP_STORE_CLI"

# Reference library: old specs pool, read-only inspiration.
REF_LIBRARY_DIR="${REF_LIBRARY_DIR:-/data/vault/docs/specs}"
REF_LIBRARY_INDEX="${REF_LIBRARY_INDEX:-$REF_LIBRARY_DIR/index.md}"

# Target repo is the repository the bootstrap loop will improve.
if [ -z "${BOOT_TARGET_REPO:-}" ] || [ ! -d "$BOOT_TARGET_REPO/.git" ]; then
  echo "[bootstrap-loop] BOOT_TARGET_REPO must point at a git repository" >&2
  exit 2
fi

mkdir -p "$RUN_ROOT"
export PLUGIN_ROOT RUN_ROOT LOOP_ENGINE_CLI LOOP_STORE_CLI DD_PLUGIN_ROOT
export IDEA_STORE_DIR="$RUN_ROOT/stores/idea"
export SPEC_PR_STORE_DIR="$RUN_ROOT/stores/spec-pr"
export SPEC_VERDICT_STORE_DIR="$RUN_ROOT/stores/spec-verdict"
export TRIGGER_STORE_DIR="$RUN_ROOT/stores/trigger"
export PR_STORE_DIR="$RUN_ROOT/stores/pr"
export VERDICT_STORE_DIR="$RUN_ROOT/stores/verdict"
export WORKSPACE_REPO="$RUN_ROOT/workspace-repo"
export DIFF_DIR="$RUN_ROOT/diffs"
export RUNTIME_FLEET="$RUN_ROOT/fleet.yaml"

# Models / runtimes (shared sensible defaults; override via env).
export BOOT_DRAFT_MODEL="${BOOT_DRAFT_MODEL:-set_claude_ccswitch_glm}"
export BOOT_DRAFT_RUNTIME="${BOOT_DRAFT_RUNTIME:-claude-code}"
export BOOT_REVIEW_MODEL="${BOOT_REVIEW_MODEL:-set_claude_ccswitch_glm}"
export BOOT_WORK_MODEL="${BOOT_WORK_MODEL:-set_claude_ccswitch_glm}"
export BOOT_CLAUDE_CONFIG_DIR="${BOOT_CLAUDE_CONFIG_DIR:-$RUN_ROOT/.claude-lingzhi}"
export DD_WORK_MODEL="${DD_WORK_MODEL:-$BOOT_WORK_MODEL}"
export DD_WORK_RUNTIME="${DD_WORK_RUNTIME:-claude-code}"
export DD_REVIEW_MODEL="${DD_REVIEW_MODEL:-set_claude_ccswitch_glm}"
export DD_CLAUDE_CONFIG_DIR="${DD_CLAUDE_CONFIG_DIR:-$BOOT_CLAUDE_CONFIG_DIR}"
export DD_ACCEPT_CMD="${DD_ACCEPT_CMD:-npm test}"
export BOOT_MAX_PASSES="${BOOT_MAX_PASSES:-16}"

mkdir -p "$IDEA_STORE_DIR" "$SPEC_PR_STORE_DIR" "$SPEC_VERDICT_STORE_DIR" \
  "$TRIGGER_STORE_DIR" "$PR_STORE_DIR" "$VERDICT_STORE_DIR" \
  "$DIFF_DIR" "$RUN_ROOT/logs"

# Prepare isolated workspace clone.
if [ ! -d "$WORKSPACE_REPO/.git" ]; then
  rm -rf "$WORKSPACE_REPO"
  mkdir -p "$(dirname "$WORKSPACE_REPO")"
  git clone -q "$BOOT_TARGET_REPO" "$WORKSPACE_REPO"
  git -C "$WORKSPACE_REPO" config user.name "Bootstrap Loop"
  git -C "$WORKSPACE_REPO" config user.email "bootstrap@example.invalid"
  # Reviewers may write feedback inside the workspace; keep it out of the candidate branch.
  printf '.dd-review/\n' >> "$WORKSPACE_REPO/.git/info/exclude"
fi
export WORKSPACE_BASE_BRANCH="$(git -C "$WORKSPACE_REPO" symbolic-ref --short HEAD)"

# Seed the Spec Loop entry point with one open idea.
# The idea store is the only queue that needs external seeding; everything else is routed by the fleet.
idea_payload="$(
  IDEA_ID="${BOOT_IDEA_ID:-idea-$(date +%s)}" node -e '
process.stdout.write(JSON.stringify({
  id: process.env.IDEA_ID,
  status: "open",
  feedback: "(none)",
  feedback_file: "",
}));
'
)"
node "$LOOP_STORE_CLI" "$IDEA_STORE_DIR" put "$idea_payload" >/dev/null

# Render the fleet manifest from template.
FLEET_TEMPLATE="$PLUGIN_ROOT/workflows/fleet.yaml.tpl"
node "$PLUGIN_ROOT/scripts/render-template.mjs" "$FLEET_TEMPLATE" "$RUNTIME_FLEET"

echo "[bootstrap-loop] run_root=$RUN_ROOT target=$BOOT_TARGET_REPO"
node "$LOOP_ENGINE_CLI" drain "$RUNTIME_FLEET" "$RUN_ROOT/runs"
