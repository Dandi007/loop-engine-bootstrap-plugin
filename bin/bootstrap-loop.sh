#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="${BOOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_ROOT="${BOOT_RUN_ROOT:-$HOME/.loop-engine/bootstrap/$RUN_ID}"

LOOP_ENGINE_CLI="${LOOP_ENGINE_CLI:-/data/code/self/loop-engine/dist/cli.js}"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-/data/code/self/loop-engine/dist/lib/store-cli.js}"
LOOP_EVENTS_CLI="${LOOP_EVENTS_CLI:-$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"
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
export REF_LIBRARY_DIR="${REF_LIBRARY_DIR:-/data/vault/docs/specs}"
export REF_LIBRARY_INDEX="${REF_LIBRARY_INDEX:-$REF_LIBRARY_DIR/index.md}"

# Target repo is the repository the bootstrap loop will improve.
if [ -z "${BOOT_TARGET_REPO:-}" ] || [ ! -d "$BOOT_TARGET_REPO/.git" ]; then
  echo "[bootstrap-loop] BOOT_TARGET_REPO must point at a git repository" >&2
  exit 2
fi

mkdir -p "$RUN_ROOT"
export PLUGIN_ROOT RUN_ROOT LOOP_ENGINE_CLI LOOP_STORE_CLI DD_PLUGIN_ROOT
export LOOP_ENGINE_RUNTIME_ROOT="${LOOP_ENGINE_RUNTIME_ROOT:-$HOME/.loop-engine}"

# Store directories (same as before, PR_STORE_DIR reused for merge statuses).
export IDEA_STORE_DIR="$RUN_ROOT/stores/idea"
export SPEC_PR_STORE_DIR="$RUN_ROOT/stores/spec-pr"
export SPEC_VERDICT_STORE_DIR="$RUN_ROOT/stores/spec-verdict"
export TRIGGER_STORE_DIR="$RUN_ROOT/stores/trigger"
export PR_STORE_DIR="$RUN_ROOT/stores/pr"
export VERDICT_STORE_DIR="$RUN_ROOT/stores/verdict"
export WORKSPACE_REPO="$RUN_ROOT/workspace-repo"
export DIFF_DIR="$RUN_ROOT/diffs"

# Fleet manifests.
export FLEET_IMPL="$RUN_ROOT/fleet-impl.yaml"
export FLEET_MERGE="$RUN_ROOT/fleet-merge.yaml"

# Models / runtimes (shared sensible defaults; override via env).
export BOOT_DRAFT_MODEL="${BOOT_DRAFT_MODEL:-set_claude_ccswitch_glm}"
export BOOT_DRAFT_RUNTIME="${BOOT_DRAFT_RUNTIME:-claude-code}"
export BOOT_REVIEW_MODEL="${BOOT_REVIEW_MODEL:-set_claude_ccswitch_glm}"
export BOOT_CLAUDE_CONFIG_DIR="${BOOT_CLAUDE_CONFIG_DIR:-$RUN_ROOT/.claude-lingzhi}"
export DD_WORK_MODEL="${DD_WORK_MODEL:-$BOOT_DRAFT_MODEL}"
export DD_WORK_RUNTIME="${DD_WORK_RUNTIME:-claude-code}"
export DD_REVIEW_MODEL="${DD_REVIEW_MODEL:-set_claude_ccswitch_glm}"
export DD_CLAUDE_CONFIG_DIR="${DD_CLAUDE_CONFIG_DIR:-$BOOT_CLAUDE_CONFIG_DIR}"
export DD_ACCEPT_CMD="${DD_ACCEPT_CMD:-make gate BASE=origin/main BRANCH=\$(git rev-parse --abbrev-ref HEAD)}"
export BOOT_MAX_PASSES="${BOOT_MAX_PASSES:-64}"
export BOOT_MERGE_MAX_PASSES="${BOOT_MERGE_MAX_PASSES:-16}"

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

# Seed the batch idea entry point: one idea triggers the batch drafter to produce 3-5 specs.
idea_payload="$(
  IDEA_ID="${BOOT_IDEA_ID:-batch-idea-$(date +%s)}" node -e '
process.stdout.write(JSON.stringify({
  id: process.env.IDEA_ID,
  status: "open",
  feedback: "(none)",
  feedback_file: "",
}));
'
)"
node "$LOOP_STORE_CLI" "$IDEA_STORE_DIR" put "$idea_payload" >/dev/null

# Render Fleet 1: impl phase (batch draft + parallel impl + verify, no merge).
node "$PLUGIN_ROOT/scripts/render-template.mjs" \
  "$PLUGIN_ROOT/workflows/fleet-impl.yaml.tpl" "$FLEET_IMPL"

# Render Fleet 2: merge phase (sequential merge of all ready-to-merge branches).
node "$PLUGIN_ROOT/scripts/render-template.mjs" \
  "$PLUGIN_ROOT/workflows/fleet-merge.yaml.tpl" "$FLEET_MERGE"

# === PHASE 1: Batch draft + parallel impl + verify ===
echo "[bootstrap-loop] Phase 1: batch draft + parallel impl + verify"
echo "[bootstrap-loop] run_root=$RUN_ROOT target=$BOOT_TARGET_REPO"
impl_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_IMPL" "$RUN_ROOT/runs/impl" 2>&1) || true
echo "$impl_result"

# loop 层事件正门（design §3.1）：Phase 1 结束 → 进入 merge。
# 写入刚结束阶段（impl）的 runs root；观测旁路，失败容忍（|| true），不中断主流程。
node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/impl" \
  --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}' || true

# === PHASE 2: Sequential merge ===
echo "[bootstrap-loop] Phase 2: sequential merge"
merge_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_MERGE" "$RUN_ROOT/runs/merge" 2>&1) || true
echo "$merge_result"

# loop 层事件正门（design §3.1）：Phase 2 结束 → done。
# 写入刚结束阶段（merge）的 runs root；观测旁路，失败容忍（|| true），不中断主流程。
node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/merge" \
  --kind phase_change --label bootstrap --detail '{"from":"merge","to":"done"}' || true

echo "[bootstrap-loop] batch complete"