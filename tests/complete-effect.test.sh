#!/usr/bin/env bash
# Integration tests for SPEC-002-b0-plugin-complete-effect.
# Verifies the 4 migrated workflow templates (spec-check / deploy-verify / merger)
# emit `{op:"complete", status:<terminal>}` effects instead of directly calling
# `node $loop_store_cli $pr_store_dir update`, and that loop_store_cli / pr_store_dir
# are fully purged from the templates (INV-5).
#
# Each scenario renders a template with fixture store dirs, runs it via bash,
# and asserts on the emitted JSON envelope. The PR store dir is checked to be
# untouched (no direct update).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
ENGINE_DIST_TEMPLATE="$ENGINE_ROOT/dist/template.js"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}"

if [ ! -f "$ENGINE_DIST_TEMPLATE" ]; then
  echo "SKIP: Loop Engine dist missing; build it to run complete-effect tests" >&2
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

store_count_all() {
  # Count records of any status in the given store dir.
  node "$LOOP_STORE_CLI" "$1" list open 2>/dev/null | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(d).length)}catch{console.log(0)}})'
}

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
# TC-01: P-b1 — spec-check PASS → complete ready-to-deploy, no direct update
# ---------------------------------------------------------------------------
echo "TC-01: spec-check PASS → complete ready-to-deploy"
tc1="$WORK_ROOT/tc1"
tc1_repo="$tc1/repo"; tc1_pr="$tc1/pr"; tc1_trigger="$tc1/trigger"
mkdir -p "$tc1_repo" "$tc1_pr" "$tc1_trigger"
git init -q --initial-branch=main "$tc1_repo"
git -C "$tc1_repo" config user.name "Test"
git -C "$tc1_repo" config user.email "test@example.invalid"
echo "base" > "$tc1_repo/README.md"
git -C "$tc1_repo" add .
git -C "$tc1_repo" commit -q -m "base"
tc1_base="$(git -C "$tc1_repo" rev-parse HEAD)"
git -C "$tc1_repo" checkout -q -b "dd/SPEC-001"
mkdir -p "$tc1_repo/docs/specs"
echo "spec" > "$tc1_repo/docs/specs/SPEC-001.md"
git -C "$tc1_repo" add .
git -C "$tc1_repo" commit -q -m "impl"
tc1_pr_count_before="$(store_count_all "$tc1_pr")"
tc1_script="$tc1/run.sh"
render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$tc1_script" \
  "workspace_repo=$tc1_repo" \
  "base_commit=$tc1_base" \
  "branch=dd/SPEC-001" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "pr_store_dir=$tc1_pr" \
  "trigger_store_dir=$tc1_trigger" \
  "pr_id=pr-SPEC-001" \
  "spec_id=SPEC-001" \
  "spec_file=$tc1_repo/docs/specs/SPEC-001.md"
tc1_out="$(bash "$tc1_script")"
assert_json "TC-01 emits complete ready-to-deploy" \
  "const a=e.effects.find(x=>x.op==='complete');if(!(a&&a.status==='ready-to-deploy'))process.exit(1)" \
  "$tc1_out"
tc1_pr_count_after="$(store_count_all "$tc1_pr")"
if [ "$tc1_pr_count_before" = "$tc1_pr_count_after" ]; then
  echo "ok: TC-01 PR store untouched (no direct update)"
else
  echo "FAIL: TC-01 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-02: P-b2 — spec-check FAIL → complete rejected + enqueue trigger
# ---------------------------------------------------------------------------
echo "TC-02: spec-check FAIL → complete rejected + enqueue trigger"
tc2="$WORK_ROOT/tc2"
tc2_repo="$tc2/repo"; tc2_pr="$tc2/pr"; tc2_trigger="$tc2/trigger"
mkdir -p "$tc2_repo" "$tc2_pr" "$tc2_trigger"
git init -q --initial-branch=main "$tc2_repo"
git -C "$tc2_repo" config user.name "Test"
git -C "$tc2_repo" config user.email "test@example.invalid"
echo "base" > "$tc2_repo/README.md"
git -C "$tc2_repo" add .
git -C "$tc2_repo" commit -q -m "base"
tc2_base="$(git -C "$tc2_repo" rev-parse HEAD)"
git -C "$tc2_repo" checkout -q -b "dd/SPEC-002"
echo "code" > "$tc2_repo/code.js"
git -C "$tc2_repo" add .
git -C "$tc2_repo" commit -q -m "impl"
tc2_pr_count_before="$(store_count_all "$tc2_pr")"
tc2_script="$tc2/run.sh"
render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$tc2_script" \
  "workspace_repo=$tc2_repo" \
  "base_commit=$tc2_base" \
  "branch=dd/SPEC-002" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "pr_store_dir=$tc2_pr" \
  "trigger_store_dir=$tc2_trigger" \
  "pr_id=pr-SPEC-002" \
  "spec_id=SPEC-002" \
  "spec_file=$tc2_repo/docs/specs/SPEC-002.md"
tc2_out="$(bash "$tc2_script")"
assert_json "TC-02 emits complete rejected" \
  "const a=e.effects.find(x=>x.op==='complete');if(!(a&&a.status==='rejected'))process.exit(1)" \
  "$tc2_out"
assert_json "TC-02 emits enqueue trigger" \
  "const a=e.effects.find(x=>x.op==='enqueue'&&x.queue==='trigger');if(!(a&&a.task.status==='open'&&a.task.feedback.includes('REJECT')))process.exit(1)" \
  "$tc2_out"
tc2_pr_count_after="$(store_count_all "$tc2_pr")"
if [ "$tc2_pr_count_before" = "$tc2_pr_count_after" ]; then
  echo "ok: TC-02 PR store untouched (no direct update)"
else
  echo "FAIL: TC-02 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-03: P-b3 — deploy-verify ready-to-merge → complete ready-to-merge, no enqueue
# ---------------------------------------------------------------------------
echo "TC-03: deploy-verify success → complete ready-to-merge"
tc3="$WORK_ROOT/tc3"
tc3_repo="$tc3/repo"; tc3_pr="$tc3/pr"; tc3_trigger="$tc3/trigger"; tc3_log="$tc3/logs"
mkdir -p "$tc3_repo" "$tc3_pr" "$tc3_trigger" "$tc3_log"
git init -q --initial-branch=main "$tc3_repo"
git -C "$tc3_repo" config user.name "Test"
git -C "$tc3_repo" config user.email "test@example.invalid"
echo "base" > "$tc3_repo/README.md"
git -C "$tc3_repo" add .
git -C "$tc3_repo" commit -q -m "base"
git -C "$tc3_repo" checkout -q -b "dd/SPEC-003"
echo "feature" > "$tc3_repo/feature.js"
git -C "$tc3_repo" add .
git -C "$tc3_repo" commit -q -m "impl"
tc3_head="$(git -C "$tc3_repo" rev-parse HEAD)"
tc3_pr_count_before="$(store_count_all "$tc3_pr")"
tc3_script="$tc3/run.sh"
render_template "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" "$tc3_script" \
  "workspace_repo=$tc3_repo" \
  "accept_cmd=true" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc3_trigger" \
  "pr_store_dir=$tc3_pr" \
  "deploy_log_dir=$tc3_log" \
  "pr_id=pr-SPEC-003" \
  "spec_id=SPEC-003" \
  "spec_file=/tmp/SPEC-003.md" \
  "branch=dd/SPEC-003" \
  "base_commit=$tc3_head"
tc3_out="$(bash "$tc3_script")"
assert_json "TC-03 emits complete ready-to-merge, then halt, no enqueue" \
  "if(!(e.effects.length===2&&e.effects[0].op==='complete'&&e.effects[0].status==='ready-to-merge'&&e.effects[1].op==='halt'))process.exit(1)" \
  "$tc3_out"
tc3_pr_count_after="$(store_count_all "$tc3_pr")"
if [ "$tc3_pr_count_before" = "$tc3_pr_count_after" ]; then
  echo "ok: TC-03 PR store untouched"
else
  echo "FAIL: TC-03 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-04: P-b3 — deploy-verify verify_failed → complete verify_failed + enqueue
# ---------------------------------------------------------------------------
echo "TC-04: deploy-verify failure → complete verify_failed + enqueue"
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
tc4_pr_count_before="$(store_count_all "$tc4_pr")"
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
assert_json "TC-04 emits complete verify_failed + enqueue + halt" \
  "if(!(e.effects.length===3&&e.effects[0].op==='complete'&&e.effects[0].status==='verify_failed'&&e.effects[1].op==='enqueue'&&e.effects[2].op==='halt'))process.exit(1)" \
  "$tc4_out"
tc4_pr_count_after="$(store_count_all "$tc4_pr")"
if [ "$tc4_pr_count_before" = "$tc4_pr_count_after" ]; then
  echo "ok: TC-04 PR store untouched"
else
  echo "FAIL: TC-04 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-05: P-b4 — merger merged → complete merged, no enqueue
# ---------------------------------------------------------------------------
echo "TC-05: merger success → complete merged"
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
echo "feature" > "$tc5_repo/feature.js"
git -C "$tc5_repo" add .
git -C "$tc5_repo" commit -q -m "impl"
git -C "$tc5_repo" checkout -q main
tc5_pr_count_before="$(store_count_all "$tc5_pr")"
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
assert_json "TC-05 emits complete merged + halt, no enqueue" \
  "if(!(e.effects.length===2&&e.effects[0].op==='complete'&&e.effects[0].status==='merged'&&e.effects[1].op==='halt'))process.exit(1)" \
  "$tc5_out"
tc5_pr_count_after="$(store_count_all "$tc5_pr")"
if [ "$tc5_pr_count_before" = "$tc5_pr_count_after" ]; then
  echo "ok: TC-05 PR store untouched"
else
  echo "FAIL: TC-05 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-06: P-b4 — merger merge_failed → complete merge_failed + enqueue
# ---------------------------------------------------------------------------
echo "TC-06: merger test-fail → complete merge_failed + enqueue"
tc6="$WORK_ROOT/tc6"
tc6_repo="$tc6/repo"; tc6_pr="$tc6/pr"; tc6_trigger="$tc6/trigger"; tc6_log="$tc6/logs"
mkdir -p "$tc6_repo" "$tc6_pr" "$tc6_trigger" "$tc6_log"
git init -q --initial-branch=main "$tc6_repo"
git -C "$tc6_repo" config user.name "Test"
git -C "$tc6_repo" config user.email "test@example.invalid"
echo "base" > "$tc6_repo/README.md"
git -C "$tc6_repo" add .
git -C "$tc6_repo" commit -q -m "base"
tc6_base="$(git -C "$tc6_repo" rev-parse HEAD)"
git -C "$tc6_repo" checkout -q -b "dd/SPEC-006"
echo "feature" > "$tc6_repo/feature.js"
git -C "$tc6_repo" add .
git -C "$tc6_repo" commit -q -m "impl"
git -C "$tc6_repo" checkout -q main
tc6_pr_count_before="$(store_count_all "$tc6_pr")"
tc6_script="$tc6/run.sh"
render_template "$ROOT/workflows/spec-gen/merger/templates/merger.md" "$tc6_script" \
  "workspace_repo=$tc6_repo" \
  "base_branch=main" \
  "accept_cmd=false" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc6_trigger" \
  "pr_store_dir=$tc6_pr" \
  "merge_log_dir=$tc6_log" \
  "pr_id=pr-SPEC-006" \
  "spec_id=SPEC-006" \
  "spec_file=/tmp/SPEC-006.md" \
  "branch=dd/SPEC-006" \
  "base_commit=$tc6_base"
tc6_out="$(bash "$tc6_script")"
assert_json "TC-06 emits complete merge_failed + enqueue + halt" \
  "if(!(e.effects.length===3&&e.effects[0].op==='complete'&&e.effects[0].status==='merge_failed'&&e.effects[1].op==='enqueue'&&e.effects[2].op==='halt'))process.exit(1)" \
  "$tc6_out"
tc6_pr_count_after="$(store_count_all "$tc6_pr")"
if [ "$tc6_pr_count_before" = "$tc6_pr_count_after" ]; then
  echo "ok: TC-06 PR store untouched"
else
  echo "FAIL: TC-06 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-07: P-b4 — merger merge_conflict → complete merge_conflict + enqueue
# ---------------------------------------------------------------------------
echo "TC-07: merger conflict → complete merge_conflict + enqueue"
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
echo "branch version" > "$tc7_repo/conflict.txt"
git -C "$tc7_repo" add .
git -C "$tc7_repo" commit -q -m "branch change"
git -C "$tc7_repo" checkout -q main
echo "main version" > "$tc7_repo/conflict.txt"
git -C "$tc7_repo" add .
git -C "$tc7_repo" commit -q -m "main change"
tc7_pr_count_before="$(store_count_all "$tc7_pr")"
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
assert_json "TC-07 emits complete merge_conflict" \
  "const a=e.effects.find(x=>x.op==='complete');if(!(a&&a.status==='merge_conflict'))process.exit(1)" \
  "$tc7_out"
tc7_pr_count_after="$(store_count_all "$tc7_pr")"
if [ "$tc7_pr_count_before" = "$tc7_pr_count_after" ]; then
  echo "ok: TC-07 PR store untouched"
else
  echo "FAIL: TC-07 PR store written directly" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-08: complete precedes enqueue in failure paths (P-b3 / P-b4 ordering)
# ---------------------------------------------------------------------------
echo "TC-08: complete index < enqueue index in failure paths"
if echo "$tc4_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const ci=e.effects.findIndex(x=>x.op==="complete");const ei=e.effects.findIndex(x=>x.op==="enqueue");if(!(ci>=0&&ei>=0&&ci<ei))process.exit(1)})'; then
  echo "ok: TC-08 deploy-verify failure complete before enqueue"
else
  echo "FAIL: TC-08 deploy-verify ordering wrong: $tc4_out" >&2
  fail=1
fi
if echo "$tc6_out" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const e=JSON.parse(d);const ci=e.effects.findIndex(x=>x.op==="complete");const ei=e.effects.findIndex(x=>x.op==="enqueue");if(!(ci>=0&&ei>=0&&ci<ei))process.exit(1)})'; then
  echo "ok: TC-08 merger failure complete before enqueue"
else
  echo "FAIL: TC-08 merger ordering wrong: $tc6_out" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-09: INV-5 — loop_store_cli / pr_store_dir purged from migrated templates
# ---------------------------------------------------------------------------
echo "TC-09: INV-5 templates purged of loop_store_cli / pr_store_dir"
for tpl in \
  "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" \
  "$ROOT/workflows/spec-gen/spec-check/workflow.yaml" \
  "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" \
  "$ROOT/workflows/spec-gen/deploy-verify/workflow.yaml" \
  "$ROOT/workflows/spec-gen/merger/templates/merger.md" \
  "$ROOT/workflows/spec-gen/merger/workflow.yaml"; do
  if grep -q 'loop_store_cli\|pr_store_dir' "$tpl"; then
    echo "FAIL: $tpl still references loop_store_cli / pr_store_dir" >&2
    fail=1
  fi
done
if [ "$fail" -eq 0 ]; then
  echo "ok: TC-09 no loop_store_cli / pr_store_dir in migrated templates/yamls"
fi

# ---------------------------------------------------------------------------
# TC-10: INV-5 — loop_store_cli purged from spec-check/deploy-verify/merger
# input sections in fleet templates (§3.7/§3.8)
# ---------------------------------------------------------------------------
echo "TC-10: INV-5 fleet input sections purged of loop_store_cli (spec-check/deploy-verify/merger)"
fleet_impl_check="$(awk '
  /^  - label: spec-check$/ || /^  - label: deploy-verify$/ { in_section=1; label=$0; next }
  /^  - label:/ && in_section { in_section=0 }
  in_section && /loop_store_cli/ { print label": "$0 }
' "$ROOT/workflows/fleet-impl.yaml.tpl")"
fleet_merge_check="$(awk '
  /^  - label: merger$/ { in_section=1; label=$0; next }
  /^  - label:/ && in_section { in_section=0 }
  in_section && /loop_store_cli/ { print label": "$0 }
' "$ROOT/workflows/fleet-merge.yaml.tpl")"
if [ -z "$fleet_impl_check" ] && [ -z "$fleet_merge_check" ]; then
  echo "ok: TC-10 spec-check/deploy-verify/merger input sections purged of loop_store_cli"
else
  echo "FAIL: TC-10 fleet input sections still reference loop_store_cli: $fleet_impl_check $fleet_merge_check" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-11: INV-6 — trigger_store_dir retained in three workflow.yaml payloads
# ---------------------------------------------------------------------------
echo "TC-11: INV-6 trigger_store_dir retained in payloads"
for wf in \
  "$ROOT/workflows/spec-gen/spec-check/workflow.yaml" \
  "$ROOT/workflows/spec-gen/deploy-verify/workflow.yaml" \
  "$ROOT/workflows/spec-gen/merger/workflow.yaml"; do
  if ! grep -q 'trigger_store_dir' "$wf"; then
    echo "FAIL: $wf missing trigger_store_dir" >&2
    fail=1
  fi
done
if [ "$fail" -eq 0 ]; then
  echo "ok: TC-11 trigger_store_dir retained in all three payloads"
fi

# ---------------------------------------------------------------------------
# TC-12: §5 fleet template full purge — loop_store_cli must be 0 lines across
# the whole fleet-impl.yaml.tpl and fleet-merge.yaml.tpl (not just the
# spec-check/deploy-verify/merger input sections). This is the literal §5
# acceptance grep.
# ---------------------------------------------------------------------------
echo "TC-12: §5 fleet templates fully purged of loop_store_cli (0 lines)"
fleet_loop_cli_count="$(grep -n 'loop_store_cli' \
  "$ROOT/workflows/fleet-impl.yaml.tpl" \
  "$ROOT/workflows/fleet-merge.yaml.tpl" 2>/dev/null | grep -v '^Binary' | wc -l | tr -d ' ' || true)"
if [ "$fleet_loop_cli_count" -eq 0 ]; then
  echo "ok: TC-12 fleet-impl/fleet-merge contain 0 loop_store_cli lines"
else
  echo "FAIL: TC-12 fleet templates still reference loop_store_cli ($fleet_loop_cli_count lines):" >&2
  grep -n 'loop_store_cli' "$ROOT/workflows/fleet-impl.yaml.tpl" "$ROOT/workflows/fleet-merge.yaml.tpl" 2>/dev/null >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then echo "complete-effect FAILED"; exit 1; fi
echo "complete-effect PASSED"
