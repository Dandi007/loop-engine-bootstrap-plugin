#!/usr/bin/env bash
# Acceptance checks for loop-engine-bootstrap-plugin (batch architecture).
# These checks are deterministic and do not call LLMs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# ESM extension resolution: loop-engine dist uses .js-less imports, needs the loader.
export NODE_OPTIONS="--import file:///data/code/self/loop-engine/scripts/register-node-esm-extension-loader.mjs"

check(){ if [ ! -e "$ROOT/$1" ]; then echo "MISSING: $1" >&2; fail=1; else echo "ok: $1"; fi; }

# File existence checks.
check "workflows/fleet-impl.yaml.tpl"
check "workflows/fleet-merge.yaml.tpl"
check "workflows/fleet.yaml.tpl"
check "workflows/spec-gen/draft/workflow.yaml"
check "workflows/spec-gen/draft/personas/drafter.md"
check "workflows/spec-gen/draft/templates/draft.md"
check "workflows/spec-gen/review/workflow.yaml"
check "workflows/spec-gen/review/personas/spec-reviewer.md"
check "workflows/spec-gen/review/templates/spec-review.md"
check "workflows/spec-gen/rework/workflow.yaml"
check "workflows/spec-gen/rework/templates/spec-rework.md"
check "workflows/spec-gen/spec-check/workflow.yaml"
check "workflows/spec-gen/spec-check/templates/spec-check.md"
check "workflows/spec-gen/deploy-verify/workflow.yaml"
check "workflows/spec-gen/deploy-verify/templates/deploy-verify.md"
check "workflows/spec-gen/merger/workflow.yaml"
check "workflows/spec-gen/merger/templates/merger.md"
check "bin/bootstrap-loop.sh"
check "bin/bootstrap-continuous.sh"
check "scripts/render-template.mjs"
check "workflows/spec-gen/contracts/idea.schema.json"
check "workflows/spec-gen/contracts/pr.schema.json"
check "workflows/spec-gen/contracts/spec-pr.schema.json"
check "workflows/spec-gen/contracts/trigger.schema.json"
check "workflows/spec-gen/contracts/verdict.schema.json"
check "tests/pointer-records.test.sh"
check "tests/pointer-consumption.test.sh"
check "bin/spec-inject.sh"

ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
ENGINE_DIST_FLEET="$ENGINE_ROOT/dist/fleet.js"

if [ ! -f "$ENGINE_DIST_FLEET" ]; then
  echo "SKIP: Loop Engine dist missing; build it to run schema validation" >&2
else
  RUN_ROOT="$ROOT/.runtime/test-acceptance"
  rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT"

  export PLUGIN_ROOT="$ROOT"
  export DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
  export RUN_ROOT
  export IDEA_STORE_DIR="$RUN_ROOT/stores/idea"
  export SPEC_PR_STORE_DIR="$RUN_ROOT/stores/spec-pr"
  export SPEC_VERDICT_STORE_DIR="$RUN_ROOT/stores/spec-verdict"
  export TRIGGER_STORE_DIR="$RUN_ROOT/stores/trigger"
  export PR_STORE_DIR="$RUN_ROOT/stores/pr"
  export VERDICT_STORE_DIR="$RUN_ROOT/stores/verdict"
  export WORKSPACE_REPO="$RUN_ROOT/workspace-repo"
  export DIFF_DIR="$RUN_ROOT/diffs"
  export REF_LIBRARY_DIR="$RUN_ROOT/ref-lib"
  export REF_LIBRARY_INDEX="$RUN_ROOT/ref-lib/index.md"
  export BOOT_DRAFT_MODEL="test-model"
  export BOOT_DRAFT_RUNTIME="bash"
  export BOOT_REVIEW_MODEL="test-model"
  export BOOT_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_WORK_MODEL="test-model"
  export DD_WORK_RUNTIME="bash"
  export DD_REVIEW_MODEL="test-model"
  export DD_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_ACCEPT_CMD="npm test"
  export BOOT_MAX_PASSES="8"
  export BOOT_MERGE_MAX_PASSES="8"
  export LOOP_STORE_CLI="${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}"
  export WORKSPACE_BASE_BRANCH="main"

  mkdir -p "$REF_LIBRARY_DIR"
  echo "# Reference library index" > "$REF_LIBRARY_INDEX"

  # --- Fleet-impl schema validation ---
  RENDERED_FLEET_IMPL="$RUN_ROOT/fleet-impl.yaml"
  node "$ROOT/scripts/render-template.mjs" "$ROOT/workflows/fleet-impl.yaml.tpl" "$RENDERED_FLEET_IMPL"
  echo "ok: fleet-impl.yaml rendered"

  export ENGINE_DIST_FLEET
  fleet_impl_js="$(mktemp --suffix=.mjs)"
  cat > "$fleet_impl_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
try {
  const manifest = loadFleetManifest(process.env.RENDERED_FLEET_IMPL);
  const labels = manifest.pipelines.map((p) => p.label).sort();
  const expected = ["deploy-verify", "draft", "review", "rework", "spec-check", "spec-review", "spec-rework", "work"];
  if (JSON.stringify(labels) !== JSON.stringify(expected)) {
    console.error("unexpected pipeline labels: " + labels.join(","));
    process.exit(1);
  }
  console.log("ok: fleet-impl manifest schema valid");
} catch (e) {
  console.error("fleet-impl manifest invalid: " + e.message);
  process.exit(1);
}
NODE
  RENDERED_FLEET_IMPL="$RENDERED_FLEET_IMPL" node "$fleet_impl_js" || fail=1
  rm -f "$fleet_impl_js"

  # --- Fleet-merge schema validation ---
  RENDERED_FLEET_MERGE="$RUN_ROOT/fleet-merge.yaml"
  node "$ROOT/scripts/render-template.mjs" "$ROOT/workflows/fleet-merge.yaml.tpl" "$RENDERED_FLEET_MERGE"
  echo "ok: fleet-merge.yaml rendered"

  fleet_merge_js="$(mktemp --suffix=.mjs)"
  cat > "$fleet_merge_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
try {
  const manifest = loadFleetManifest(process.env.RENDERED_FLEET_MERGE);
  const labels = manifest.pipelines.map((p) => p.label).sort();
  const expected = ["merger"];
  if (JSON.stringify(labels) !== JSON.stringify(expected)) {
    console.error("unexpected pipeline labels: " + labels.join(","));
    process.exit(1);
  }
  console.log("ok: fleet-merge manifest schema valid");
} catch (e) {
  console.error("fleet-merge manifest invalid: " + e.message);
  process.exit(1);
}
NODE
  RENDERED_FLEET_MERGE="$RENDERED_FLEET_MERGE" node "$fleet_merge_js" || fail=1
  rm -f "$fleet_merge_js"

  # INV-2: Impl Loop pipelines (work, review, rework) must point at dev-dispatch, not local copies.
  # deploy-verify and merger are new bootstrap-plugin pipelines that should point at local.
  impl_check_js="$(mktemp --suffix=.mjs)"
  cat > "$impl_check_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
const manifest = loadFleetManifest(process.env.RENDERED_FLEET_IMPL);
const impl = ["work", "review", "rework"];
const local = ["deploy-verify", "spec-check", "draft", "spec-review", "spec-rework"];
const localPrefix = process.env.PLUGIN_ROOT + "/";
let ok = true;
for (const label of impl) {
  const p = manifest.pipelines.find((p) => p.label === label);
  if (!p) { console.error("missing pipeline: " + label); ok = false; continue; }
  if (p.config_dir.startsWith(localPrefix)) {
    console.error("FAIL: " + label + " config_dir is local: " + p.config_dir);
    ok = false;
  }
}
for (const label of local) {
  const p = manifest.pipelines.find((p) => p.label === label);
  if (!p) { console.error("missing pipeline: " + label); ok = false; continue; }
  if (!p.config_dir.startsWith(localPrefix)) {
    console.error("FAIL: " + label + " config_dir is not local: " + p.config_dir);
    ok = false;
  }
}
if (ok) console.log("ok: INV-2 config_dir routing correct");
else process.exit(1);
NODE
  RENDERED_FLEET_IMPL="$RENDERED_FLEET_IMPL" node "$impl_check_js" || fail=1
  rm -f "$impl_check_js"

  # INV-1: bin/ contains bootstrap-loop.sh, bootstrap-continuous.sh, and spec-inject.sh (SPEC-006).
  bin_scripts=($(find "$ROOT/bin" -maxdepth 1 -type f ! -name '.gitkeep' | sort))
  if [ "${#bin_scripts[@]}" -eq 3 ] && [ "$(basename "${bin_scripts[0]}")" = "bootstrap-continuous.sh" ] && [ "$(basename "${bin_scripts[1]}")" = "bootstrap-loop.sh" ] && [ "$(basename "${bin_scripts[2]}")" = "spec-inject.sh" ]; then
    echo "ok: bin/ has bootstrap-continuous.sh + bootstrap-loop.sh + spec-inject.sh"
  else
    echo "FAIL: bin/ contains unexpected scripts: ${bin_scripts[*]}" >&2
    fail=1
  fi

  # INV-3: deploy-verify must claim from ready-to-deploy (guarded by spec-check).
  # merger must claim from ready-to-merge (guarded by deploy-verify).
  inv3_js="$(mktemp --suffix=.mjs)"
  cat > "$inv3_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
const manifest = loadFleetManifest(process.env.RENDERED_FLEET_IMPL);
const mergeManifest = loadFleetManifest(process.env.RENDERED_FLEET_MERGE);
const deployVerify = manifest.pipelines.find((p) => p.label === "deploy-verify");
const specCheck = manifest.pipelines.find((p) => p.label === "spec-check");
const merger = mergeManifest.pipelines.find((p) => p.label === "merger");
let ok = true;
if (!deployVerify) { console.error("missing deploy-verify pipeline"); ok = false; }
if (!specCheck) { console.error("missing spec-check pipeline"); ok = false; }
if (!merger) { console.error("missing merger pipeline"); ok = false; }
if (deployVerify && deployVerify.claim?.from !== "ready-to-deploy") {
  console.error("FAIL: deploy-verify claims from " + deployVerify.claim?.from + ", expected ready-to-deploy");
  ok = false;
}
if (specCheck && specCheck.claim?.from !== "approved") {
  console.error("FAIL: spec-check claims from " + specCheck.claim?.from + ", expected approved");
  ok = false;
}
if (merger && merger.claim?.from !== "ready-to-merge") {
  console.error("FAIL: merger claims from " + merger.claim?.from + ", expected ready-to-merge");
  ok = false;
}
if (ok) console.log("ok: INV-3 deploy-verify guarded by spec-check, merger guarded by deploy-verify");
else process.exit(1);
NODE
  RENDERED_FLEET_IMPL="$RENDERED_FLEET_IMPL" RENDERED_FLEET_MERGE="$RENDERED_FLEET_MERGE" node "$inv3_js" || fail=1
  rm -f "$inv3_js"

  # Deterministic full-chain store state-flow tests (no LLM calls).
  STATE_ROOT="$RUN_ROOT/state-flow"
  rm -rf "$STATE_ROOT"
  mkdir -p "$STATE_ROOT"
  ENGINE_DIST_TEMPLATE="$ENGINE_ROOT/dist/template.js"

  render_template() {
    local tpl="$1"
    local out="$2"
    shift 2
    local ctx="$*"
    local render_js
    render_js="$(mktemp --suffix=.mjs)"
    cat > "$render_js" <<RENDER
import { fill } from "file://$ENGINE_DIST_TEMPLATE";
import { readFileSync, writeFileSync } from "node:fs";
const ctx = {};
for (const pair of process.argv[2].split(/\s+/)) {
  const i = pair.indexOf("=");
  if (i > 0) ctx[pair.slice(0, i)] = pair.slice(i + 1);
}
writeFileSync(process.argv[3], fill(readFileSync(process.argv[4], "utf8"), ctx), "utf8");
RENDER
    node "$render_js" "$ctx" "$out" "$tpl"
    rm -f "$render_js"
  }

  store_put() { node "$LOOP_STORE_CLI" "$1" put "$2"; }
  store_get() { node "$LOOP_STORE_CLI" "$1" get "$2"; }
  store_by_status() { node "$LOOP_STORE_CLI" "$1" list "$2"; }

  # --- spec-rework APPROVE emits an enqueue trigger effect (no direct put) ---
  echo "state-flow: spec-rework APPROVE → enqueue trigger effect"
  sr_approve_root="$STATE_ROOT/sr-approve"
  sr_idea="$sr_approve_root/idea"
  sr_trigger="$sr_approve_root/trigger"
  sr_verdict="$sr_approve_root/spec-verdict"
  mkdir -p "$sr_idea" "$sr_trigger" "$sr_verdict"
  store_put "$sr_verdict" "$(printf '{"id":"verdict-SPEC-002","status":"decided","spec_id":"SPEC-002","spec_file":"/tmp/SPEC-002.md","verdict":"APPROVE","feedback":"ok","feedback_file":""}')"
  sr_script="$sr_approve_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$sr_script" \
    "idea_store_dir=$sr_idea" \
    "trigger_store_dir=$sr_trigger" \
    "spec_verdict_id=verdict-SPEC-002" \
    "spec_id=SPEC-002" \
    "spec_file=/tmp/SPEC-002.md" \
    "verdict=APPROVE" \
    "feedback=ok" \
    "feedback_file="
  sr_approve_out="$(bash "$sr_script")"
  # INV: trigger store dir untouched (no direct put).
  sr_trigger_recs="$(store_by_status "$sr_trigger" open)"
  if echo "$sr_approve_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects[0];if(!a||a.op!=="enqueue"||a.queue!=="trigger"||a.task.id!=="SPEC-002"||a.task.status!=="open"||a.task.feedback!=="(none)"){console.error("bad enqueue effect");process.exit(1)}})'; then
    echo "ok: spec-rework APPROVE emitted enqueue trigger effect"
  else
    echo "FAIL: spec-rework APPROVE did not emit expected enqueue effect: $sr_approve_out" >&2
    fail=1
  fi
  if [ "$(echo "$sr_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 0 ]; then
    echo "ok: spec-rework APPROVE did not directly write trigger store"
  else
    echo "FAIL: spec-rework APPROVE wrote directly to trigger store: $sr_trigger_recs" >&2
    fail=1
  fi

  # --- spec-rework REJECT emits an enqueue idea effect (no direct put) ---
  echo "state-flow: spec-rework REJECT → enqueue idea effect"
  sr_reject_root="$STATE_ROOT/sr-reject"
  sr_idea="$sr_reject_root/idea"
  sr_trigger="$sr_reject_root/trigger"
  sr_verdict="$sr_reject_root/spec-verdict"
  mkdir -p "$sr_idea" "$sr_trigger" "$sr_verdict"
  store_put "$sr_verdict" "$(printf '{"id":"verdict-SPEC-003","status":"decided","spec_id":"SPEC-003","spec_file":"/tmp/SPEC-003.md","verdict":"REJECT","feedback":"too vague","feedback_file":""}')"
  sr_script="$sr_reject_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$sr_script" \
    "idea_store_dir=$sr_idea" \
    "trigger_store_dir=$sr_trigger" \
    "spec_verdict_id=verdict-SPEC-003" \
    "spec_id=SPEC-003" \
    "spec_file=/tmp/SPEC-003.md" \
    "verdict=REJECT" \
    "feedback=too vague" \
    "feedback_file="
  sr_reject_out="$(bash "$sr_script")"
  sr_idea_recs="$(store_by_status "$sr_idea" open)"
  if echo "$sr_reject_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects[0];if(!a||a.op!=="enqueue"||a.queue!=="idea"||a.task.status!=="open"||!a.task.feedback.includes("Spec review REJECT")){console.error("bad enqueue effect");process.exit(1)}})'; then
    echo "ok: spec-rework REJECT emitted enqueue idea effect with feedback"
  else
    echo "FAIL: spec-rework REJECT did not emit expected enqueue effect: $sr_reject_out" >&2
    fail=1
  fi
  if [ "$(echo "$sr_idea_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 0 ]; then
    echo "ok: spec-rework REJECT did not directly write idea store"
  else
    echo "FAIL: spec-rework REJECT wrote directly to idea store: $sr_idea_recs" >&2
    fail=1
  fi

  # --- spec-check APPROVE when spec is in diff → ready-to-deploy ---
  echo "state-flow: spec-check with spec in diff → ready-to-deploy"
  sc_pass_root="$STATE_ROOT/sc-pass"
  sc_repo="$sc_pass_root/repo"
  sc_pr="$sc_pass_root/pr"
  sc_trigger="$sc_pass_root/trigger"
  mkdir -p "$sc_repo" "$sc_pr" "$sc_trigger"
  git init -q --initial-branch=main "$sc_repo"
  git -C "$sc_repo" config user.name "Test"
  git -C "$sc_repo" config user.email "test@example.invalid"
  echo "base" > "$sc_repo/README.md"
  git -C "$sc_repo" add .
  git -C "$sc_repo" commit -q -m "base"
  sc_base="$(git -C "$sc_repo" rev-parse HEAD)"
  git -C "$sc_repo" checkout -q -b "dd/SPEC-004"
  mkdir -p "$sc_repo/docs/specs"
  echo "spec" > "$sc_repo/docs/specs/SPEC-004.md"
  git -C "$sc_repo" add .
  git -C "$sc_repo" commit -q -m "impl"
  sc_spec_commit="$(git -C "$sc_repo" rev-parse HEAD)"
  store_put "$sc_pr" "$(printf '{"id":"pr-SPEC-004","status":"checking","spec_id":"SPEC-004","spec_file":"%s/docs/specs/SPEC-004.md","branch":"dd/SPEC-004","base_commit":"%s"}' "$sc_repo" "$sc_base")"
  sc_script="$sc_pass_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$sc_script" \
    "workspace_repo=$sc_repo" \
    "base_commit=$sc_base" \
    "branch=dd/SPEC-004" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "pr_store_dir=$sc_pr" \
    "trigger_store_dir=$sc_trigger" \
    "pr_id=pr-SPEC-004" \
    "spec_id=SPEC-004" \
    "spec_file=$sc_repo/docs/specs/SPEC-004.md" \
    "repo=$sc_repo" \
    "commit=$sc_spec_commit" \
    "spec_path=docs/specs/SPEC-004.md"
  sc_pass_out="$(bash "$sc_script")"
  # SPEC-002: template emits complete ready-to-deploy; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$sc_pass_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="ready-to-deploy"){console.error("expected complete ready-to-deploy, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: spec-check emitted complete ready-to-deploy when spec is present"
  else
    echo "FAIL: spec-check did not emit complete ready-to-deploy: $sc_pass_out" >&2
    fail=1
  fi

  # --- spec-check REJECT when spec is missing from diff ---
  echo "state-flow: spec-check without spec in diff → rejected + retry trigger"
  sc_fail_root="$STATE_ROOT/sc-fail"
  sc_repo="$sc_fail_root/repo"
  sc_pr="$sc_fail_root/pr"
  sc_trigger="$sc_fail_root/trigger"
  mkdir -p "$sc_repo" "$sc_pr" "$sc_trigger"
  git init -q --initial-branch=main "$sc_repo"
  git -C "$sc_repo" config user.name "Test"
  git -C "$sc_repo" config user.email "test@example.invalid"
  echo "base" > "$sc_repo/README.md"
  git -C "$sc_repo" add .
  git -C "$sc_repo" commit -q -m "base"
  sc_base="$(git -C "$sc_repo" rev-parse HEAD)"
  git -C "$sc_repo" checkout -q -b "dd/SPEC-005"
  echo "code" > "$sc_repo/code.js"
  git -C "$sc_repo" add .
  git -C "$sc_repo" commit -q -m "impl"
  store_put "$sc_pr" "$(printf '{"id":"pr-SPEC-005","status":"checking","spec_id":"SPEC-005","spec_file":"%s/docs/specs/SPEC-005.md","branch":"dd/SPEC-005","base_commit":"%s"}' "$sc_repo" "$sc_base")"
  sc_script="$sc_fail_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$sc_script" \
    "workspace_repo=$sc_repo" \
    "base_commit=$sc_base" \
    "branch=dd/SPEC-005" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "pr_store_dir=$sc_pr" \
    "trigger_store_dir=$sc_trigger" \
    "pr_id=pr-SPEC-005" \
    "spec_id=SPEC-005" \
    "spec_file=$sc_repo/docs/specs/SPEC-005.md"
  sc_fail_out="$(bash "$sc_script")"
  sc_trigger_recs="$(store_by_status "$sc_trigger" open)"
  # SPEC-002: template emits complete rejected; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$sc_fail_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="rejected"){console.error("expected complete rejected, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: spec-check emitted complete rejected when spec is missing"
  else
    echo "FAIL: spec-check did not emit complete rejected: $sc_fail_out" >&2
    fail=1
  fi
  if echo "$sc_fail_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="enqueue"&&x.queue==="trigger");if(!a||a.task.status!=="open"||!a.task.feedback.includes("REJECT")){console.error("bad enqueue effect");process.exit(1)}})'; then
    echo "ok: spec-check emitted enqueue trigger effect when spec is missing"
  else
    echo "FAIL: spec-check did not emit expected enqueue effect: $sc_fail_out" >&2
    fail=1
  fi
  if [ "$(echo "$sc_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 0 ]; then
    echo "ok: spec-check did not directly write trigger store when spec is missing"
  else
    echo "FAIL: spec-check wrote directly to trigger store: $sc_trigger_recs" >&2
    fail=1
  fi

  # --- deploy-verify success: tests pass → ready-to-merge ---
  echo "state-flow: deploy-verify success → ready-to-merge"
  dv_pass_root="$STATE_ROOT/dv-pass"
  dv_repo="$dv_pass_root/repo"
  dv_pr="$dv_pass_root/pr"
  dv_trigger="$dv_pass_root/trigger"
  dv_log="$dv_pass_root/logs"
  mkdir -p "$dv_repo" "$dv_pr" "$dv_trigger" "$dv_log"
  git init -q --initial-branch=main "$dv_repo"
  git -C "$dv_repo" config user.name "Test"
  git -C "$dv_repo" config user.email "test@example.invalid"
  echo "base" > "$dv_repo/README.md"
  git -C "$dv_repo" add .
  git -C "$dv_repo" commit -q -m "base"
  git -C "$dv_repo" checkout -q -b "dd/SPEC-006"
  echo "feature" > "$dv_repo/feature.js"
  git -C "$dv_repo" add .
  git -C "$dv_repo" commit -q -m "impl"
  store_put "$dv_pr" "$(printf '{"id":"pr-SPEC-006","status":"verifying","spec_id":"SPEC-006","spec_file":"/tmp/SPEC-006.md","branch":"dd/SPEC-006","base_commit":"%s"}' "$(git -C "$dv_repo" rev-parse HEAD)")"
  dv_script="$dv_pass_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$dv_script" \
    "workspace_repo=$dv_repo" \
    "accept_cmd=true" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "trigger_store_dir=$dv_trigger" \
    "pr_store_dir=$dv_pr" \
    "deploy_log_dir=$dv_log" \
    "pr_id=pr-SPEC-006" \
    "spec_id=SPEC-006" \
    "spec_file=/tmp/SPEC-006.md" \
    "branch=dd/SPEC-006" \
    "base_commit=$(git -C "$dv_repo" rev-parse HEAD)"
  dv_pass_out="$(bash "$dv_script")"
  # SPEC-002: template emits complete ready-to-merge; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$dv_pass_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="ready-to-merge"){console.error("expected complete ready-to-merge, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: deploy-verify emitted complete ready-to-merge on success"
  else
    echo "FAIL: deploy-verify did not emit complete ready-to-merge: $dv_pass_out" >&2
    fail=1
  fi

  # --- deploy-verify failure: tests fail → verify_failed + retry trigger ---
  echo "state-flow: deploy-verify failure → verify_failed + retry"
  dv_fail_root="$STATE_ROOT/dv-fail"
  dv_repo="$dv_fail_root/repo"
  dv_pr="$dv_fail_root/pr"
  dv_trigger="$dv_fail_root/trigger"
  dv_log="$dv_fail_root/logs"
  mkdir -p "$dv_repo" "$dv_pr" "$dv_trigger" "$dv_log"
  git init -q --initial-branch=main "$dv_repo"
  git -C "$dv_repo" config user.name "Test"
  git -C "$dv_repo" config user.email "test@example.invalid"
  echo "base" > "$dv_repo/README.md"
  git -C "$dv_repo" add .
  git -C "$dv_repo" commit -q -m "base"
  git -C "$dv_repo" checkout -q -b "dd/SPEC-007"
  echo "feature" > "$dv_repo/feature.js"
  git -C "$dv_repo" add .
  git -C "$dv_repo" commit -q -m "impl"
  store_put "$dv_pr" "$(printf '{"id":"pr-SPEC-007","status":"verifying","spec_id":"SPEC-007","spec_file":"/tmp/SPEC-007.md","branch":"dd/SPEC-007","base_commit":"%s"}' "$(git -C "$dv_repo" rev-parse HEAD)")"
  dv_script="$dv_fail_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$dv_script" \
    "workspace_repo=$dv_repo" \
    "accept_cmd=false" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "trigger_store_dir=$dv_trigger" \
    "pr_store_dir=$dv_pr" \
    "deploy_log_dir=$dv_log" \
    "pr_id=pr-SPEC-007" \
    "spec_id=SPEC-007" \
    "spec_file=/tmp/SPEC-007.md" \
    "branch=dd/SPEC-007" \
    "base_commit=$(git -C "$dv_repo" rev-parse HEAD)"
  dv_fail_out="$(bash "$dv_script")"
  dv_trigger_recs="$(store_by_status "$dv_trigger" open)"
  # SPEC-002: template emits complete verify_failed; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$dv_fail_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="verify_failed"){console.error("expected complete verify_failed, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: deploy-verify emitted complete verify_failed on failure"
  else
    echo "FAIL: deploy-verify did not emit complete verify_failed: $dv_fail_out" >&2
    fail=1
  fi
  if echo "$dv_fail_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="enqueue"&&x.queue==="trigger");if(!a||a.task.status!=="open"||!a.task.feedback.includes("Deploy-verify acceptance FAILED")){console.error("bad enqueue effect");process.exit(1)}})'; then
    echo "ok: deploy-verify emitted enqueue trigger effect on failure"
  else
    echo "FAIL: deploy-verify did not emit expected enqueue effect: $dv_fail_out" >&2
    fail=1
  fi
  if [ "$(echo "$dv_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 0 ]; then
    echo "ok: deploy-verify did not directly write trigger store on failure"
  else
    echo "FAIL: deploy-verify wrote directly to trigger store: $dv_trigger_recs" >&2
    fail=1
  fi

  # --- merger success: merge + test pass → merged ---
  echo "state-flow: merger success → merged"
  mg_pass_root="$STATE_ROOT/mg-pass"
  mg_repo="$mg_pass_root/repo"
  mg_pr="$mg_pass_root/pr"
  mg_trigger="$mg_pass_root/trigger"
  mg_log="$mg_pass_root/logs"
  mkdir -p "$mg_repo" "$mg_pr" "$mg_trigger" "$mg_log"
  git init -q --initial-branch=main "$mg_repo"
  git -C "$mg_repo" config user.name "Test"
  git -C "$mg_repo" config user.email "test@example.invalid"
  echo "base" > "$mg_repo/README.md"
  git -C "$mg_repo" add .
  git -C "$mg_repo" commit -q -m "base"
  mg_base="$(git -C "$mg_repo" rev-parse HEAD)"
  git -C "$mg_repo" checkout -q -b "dd/SPEC-008"
  echo "feature" > "$mg_repo/feature.js"
  git -C "$mg_repo" add .
  git -C "$mg_repo" commit -q -m "impl"
  git -C "$mg_repo" checkout -q main
  store_put "$mg_pr" "$(printf '{"id":"pr-SPEC-008","status":"merging","spec_id":"SPEC-008","spec_file":"/tmp/SPEC-008.md","branch":"dd/SPEC-008","base_commit":"%s"}' "$mg_base")"
  mg_script="$mg_pass_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/merger/templates/merger.md" "$mg_script" \
    "workspace_repo=$mg_repo" \
    "base_branch=main" \
    "accept_cmd=true" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "trigger_store_dir=$mg_trigger" \
    "pr_store_dir=$mg_pr" \
    "merge_log_dir=$mg_log" \
    "pr_id=pr-SPEC-008" \
    "spec_id=SPEC-008" \
    "spec_file=/tmp/SPEC-008.md" \
    "branch=dd/SPEC-008" \
    "base_commit=$mg_base"
  mg_pass_out="$(bash "$mg_script")"
  # SPEC-002: template emits complete merged; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$mg_pass_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="merged"){console.error("expected complete merged, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: merger emitted complete merged on success"
  else
    echo "FAIL: merger did not emit complete merged: $mg_pass_out" >&2
    fail=1
  fi
  # Verify the merge actually happened on main.
  if git -C "$mg_repo" log --oneline main | head -1 | grep -q "merge(bootstrap)"; then
    echo "ok: merger commit is on main branch"
  else
    echo "FAIL: merger commit not found on main branch" >&2
    fail=1
  fi

  # --- merger conflict: merge fails → merge_conflict + retry trigger ---
  echo "state-flow: merger conflict → merge_conflict + retry"
  mg_conflict_root="$STATE_ROOT/mg-conflict"
  mg_repo="$mg_conflict_root/repo"
  mg_pr="$mg_conflict_root/pr"
  mg_trigger="$mg_conflict_root/trigger"
  mg_log="$mg_conflict_root/logs"
  mkdir -p "$mg_repo" "$mg_pr" "$mg_trigger" "$mg_log"
  git init -q --initial-branch=main "$mg_repo"
  git -C "$mg_repo" config user.name "Test"
  git -C "$mg_repo" config user.email "test@example.invalid"
  echo "base" > "$mg_repo/README.md"
  git -C "$mg_repo" add .
  git -C "$mg_repo" commit -q -m "base"
  mg_base="$(git -C "$mg_repo" rev-parse HEAD)"
  # Create conflicting changes on main and the branch.
  git -C "$mg_repo" checkout -q -b "dd/SPEC-009"
  echo "branch version" > "$mg_repo/conflict.txt"
  git -C "$mg_repo" add .
  git -C "$mg_repo" commit -q -m "branch change"
  git -C "$mg_repo" checkout -q main
  echo "main version" > "$mg_repo/conflict.txt"
  git -C "$mg_repo" add .
  git -C "$mg_repo" commit -q -m "main change"
  store_put "$mg_pr" "$(printf '{"id":"pr-SPEC-009","status":"merging","spec_id":"SPEC-009","spec_file":"/tmp/SPEC-009.md","branch":"dd/SPEC-009","base_commit":"%s"}' "$mg_base")"
  mg_script="$mg_conflict_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/merger/templates/merger.md" "$mg_script" \
    "workspace_repo=$mg_repo" \
    "base_branch=main" \
    "accept_cmd=true" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "trigger_store_dir=$mg_trigger" \
    "pr_store_dir=$mg_pr" \
    "merge_log_dir=$mg_log" \
    "pr_id=pr-SPEC-009" \
    "spec_id=SPEC-009" \
    "spec_file=/tmp/SPEC-009.md" \
    "branch=dd/SPEC-009" \
    "base_commit=$mg_base"
  mg_conflict_out="$(bash "$mg_script")"
  mg_trigger_recs="$(store_by_status "$mg_trigger" open)"
  # SPEC-002: template emits complete merge_conflict; engine applies it via
  # completeRecord. The template no longer advances the PR record directly.
  if echo "$mg_conflict_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="complete");if(!a||a.status!=="merge_conflict"){console.error("expected complete merge_conflict, got "+(a&&a.status));process.exit(1)}})'; then
    echo "ok: merger emitted complete merge_conflict on conflict"
  else
    echo "FAIL: merger did not emit complete merge_conflict: $mg_conflict_out" >&2
    fail=1
  fi
  if echo "$mg_conflict_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const a=e.effects.find(x=>x.op==="enqueue"&&x.queue==="trigger");if(!a||a.task.status!=="open"||!a.task.feedback.includes("Merge phase FAILED")){console.error("bad enqueue effect");process.exit(1)}})'; then
    echo "ok: merger emitted enqueue trigger effect on conflict"
  else
    echo "FAIL: merger did not emit expected enqueue effect: $mg_conflict_out" >&2
    fail=1
  fi
  if [ "$(echo "$mg_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 0 ]; then
    echo "ok: merger did not directly write trigger store on conflict"
  else
    echo "FAIL: merger wrote directly to trigger store: $mg_trigger_recs" >&2
    fail=1
  fi
fi

# --- enqueue-routes integration tests (SPEC-001-b0-plugin-enqueue-routes) ---
echo "running enqueue-routes integration tests"
if bash "$ROOT/tests/enqueue-routes.test.sh"; then
  echo "ok: enqueue-routes tests passed"
else
  echo "FAIL: enqueue-routes tests failed" >&2
  fail=1
fi

# --- complete-effect integration tests (SPEC-002-b0-plugin-complete-effect) ---
echo "running complete-effect integration tests"
if bash "$ROOT/tests/complete-effect.test.sh"; then
  echo "ok: complete-effect tests passed"
else
  echo "FAIL: complete-effect tests failed" >&2
  fail=1
fi

# --- pipeline-contracts static tests (SPEC-003-b2-pipeline-contracts) ---
echo "running pipeline-contracts static tests"
if bash "$ROOT/tests/pipeline-contracts.test.sh"; then
  echo "ok: pipeline-contracts tests passed"
else
  echo "FAIL: pipeline-contracts tests failed" >&2
  fail=1
fi

# --- pointer-records static tests (SPEC-005-b3-pointer-records) ---
echo "running pointer-records static tests"
if bash "$ROOT/tests/pointer-records.test.sh"; then
  echo "ok: pointer-records tests passed"
else
  echo "FAIL: pointer-records tests failed" >&2
  fail=1
fi

# --- pointer-consumption tests (SPEC-006-b3-pointer-consumption-inject-tool) ---
echo "running pointer-consumption tests"
if bash "$ROOT/tests/pointer-consumption.test.sh"; then
  echo "ok: pointer-consumption tests passed"
else
  echo "FAIL: pointer-consumption tests failed" >&2
  fail=1
fi

# --- loop-events wiring tests (SPEC-004-b1-loop-events-wiring) ---
echo "running loop-events wiring tests"
if bash "$ROOT/tests/loop-events-wiring.test.sh"; then
  echo "ok: loop-events wiring tests passed"
else
  echo "FAIL: loop-events wiring tests failed" >&2
  fail=1
fi

# --- grep assertion: no direct put calls remain in migrated templates ---
put_count="$(grep -rn 'node.*loop_store_cli.*put\|"$loop_store_cli".*put' "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$ROOT/workflows/spec-gen/merger/templates/merger.md" 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$put_count" -eq 0 ]; then
  echo "ok: no direct put calls in migrated templates"
else
  echo "FAIL: $put_count direct put call(s) remain in migrated templates" >&2
  fail=1
fi

# --- grep assertion: no direct update calls remain in spec-check/deploy-verify/merger ---
update_count="$(grep -rn 'node.*loop_store_cli.*update\|"$loop_store_cli".*update' "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$ROOT/workflows/spec-gen/merger/templates/merger.md" 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$update_count" -eq 0 ]; then
  echo "ok: no direct update calls in spec-check/deploy-verify/merger templates"
else
  echo "FAIL: $update_count direct update call(s) remain in spec-check/deploy-verify/merger templates" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then echo "acceptance FAILED"; exit 1; fi
echo "acceptance PASSED"