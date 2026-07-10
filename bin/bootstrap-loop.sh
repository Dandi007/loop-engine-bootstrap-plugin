#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_ID="${BOOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
# 收口：invocation scratch（stores/workspace/fleet 等）落统一 runtime root 下的 caller 工作区
# root/work/bootstrap/<id>，与引擎的 uuid run 输出目录 root/runs/<uuid> 解耦。root 从 config SSoT 读。
LE_ROOT="$(node -e 'try{const c=JSON.parse(require("fs").readFileSync(require("os").homedir()+"/.config/loop-engine/config.json","utf8"));process.stdout.write(c.runtimeRoot||"")}catch{}')"
LE_ROOT="${LE_ROOT:-$HOME/.loop-engine}"
RUN_ROOT="${BOOT_RUN_ROOT:-$LE_ROOT/work/bootstrap/$RUN_ID}"

LOOP_ENGINE_CLI="${LOOP_ENGINE_CLI:-/data/code/self/loop-engine/dist/cli.js}"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-/data/code/self/loop-engine/dist/lib/store-cli.js}"
LOOP_EVENTS_CLI="${LOOP_EVENTS_CLI:-$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"

# Model–Provider–Runtime 三元表接线：若设了 <prefix>_SELECT（如 BOOT_DRAFT_SELECT=glm/code-plan），
# 用 loop-engine 的 model-resolver 解析成 (runtime, model) 覆盖 <prefix>_RUNTIME/<prefix>_MODEL。
# 未设 SELECT / 未知选择器 / resolver 缺失 → 保留既有直传值（向后兼容）。resolver 是 engine dist
# （缺 .js 扩展名 ESM），须带 engine 的 extension-loader（裸 node 会 ERR_MODULE_NOT_FOUND；loader
# 从 resolver 路径派生）。
LOOP_MODEL_RESOLVER="${LOOP_MODEL_RESOLVER:-$(dirname "$LOOP_ENGINE_CLI")/lib/model-resolver.js}"
LOOP_ENGINE_ESM_LOADER="${LOOP_ENGINE_ESM_LOADER:-$(cd "$(dirname "$LOOP_MODEL_RESOLVER")/../.." 2>/dev/null && pwd)/scripts/register-node-esm-extension-loader.mjs}"
resolve_select() {
  local prefix="$1"
  local select_var="${prefix}_SELECT"
  local select="${!select_var:-}"
  [ -z "$select" ] && return 0
  local kv
  if kv="$(node --import "$LOOP_ENGINE_ESM_LOADER" "$LOOP_MODEL_RESOLVER" "$select" 2>/dev/null)"; then
    local RUNTIME MODEL PROVIDER
    eval "$kv"
    export "${prefix}_RUNTIME=$RUNTIME"
    export "${prefix}_MODEL=$MODEL"
    echo "[bootstrap-loop] ${prefix} ← selector '${select}' → runtime=${RUNTIME} model=${MODEL}"
  else
    echo "[bootstrap-loop] WARN: selector '${select}' 未知或 resolver 不可用，${prefix} 保留直传" >&2
  fi
}

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
# 不再强制 LOOP_ENGINE_RUNTIME_ROOT（那会覆盖 config SSoT）；drain 落点由引擎按统一 root 自动分配。
export LOOP_ENGINE_CALLER="${LOOP_ENGINE_CALLER:-bootstrap}"

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
export BOOT_REVIEW_RUNTIME="${BOOT_REVIEW_RUNTIME:-claude-code}"
export BOOT_CLAUDE_CONFIG_DIR="${BOOT_CLAUDE_CONFIG_DIR:-$RUN_ROOT/.claude-lingzhi}"
export DD_WORK_MODEL="${DD_WORK_MODEL:-$BOOT_DRAFT_MODEL}"
export DD_WORK_RUNTIME="${DD_WORK_RUNTIME:-claude-code}"
export DD_REVIEW_MODEL="${DD_REVIEW_MODEL:-set_claude_ccswitch_glm}"
export DD_REVIEW_RUNTIME="${DD_REVIEW_RUNTIME:-claude-code}"
export DD_CLAUDE_CONFIG_DIR="${DD_CLAUDE_CONFIG_DIR:-$BOOT_CLAUDE_CONFIG_DIR}"
# SELECT 优先：设了就用三元表覆盖上面的 RUNTIME/MODEL 直传缺省。draft/work 是实现 agent，
# review（spec 层 + dd 层）是审查 agent，四条 lane 都可独立经三元表选择 runtime+model。
resolve_select BOOT_DRAFT
resolve_select BOOT_REVIEW
resolve_select DD_WORK
resolve_select DD_REVIEW
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
impl_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_IMPL" --label impl 2>&1) || true
echo "$impl_result"
# 从 drain 终局 stdout 取实际 runs_root（引擎自动分配的 root/runs/<uuid>）供 loop-events 定位。
impl_runs_root=$(printf '%s' "$impl_result" | tail -1 | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).runs_root||"")}catch{}})')

# loop 层事件正门（design §3.1）：Phase 1 结束 → 进入 merge。
# 写入刚结束阶段（impl）的 runs root；观测旁路，失败容忍（|| true），不中断主流程。
[ -n "$impl_runs_root" ] && node "$LOOP_EVENTS_CLI" append --runs-root "$impl_runs_root" \
  --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}' || true

# === PHASE 2: Sequential merge ===
echo "[bootstrap-loop] Phase 2: sequential merge"
merge_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_MERGE" --label merge 2>&1) || true
echo "$merge_result"
merge_runs_root=$(printf '%s' "$merge_result" | tail -1 | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).runs_root||"")}catch{}})')

# loop 层事件正门（design §3.1）：Phase 2 结束 → done。
# 写入刚结束阶段（merge）的 runs root；观测旁路，失败容忍（|| true），不中断主流程。
[ -n "$merge_runs_root" ] && node "$LOOP_EVENTS_CLI" append --runs-root "$merge_runs_root" \
  --kind phase_change --label bootstrap --detail '{"from":"merge","to":"done"}' || true

echo "[bootstrap-loop] batch complete"