#!/usr/bin/env bash
# Acceptance checks for loop-engine-bootstrap-plugin.
# These checks are deterministic and do not call LLMs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check(){ if [ ! -e "$ROOT/$1" ]; then echo "MISSING: $1" >&2; fail=1; else echo "ok: $1"; fi; }

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
check "bin/bootstrap-loop.sh"
check "scripts/render-template.mjs"

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
  export BOOT_WORK_MODEL="test-model"
  export BOOT_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_WORK_MODEL="test-model"
  export DD_WORK_RUNTIME="bash"
  export DD_REVIEW_MODEL="test-model"
  export DD_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_ACCEPT_CMD="npm test"
  export BOOT_MAX_PASSES="8"
  export LOOP_STORE_CLI="${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}"
  export WORKSPACE_BASE_BRANCH="main"

  mkdir -p "$REF_LIBRARY_DIR"
  echo "# Reference library index" > "$REF_LIBRARY_INDEX"

  RENDERED_FLEET="$RUN_ROOT/fleet.yaml"
  node "$ROOT/scripts/render-template.mjs" "$ROOT/workflows/fleet.yaml.tpl" "$RENDERED_FLEET"
  echo "ok: fleet.yaml rendered"

  export ENGINE_DIST_FLEET RENDERED_FLEET PLUGIN_ROOT

  # Validate the rendered fleet manifest against loop-engine's schema.
  schema_check_js="$(mktemp --suffix=.mjs)"
  cat > "$schema_check_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
try {
  const manifest = loadFleetManifest(process.env.RENDERED_FLEET);
  const labels = manifest.pipelines.map((p) => p.label).sort();
  const expected = ["deploy", "draft", "review", "rework", "spec-check", "spec-review", "spec-rework", "work"];
  if (JSON.stringify(labels) !== JSON.stringify(expected)) {
    console.error("unexpected pipeline labels: " + labels.join(","));
    process.exit(1);
  }
  console.log("ok: fleet manifest schema valid");
} catch (e) {
  console.error("fleet manifest invalid: " + e.message);
  process.exit(1);
}
NODE
  node "$schema_check_js" || fail=1
  rm -f "$schema_check_js"

  # INV-2: Impl Loop four pipelines must point at dev-dispatch, not local copies.
  impl_check_js="$(mktemp --suffix=.mjs)"
  cat > "$impl_check_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
const manifest = loadFleetManifest(process.env.RENDERED_FLEET);
const impl = ["work", "review", "rework", "deploy"];
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
if (ok) console.log("ok: Impl Loop config_dirs point outside bootstrap plugin");
else process.exit(1);
NODE
  node "$impl_check_js" || fail=1
  rm -f "$impl_check_js"

  # INV-1: bin/ contains only the bootstrap-loop driver, no inter-loop glue scripts.
  bin_scripts=($(find "$ROOT/bin" -maxdepth 1 -type f ! -name '.gitkeep'))
  if [ "${#bin_scripts[@]}" -eq 1 ] && [ "$(basename "${bin_scripts[0]}")" = "bootstrap-loop.sh" ]; then
    echo "ok: bin/ has only bootstrap-loop.sh"
  else
    echo "FAIL: bin/ contains unexpected scripts: ${bin_scripts[*]}" >&2
    fail=1
  fi

  # INV-3: deploy must claim from a status guarded by the spec-check pipeline.
  deploy_claim_js="$(mktemp --suffix=.mjs)"
  cat > "$deploy_claim_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
const manifest = loadFleetManifest(process.env.RENDERED_FLEET);
const deploy = manifest.pipelines.find((p) => p.label === "deploy");
const specCheck = manifest.pipelines.find((p) => p.label === "spec-check");
let ok = true;
if (!deploy) { console.error("missing deploy pipeline"); ok = false; }
if (!specCheck) { console.error("missing spec-check pipeline"); ok = false; }
if (deploy && deploy.claim?.from !== "ready-to-deploy") {
  console.error("FAIL: deploy claims from " + deploy.claim.from + ", expected ready-to-deploy");
  ok = false;
}
if (specCheck && specCheck.claim?.from !== "approved") {
  console.error("FAIL: spec-check claims from " + specCheck.claim.from + ", expected approved");
  ok = false;
}
if (specCheck && specCheck.claim?.to !== "checking") {
  console.error("FAIL: spec-check transitions to " + specCheck.claim.to + ", expected checking");
  ok = false;
}
if (ok) console.log("ok: deploy guarded by spec-check pipeline");
else process.exit(1);
NODE
  node "$deploy_claim_js" || fail=1
  rm -f "$deploy_claim_js"

  # Deterministic full-chain store state-flow tests (no LLM calls).
  # Use the engine's Store CLI and template fill to drive the pure-bash nodes.
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
  store_list() { node "$LOOP_STORE_CLI" "$1" list; }
  store_by_status() { node "$LOOP_STORE_CLI" "$1" list "$2"; }

  # --- spec-rework APPROVE produces an open trigger record ---
  echo "state-flow: spec-rework APPROVE → trigger"
  sr_approve_root="$STATE_ROOT/sr-approve"
  sr_idea="$sr_approve_root/idea"
  sr_trigger="$sr_approve_root/trigger"
  sr_verdict="$sr_approve_root/spec-verdict"
  mkdir -p "$sr_idea" "$sr_trigger" "$sr_verdict"
  store_put "$sr_verdict" "$(printf '{"id":"verdict-SPEC-002","status":"decided","spec_id":"SPEC-002","spec_file":"/tmp/SPEC-002.md","verdict":"APPROVE","feedback":"ok","feedback_file":""}')"
  sr_script="$sr_approve_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$sr_script" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "idea_store_dir=$sr_idea" \
    "trigger_store_dir=$sr_trigger" \
    "spec_verdict_id=verdict-SPEC-002" \
    "spec_id=SPEC-002" \
    "spec_file=/tmp/SPEC-002.md" \
    "verdict=APPROVE" \
    "feedback=ok" \
    "feedback_file="
  bash "$sr_script" >/dev/null
  sr_trigger_recs="$(store_by_status "$sr_trigger" open)"
  if [ "$(echo "$sr_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 1 ]; then
    echo "ok: spec-rework APPROVE enqueued one open trigger record"
  else
    echo "FAIL: spec-rework APPROVE did not enqueue exactly one open trigger record: $sr_trigger_recs" >&2
    fail=1
  fi

  # --- spec-rework REJECT produces an open idea record with feedback ---
  echo "state-flow: spec-rework REJECT → idea"
  sr_reject_root="$STATE_ROOT/sr-reject"
  sr_idea="$sr_reject_root/idea"
  sr_trigger="$sr_reject_root/trigger"
  sr_verdict="$sr_reject_root/spec-verdict"
  mkdir -p "$sr_idea" "$sr_trigger" "$sr_verdict"
  store_put "$sr_verdict" "$(printf '{"id":"verdict-SPEC-003","status":"decided","spec_id":"SPEC-003","spec_file":"/tmp/SPEC-003.md","verdict":"REJECT","feedback":"too vague","feedback_file":""}')"
  sr_script="$sr_reject_root/run.sh"
  render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$sr_script" \
    "loop_store_cli=$LOOP_STORE_CLI" \
    "idea_store_dir=$sr_idea" \
    "trigger_store_dir=$sr_trigger" \
    "spec_verdict_id=verdict-SPEC-003" \
    "spec_id=SPEC-003" \
    "spec_file=/tmp/SPEC-003.md" \
    "verdict=REJECT" \
    "feedback=too vague" \
    "feedback_file="
  bash "$sr_script" >/dev/null
  sr_idea_recs="$(store_by_status "$sr_idea" open)"
  if echo "$sr_idea_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);if(a.length!==1){console.error("expected 1, got "+a.length);process.exit(1)}const r=a[0];if(r.status!=="open"||!r.feedback.includes("REJECT")){console.error("bad record");process.exit(1)}})'; then
    echo "ok: spec-rework REJECT enqueued one open idea record with feedback"
  else
    echo "FAIL: spec-rework REJECT did not enqueue the expected idea record: $sr_idea_recs" >&2
    fail=1
  fi

  # --- spec-check APPROVE when spec is in diff ---
  echo "state-flow: spec-check with spec in diff → ready-to-deploy"
  sc_pass_root="$STATE_ROOT/sc-pass"
  sc_repo="$sc_pass_root/repo"
  sc_pr="$sc_pass_root/pr"
  sc_trigger="$sc_pass_root/trigger"
  mkdir -p "$sc_repo" "$sc_pr" "$sc_trigger"
  git init -q "$sc_repo"
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
    "spec_file=$sc_repo/docs/specs/SPEC-004.md"
  bash "$sc_script" >/dev/null
  sc_pr_rec="$(store_get "$sc_pr" pr-SPEC-004)"
  if echo "$sc_pr_rec" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const r=JSON.parse(d);if(r.status!=="ready-to-deploy"){console.error("expected ready-to-deploy, got "+r.status);process.exit(1)}})'; then
    echo "ok: spec-check advanced PR to ready-to-deploy when spec is present"
  else
    echo "FAIL: spec-check did not advance PR to ready-to-deploy: $sc_pr_rec" >&2
    fail=1
  fi

  # --- spec-check REJECT when spec is missing from diff ---
  echo "state-flow: spec-check without spec in diff → rejected + retry trigger"
  sc_fail_root="$STATE_ROOT/sc-fail"
  sc_repo="$sc_fail_root/repo"
  sc_pr="$sc_fail_root/pr"
  sc_trigger="$sc_fail_root/trigger"
  mkdir -p "$sc_repo" "$sc_pr" "$sc_trigger"
  git init -q "$sc_repo"
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
  bash "$sc_script" >/dev/null
  sc_pr_rec="$(store_get "$sc_pr" pr-SPEC-005)"
  sc_trigger_recs="$(store_by_status "$sc_trigger" open)"
  if echo "$sc_pr_rec" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const r=JSON.parse(d);if(r.status!=="rejected"){console.error("expected rejected, got "+r.status);process.exit(1)}})'; then
    echo "ok: spec-check rejected PR when spec is missing"
  else
    echo "FAIL: spec-check did not reject PR when spec is missing: $sc_pr_rec" >&2
    fail=1
  fi
  if [ "$(echo "$sc_trigger_recs" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const a=JSON.parse(d);console.log(a.length)})')" -eq 1 ]; then
    echo "ok: spec-check enqueued a retry trigger when spec is missing"
  else
    echo "FAIL: spec-check did not enqueue exactly one retry trigger: $sc_trigger_recs" >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then echo "acceptance FAILED"; exit 1; fi
echo "acceptance PASSED"
