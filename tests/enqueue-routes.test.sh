#!/usr/bin/env bash
# Integration tests for SPEC-001-b0-plugin-enqueue-routes.
# Verifies the 5 migrated workflow templates emit enqueue effects instead of
# directly calling `node $loop_store_cli $store_dir put`, and that the
# transition-period update calls (spec-check/deploy-verify/merger) remain.
#
# Each scenario renders a template with fixture store dirs, runs it via bash,
# and asserts on the emitted JSON envelope. The store dirs are checked to be
# untouched (no direct put).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
ENGINE_DIST_TEMPLATE="$ENGINE_ROOT/dist/template.js"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}"

if [ ! -f "$ENGINE_DIST_TEMPLATE" ]; then
  echo "SKIP: Loop Engine dist missing; build it to run enqueue-routes tests" >&2
  exit 0
fi
if [ ! -f "$LOOP_STORE_CLI" ]; then
  echo "SKIP: store-cli missing at $LOOP_STORE_CLI" >&2
  exit 0
fi

WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

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

store_count_open() {
  node "$LOOP_STORE_CLI" "$1" list open 2>/dev/null | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(d).length)}catch{console.log(0)}})'
}

# Assert the first stdin JSON line satisfies a node predicate body (exits 0 on pass).
# The predicate body receives the parsed object as `e` and must call process.exit(1) on failure.
assert_json() {
  local label="$1"
  local pred="$2"
  if echo "$3" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const e=JSON.parse(d);${pred}})"; then
    echo "ok: $label"
  else
    echo "FAIL: $label" >&2
    echo "  output: $3" >&2
    fail=1
  fi
}

# ---------------------------------------------------------------------------
# TC-01: P-a1 — spec-rework APPROVE emits enqueue trigger effect, no direct put
# ---------------------------------------------------------------------------
echo "TC-01: spec-rework APPROVE → enqueue trigger"
tc1="$WORK_ROOT/tc1"
mkdir -p "$tc1/idea" "$tc1/trigger"
tc1_script="$tc1/run.sh"
render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$tc1_script" \
  "idea_store_dir=$tc1/idea" \
  "trigger_store_dir=$tc1/trigger" \
  "spec_verdict_id=verdict-001" \
  "spec_id=SPEC-001" \
  "spec_file=/tmp/SPEC-001.md" \
  "verdict=APPROVE" \
  "feedback=ok" \
  "feedback_file="
tc1_out="$(bash "$tc1_script")"
assert_json "TC-01 effects[0] is enqueue trigger" \
  "const a=e.effects[0];if(!(a&&a.op==='enqueue'&&a.queue==='trigger'&&a.task.id==='SPEC-001'&&a.task.status==='open'&&a.task.spec_file==='/tmp/SPEC-001.md'&&a.task.feedback==='(none)'))process.exit(1)" \
  "$tc1_out"
[ "$(store_count_open "$tc1/trigger")" -eq 0 ] || { echo "FAIL: TC-01 trigger store written directly" >&2; fail=1; }
[ "$(store_count_open "$tc1/idea")" -eq 0 ] || { echo "FAIL: TC-01 idea store written directly" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-02: P-a2 — spec-rework REJECT emits enqueue idea effect, no direct put
# ---------------------------------------------------------------------------
echo "TC-02: spec-rework REJECT → enqueue idea"
tc2="$WORK_ROOT/tc2"
mkdir -p "$tc2/idea" "$tc2/trigger"
tc2_script="$tc2/run.sh"
render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$tc2_script" \
  "idea_store_dir=$tc2/idea" \
  "trigger_store_dir=$tc2/trigger" \
  "spec_verdict_id=verdict-002" \
  "spec_id=SPEC-002" \
  "spec_file=/tmp/SPEC-002.md" \
  "verdict=REJECT" \
  "feedback=too-vague" \
  "feedback_file=/tmp/fb.md"
tc2_out="$(bash "$tc2_script")"
assert_json "TC-02 effects[0] is enqueue idea with REJECT feedback" \
  "const a=e.effects[0];if(!(a&&a.op==='enqueue'&&a.queue==='idea'&&a.task.status==='open'&&a.task.spec_file==='/tmp/SPEC-002.md'&&a.task.feedback_file==='/tmp/fb.md'&&a.task.feedback.includes('Spec review REJECT on a previous attempt')&&a.task.feedback.endsWith('Summary: too-vague')))process.exit(1)" \
  "$tc2_out"
[ "$(store_count_open "$tc2/idea")" -eq 0 ] || { echo "FAIL: TC-02 idea store written directly" >&2; fail=1; }
[ "$(store_count_open "$tc2/trigger")" -eq 0 ] || { echo "FAIL: TC-02 trigger store written directly" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-03: P-a3 — spec-check FAIL (spec missing) emits enqueue trigger, keeps update
# ---------------------------------------------------------------------------
echo "TC-03: spec-check FAIL → enqueue trigger + update retained"
tc3="$WORK_ROOT/tc3"
tc3_repo="$tc3/repo"; tc3_pr="$tc3/pr"; tc3_trigger="$tc3/trigger"
mkdir -p "$tc3_repo" "$tc3_pr" "$tc3_trigger"
git init -q --initial-branch=main "$tc3_repo"
git -C "$tc3_repo" config user.name "Test"
git -C "$tc3_repo" config user.email "test@example.invalid"
echo "base" > "$tc3_repo/README.md"
git -C "$tc3_repo" add .
git -C "$tc3_repo" commit -q -m "base"
tc3_base="$(git -C "$tc3_repo" rev-parse HEAD)"
git -C "$tc3_repo" checkout -q -b "dd/SPEC-003"
echo "code" > "$tc3_repo/code.js"
git -C "$tc3_repo" add .
git -C "$tc3_repo" commit -q -m "impl"
node "$LOOP_STORE_CLI" "$tc3_pr" put "$(printf '{"id":"pr-SPEC-003","status":"checking","spec_id":"SPEC-003","spec_file":"%s/docs/specs/SPEC-003.md","branch":"dd/SPEC-003","base_commit":"%s"}' "$tc3_repo" "$tc3_base")"
tc3_script="$tc3/run.sh"
render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$tc3_script" \
  "workspace_repo=$tc3_repo" \
  "base_commit=$tc3_base" \
  "branch=dd/SPEC-003" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "pr_store_dir=$tc3_pr" \
  "trigger_store_dir=$tc3_trigger" \
  "pr_id=pr-SPEC-003" \
  "spec_id=SPEC-003" \
  "spec_file=$tc3_repo/docs/specs/SPEC-003.md"
tc3_out="$(bash "$tc3_script")"
assert_json "TC-03 emits enqueue trigger effect" \
  "const a=e.effects.find(x=>x.op==='enqueue'&&x.queue==='trigger');if(!(a&&a.task.status==='open'&&a.task.feedback.includes('REJECT: the approved spec file is missing')))process.exit(1)" \
  "$tc3_out"
[ "$(store_count_open "$tc3_trigger")" -eq 0 ] || { echo "FAIL: TC-03 trigger store written directly" >&2; fail=1; }
# INV-3: update call retained — PR advanced to rejected.
tc3_pr_rec="$(node "$LOOP_STORE_CLI" "$tc3_pr" get pr-SPEC-003)"
assert_json "TC-03 PR marked rejected (update retained)" \
  "if(e.status!=='rejected')process.exit(1)" \
  "$tc3_pr_rec"

# ---------------------------------------------------------------------------
# TC-04: P-a4 — deploy-verify failure emits enqueue trigger, no direct put
# ---------------------------------------------------------------------------
echo "TC-04: deploy-verify failure → enqueue trigger"
tc4="$WORK_ROOT/tc4"
tc4_repo="$tc4/repo"; tc4_pr="$tc4/pr"; tc4_trigger="$tc4/trigger"; tc4_log="$tc4/logs"
mkdir -p "$tc4_repo" "$tc4_pr" "$tc4_trigger" "$tc4_log"
git init -q --initial-branch=main "$tc4_repo"
git -C "$tc4_repo" config user.name "Test"
git -C "$tc4_repo" config user.email "test@example.invalid"
echo "base" > "$tc4_repo/README.md"
git -C "$tc4_repo" add .
git -C "$tc4_repo" commit -q -m "base"
git -C "$tc4_repo" checkout -q -b "dd/SPEC-004"
echo "feature" > "$tc4_repo/feature.js"
git -C "$tc4_repo" add .
git -C "$tc4_repo" commit -q -m "impl"
tc4_head="$(git -C "$tc4_repo" rev-parse HEAD)"
node "$LOOP_STORE_CLI" "$tc4_pr" put "$(printf '{"id":"pr-SPEC-004","status":"verifying","spec_id":"SPEC-004","spec_file":"/tmp/SPEC-004.md","branch":"dd/SPEC-004","base_commit":"%s"}' "$tc4_head")"
tc4_script="$tc4/run.sh"
render_template "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$tc4_script" \
  "workspace_repo=$tc4_repo" \
  "accept_cmd=false" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc4_trigger" \
  "pr_store_dir=$tc4_pr" \
  "deploy_log_dir=$tc4_log" \
  "pr_id=pr-SPEC-004" \
  "spec_id=SPEC-004" \
  "spec_file=/tmp/SPEC-004.md" \
  "branch=dd/SPEC-004" \
  "base_commit=$tc4_head"
tc4_out="$(bash "$tc4_script")"
assert_json "TC-04 emits enqueue trigger effect" \
  "const a=e.effects.find(x=>x.op==='enqueue'&&x.queue==='trigger');if(!(a&&a.task.status==='open'&&a.task.feedback.includes('Deploy-verify acceptance FAILED')))process.exit(1)" \
  "$tc4_out"
[ "$(store_count_open "$tc4_trigger")" -eq 0 ] || { echo "FAIL: TC-04 trigger store written directly" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-05: P-a5 — merger failure emits enqueue trigger, no direct put
# ---------------------------------------------------------------------------
echo "TC-05: merger failure → enqueue trigger"
tc5="$WORK_ROOT/tc5"
tc5_repo="$tc5/repo"; tc5_pr="$tc5/pr"; tc5_trigger="$tc5/trigger"; tc5_log="$tc5/logs"
mkdir -p "$tc5_repo" "$tc5_pr" "$tc5_trigger" "$tc5_log"
git init -q --initial-branch=main "$tc5_repo"
git -C "$tc5_repo" config user.name "Test"
git -C "$tc5_repo" config user.email "test@example.invalid"
echo "base" > "$tc5_repo/README.md"
git -C "$tc5_repo" add .
git -C "$tc5_repo" commit -q -m "base"
tc5_base="$(git -C "$tc5_repo" rev-parse HEAD)"
git -C "$tc5_repo" checkout -q -b "dd/SPEC-005"
echo "branch version" > "$tc5_repo/conflict.txt"
git -C "$tc5_repo" add .
git -C "$tc5_repo" commit -q -m "branch change"
git -C "$tc5_repo" checkout -q main
echo "main version" > "$tc5_repo/conflict.txt"
git -C "$tc5_repo" add .
git -C "$tc5_repo" commit -q -m "main change"
node "$LOOP_STORE_CLI" "$tc5_pr" put "$(printf '{"id":"pr-SPEC-005","status":"merging","spec_id":"SPEC-005","spec_file":"/tmp/SPEC-005.md","branch":"dd/SPEC-005","base_commit":"%s"}' "$tc5_base")"
tc5_script="$tc5/run.sh"
render_template "$ROOT/workflows/spec-gen/merger/templates/merger.md" "$tc5_script" \
  "workspace_repo=$tc5_repo" \
  "base_branch=main" \
  "accept_cmd=true" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc5_trigger" \
  "pr_store_dir=$tc5_pr" \
  "merge_log_dir=$tc5_log" \
  "pr_id=pr-SPEC-005" \
  "spec_id=SPEC-005" \
  "spec_file=/tmp/SPEC-005.md" \
  "branch=dd/SPEC-005" \
  "base_commit=$tc5_base"
tc5_out="$(bash "$tc5_script")"
assert_json "TC-05 emits enqueue trigger effect" \
  "const a=e.effects.find(x=>x.op==='enqueue'&&x.queue==='trigger');if(!(a&&a.task.status==='open'&&a.task.feedback.includes('Merge phase FAILED')))process.exit(1)" \
  "$tc5_out"
[ "$(store_count_open "$tc5_trigger")" -eq 0 ] || { echo "FAIL: TC-05 trigger store written directly" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-06: deploy-verify success → only halt, no enqueue (INV-1 regression)
# ---------------------------------------------------------------------------
echo "TC-06: deploy-verify success → only halt (INV-1)"
tc6="$WORK_ROOT/tc6"
tc6_repo="$tc6/repo"; tc6_pr="$tc6/pr"; tc6_trigger="$tc6/trigger"; tc6_log="$tc6/logs"
mkdir -p "$tc6_repo" "$tc6_pr" "$tc6_trigger" "$tc6_log"
git init -q --initial-branch=main "$tc6_repo"
git -C "$tc6_repo" config user.name "Test"
git -C "$tc6_repo" config user.email "test@example.invalid"
echo "base" > "$tc6_repo/README.md"
git -C "$tc6_repo" add .
git -C "$tc6_repo" commit -q -m "base"
git -C "$tc6_repo" checkout -q -b "dd/SPEC-006"
echo "feature" > "$tc6_repo/feature.js"
git -C "$tc6_repo" add .
git -C "$tc6_repo" commit -q -m "impl"
tc6_head="$(git -C "$tc6_repo" rev-parse HEAD)"
node "$LOOP_STORE_CLI" "$tc6_pr" put "$(printf '{"id":"pr-SPEC-006","status":"verifying","spec_id":"SPEC-006","spec_file":"/tmp/SPEC-006.md","branch":"dd/SPEC-006","base_commit":"%s"}' "$tc6_head")"
tc6_script="$tc6/run.sh"
render_template "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$tc6_script" \
  "workspace_repo=$tc6_repo" \
  "accept_cmd=true" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc6_trigger" \
  "pr_store_dir=$tc6_pr" \
  "deploy_log_dir=$tc6_log" \
  "pr_id=pr-SPEC-006" \
  "spec_id=SPEC-006" \
  "spec_file=/tmp/SPEC-006.md" \
  "branch=dd/SPEC-006" \
  "base_commit=$tc6_head"
tc6_out="$(bash "$tc6_script")"
assert_json "TC-06 effects only halt, no enqueue" \
  "if(!(e.effects.length===1&&e.effects[0].op==='halt'))process.exit(1)" \
  "$tc6_out"
[ "$(store_count_open "$tc6_trigger")" -eq 0 ] || { echo "FAIL: TC-06 trigger store written" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-07: merger success → only halt, no enqueue (INV-1 regression)
# ---------------------------------------------------------------------------
echo "TC-07: merger success → only halt (INV-1)"
tc7="$WORK_ROOT/tc7"
tc7_repo="$tc7/repo"; tc7_pr="$tc7/pr"; tc7_trigger="$tc7/trigger"; tc7_log="$tc7/logs"
mkdir -p "$tc7_repo" "$tc7_pr" "$tc7_trigger" "$tc7_log"
git init -q --initial-branch=main "$tc7_repo"
git -C "$tc7_repo" config user.name "Test"
git -C "$tc7_repo" config user.email "test@example.invalid"
echo "base" > "$tc7_repo/README.md"
git -C "$tc7_repo" add .
git -C "$tc7_repo" commit -q -m "base"
tc7_base="$(git -C "$tc7_repo" rev-parse HEAD)"
git -C "$tc7_repo" checkout -q -b "dd/SPEC-007"
echo "feature" > "$tc7_repo/feature.js"
git -C "$tc7_repo" add .
git -C "$tc7_repo" commit -q -m "impl"
git -C "$tc7_repo" checkout -q main
node "$LOOP_STORE_CLI" "$tc7_pr" put "$(printf '{"id":"pr-SPEC-007","status":"merging","spec_id":"SPEC-007","spec_file":"/tmp/SPEC-007.md","branch":"dd/SPEC-007","base_commit":"%s"}' "$tc7_base")"
tc7_script="$tc7/run.sh"
render_template "$ROOT/workflows/spec-gen/merger/templates/merger.md" "$tc7_script" \
  "workspace_repo=$tc7_repo" \
  "base_branch=main" \
  "accept_cmd=true" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc7_trigger" \
  "pr_store_dir=$tc7_pr" \
  "merge_log_dir=$tc7_log" \
  "pr_id=pr-SPEC-007" \
  "spec_id=SPEC-007" \
  "spec_file=/tmp/SPEC-007.md" \
  "branch=dd/SPEC-007" \
  "base_commit=$tc7_base"
tc7_out="$(bash "$tc7_script")"
assert_json "TC-07 effects only halt, no enqueue" \
  "if(!(e.effects.length===1&&e.effects[0].op==='halt'))process.exit(1)" \
  "$tc7_out"
[ "$(store_count_open "$tc7_trigger")" -eq 0 ] || { echo "FAIL: TC-07 trigger store written" >&2; fail=1; }

# ---------------------------------------------------------------------------
# TC-08: INV-2 — P-a1 task fields exactly match old put payload field set
# ---------------------------------------------------------------------------
echo "TC-08: P-a1 task field set == {id,status,spec_file,feedback} (INV-2)"
tc1_task_keys="$(echo "$tc1_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);console.log(Object.keys(e.effects[0].task).sort().join(","))})')"
expected_keys="feedback,id,spec_file,status"
if [ "$tc1_task_keys" = "$expected_keys" ]; then
  echo "ok: TC-08 task field set matches"
else
  echo "FAIL: TC-08 task field set mismatch: got '$tc1_task_keys', expected '$expected_keys'" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-09: INV-3 — spec-check FAIL retains update call (PR advanced to rejected)
# ---------------------------------------------------------------------------
echo "TC-09: spec-check FAIL retained update (PR rejected) (INV-3)"
# Already asserted in TC-03 via PR record status; re-state explicitly.
tc3_pr_status="$(echo "$tc3_pr_rec" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>console.log(JSON.parse(d).status))')"
if [ "$tc3_pr_status" = "rejected" ]; then
  echo "ok: TC-09 spec-check update call retained"
else
  echo "FAIL: TC-09 PR status is '$tc3_pr_status', expected rejected" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then echo "enqueue-routes FAILED"; exit 1; fi
echo "enqueue-routes PASSED"
