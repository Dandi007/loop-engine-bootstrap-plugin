#!/usr/bin/env bash
# Static tests for SPEC-005-b3-pointer-records (pointer message triplet).
# Verifies the B3 pointer-triplet contract evolution and the producer-side
# full-chain wiring (drafter export / persona echo / rework passthrough /
# three re-seed inheritance / fleet bind / seed payload channel).
#
# This test does NOT call LLMs and does NOT run drain. It only does static
# assertions: schema shape, ajv fixtures, bind count anchors, template/payload
# presence anchors, and the seed zero-touch anchor.
#
# ajv is borrowed from the engine dependency tree (engine package.json
# depends on ajv@^8.20.0); this repo stays zero-npm-dependency.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
fail=0

if [ ! -d "$ENGINE_ROOT/node_modules/ajv" ]; then
  echo "SKIP: engine node_modules/ajv missing; npm install in $ENGINE_ROOT" >&2
  exit 0
fi

CONTRACTS_DIR="$ROOT/workflows/spec-gen/contracts"

# ---------------------------------------------------------------------------
# TC-1: three schema triplet declaration shape (INV-1 / INV-2 / INV-3)
# ---------------------------------------------------------------------------
tc1_fail=0
ENGINE_ROOT="$ENGINE_ROOT" ROOT="$ROOT" node -e '
  const fs = require("node:fs");
  const path = require("node:path");
  const dir = path.join(process.env.ROOT, "workflows/spec-gen/contracts");
  const trigger = JSON.parse(fs.readFileSync(path.join(dir, "trigger.schema.json"), "utf8"));
  const specpr  = JSON.parse(fs.readFileSync(path.join(dir, "spec-pr.schema.json"), "utf8"));
  const pr      = JSON.parse(fs.readFileSync(path.join(dir, "pr.schema.json"), "utf8"));
  let bad = 0;
  const PAT = "^[0-9a-f]{7,40}$";
  for (const [name, s] of [["trigger", trigger], ["spec-pr", specpr], ["pr", pr]]) {
    for (const k of ["repo", "commit", "spec_path", "mr"]) {
      if (!s.properties || !s.properties[k]) { console.error("FAIL: TC-1 " + name + " missing property " + k); bad = 1; }
    }
    const cp = s.properties && s.properties.commit;
    if (!cp || cp.pattern !== PAT) { console.error("FAIL: TC-1 " + name + " commit.pattern=" + (cp && cp.pattern)); bad = 1; }
    const rp = s.properties && s.properties.repo;
    if (rp && rp.pattern) { console.error("FAIL: TC-1 " + name + " repo must NOT have pattern (宽进)"); bad = 1; }
    const spp = s.properties && s.properties.spec_path;
    if (spp && spp.pattern) { console.error("FAIL: TC-1 " + name + " spec_path must NOT have pattern"); bad = 1; }
    const mrp = s.properties && s.properties.mr;
    if (!mrp || mrp.type !== "object") { console.error("FAIL: TC-1 " + name + " mr must be type:object"); bad = 1; }
    const sfp = s.properties && s.properties.spec_file;
    if (!sfp || !sfp.description || sfp.description.length === 0) { console.error("FAIL: TC-1 " + name + " spec_file.description empty (INV-3 注记)"); bad = 1; }
    if (s.additionalProperties !== true) { console.error("FAIL: TC-1 " + name + " additionalProperties must stay true (INV-8)"); bad = 1; }
  }
  // required sets
  for (const k of ["repo", "commit", "spec_path"]) {
    if (!trigger.required.includes(k)) { console.error("FAIL: TC-1 trigger required missing " + k); bad = 1; }
    if (!specpr.required.includes(k))  { console.error("FAIL: TC-1 spec-pr required missing " + k); bad = 1; }
    if (pr.required.includes(k))        { console.error("FAIL: TC-1 pr required MUST NOT include " + k + " (INV-2 钉死可选)"); bad = 1; }
  }
  if (bad) process.exit(1);
' || tc1_fail=1
if [ "$tc1_fail" -eq 0 ]; then
  echo "ok: TC-1 三 schema triplet 声明形状 (INV-1/INV-2/INV-3)"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-2: ajv 正反例 (commit pattern 执法 + INV-2 pr 可选 + INV-4 同 commit 合法)
# ---------------------------------------------------------------------------
tc2_fail=0
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# 正例
cat > "$FIXTURE_DIR/good-trigger-hex40.json" <<'JSON'
{"schema":"trigger","expect":"pass","record":{"id":"SPEC-170","status":"open","spec_file":"/tmp/SPEC-170.md","feedback":"(none)","repo":"/data/code/self/loop-engine","commit":"a1b2c3d4e5f60718293a4b5c6d7e8f9012345678","spec_path":"docs/specs/SPEC-170.md"}}
JSON
cat > "$FIXTURE_DIR/good-trigger-redo-same-commit.json" <<'JSON'
{"schema":"trigger","expect":"pass","record":{"id":"SPEC-170-r1783237261","status":"open","spec_file":"/tmp/SPEC-170.md","feedback":"(none)","repo":"/data/code/self/loop-engine","commit":"a1b2c3d4e5f60718293a4b5c6d7e8f9012345678","spec_path":"docs/specs/SPEC-170.md"}}
JSON
cat > "$FIXTURE_DIR/good-pr-no-triplet.json" <<'JSON'
{"schema":"pr","expect":"pass","record":{"id":"pr-SPEC-004","status":"checking","spec_id":"SPEC-004","spec_file":"/tmp/SPEC-004.md","branch":"dd/SPEC-004","base_commit":"abc123"}}
JSON
cat > "$FIXTURE_DIR/good-pr-hex7.json" <<'JSON'
{"schema":"pr","expect":"pass","record":{"id":"pr-SPEC-009","status":"ready","spec_id":"SPEC-009","spec_file":"/tmp/SPEC-009.md","branch":"dd/SPEC-009","base_commit":"abc123","repo":"/data/code/self/x","commit":"abcdef0","spec_path":"docs/specs/SPEC-009.md"}}
JSON
cat > "$FIXTURE_DIR/good-spec-pr-triplet.json" <<'JSON'
{"schema":"spec-pr","expect":"pass","record":{"id":"spec-pr-SPEC-001","status":"reviewing","spec_id":"SPEC-001","spec_file":"/tmp/SPEC-001.md","repo":"/data/code/self/x","commit":"abcdef0123456789abcdef0123456789abcdef01","spec_path":"docs/specs/SPEC-001.md"}}
JSON

# 反例
cat > "$FIXTURE_DIR/bad-trigger-main.json" <<'JSON'
{"schema":"trigger","expect":"reject","record":{"id":"SPEC-171","status":"open","spec_file":"/tmp/SPEC-171.md","feedback":"(none)","repo":"/data/code/self/x","commit":"main","spec_path":"docs/specs/SPEC-171.md"}}
JSON
cat > "$FIXTURE_DIR/bad-trigger-feature-slash.json" <<'JSON'
{"schema":"trigger","expect":"reject","record":{"id":"SPEC-172","status":"open","spec_file":"/tmp/SPEC-172.md","feedback":"(none)","repo":"/data/code/self/x","commit":"feature/x","spec_path":"docs/specs/SPEC-172.md"}}
JSON
cat > "$FIXTURE_DIR/bad-trigger-missing-repo.json" <<'JSON'
{"schema":"trigger","expect":"reject","record":{"id":"SPEC-173","status":"open","spec_file":"/tmp/SPEC-173.md","feedback":"(none)","commit":"abcdef0","spec_path":"docs/specs/SPEC-173.md"}}
JSON
cat > "$FIXTURE_DIR/bad-specpr-missing-commit.json" <<'JSON'
{"schema":"spec-pr","expect":"reject","record":{"id":"spec-pr-SPEC-002","status":"reviewing","spec_id":"SPEC-002","spec_file":"/tmp/SPEC-002.md","repo":"/data/code/self/x","spec_path":"docs/specs/SPEC-002.md"}}
JSON
cat > "$FIXTURE_DIR/bad-pr-main.json" <<'JSON'
{"schema":"pr","expect":"reject","record":{"id":"pr-SPEC-010","status":"ready","spec_id":"SPEC-010","spec_file":"/tmp/SPEC-010.md","branch":"dd/SPEC-010","base_commit":"abc123","commit":"main"}}
JSON
cat > "$FIXTURE_DIR/bad-trigger-short-hex.json" <<'JSON'
{"schema":"trigger","expect":"reject","record":{"id":"SPEC-174","status":"open","spec_file":"/tmp/SPEC-174.md","feedback":"(none)","repo":"/data/code/self/x","commit":"def456","spec_path":"docs/specs/SPEC-174.md"}}
JSON

if ! ENGINE_ROOT="$ENGINE_ROOT" ROOT="$ROOT" FIXTURE_DIR="$FIXTURE_DIR" node -e '
  const { createRequire } = require("node:module");
  const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
  const Ajv = req("ajv");
  const fs = require("node:fs");
  const path = require("node:path");
  const ajv = new Ajv({ allErrors: true });
  const contractsDir = path.join(process.env.ROOT, "workflows/spec-gen/contracts");
  const validate = {};
  for (const f of fs.readdirSync(contractsDir)) {
    if (!f.endsWith(".schema.json")) continue;
    const name = f.replace(/\.schema\.json$/, "");
    validate[name] = ajv.compile(JSON.parse(fs.readFileSync(path.join(contractsDir, f), "utf8")));
  }
  let bad = 0;
  for (const f of fs.readdirSync(process.env.FIXTURE_DIR).sort()) {
    const { schema, expect, record } = JSON.parse(fs.readFileSync(path.join(process.env.FIXTURE_DIR, f), "utf8"));
    const v = validate[schema];
    if (!v) { console.error("no schema for " + schema); bad = 1; continue; }
    const ok = v(record);
    const wantPass = expect === "pass";
    if (ok !== wantPass) {
      console.error("FAIL: " + f + " expected " + expect + " validate=" + ok + (ok ? "" : " errors=" + JSON.stringify(v.errors)));
      bad = 1;
    }
  }
  if (bad) process.exit(1);
'; then
  echo "FAIL: TC-2 ajv 正反例 mismatch" >&2
  tc2_fail=1
fi
if [ "$tc2_fail" -eq 0 ]; then
  echo "ok: TC-2 ajv 正反例 (commit pattern / INV-2 pr 可选 / INV-4 同 commit)"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-3: 8 处 bind 计数锚 (fleet-impl 恰 7, fleet-merge 恰 1; 行首缩进锚定)
# ---------------------------------------------------------------------------
count_impl_sp="$(grep -Ec '^[[:space:]]+spec_path: spec_path$' "$ROOT/workflows/fleet-impl.yaml.tpl")"
count_merge_sp="$(grep -Ec '^[[:space:]]+spec_path: spec_path$' "$ROOT/workflows/fleet-merge.yaml.tpl")"
count_impl_c="$(grep -Ec '^[[:space:]]+commit: commit$' "$ROOT/workflows/fleet-impl.yaml.tpl")"
count_merge_c="$(grep -Ec '^[[:space:]]+commit: commit$' "$ROOT/workflows/fleet-merge.yaml.tpl")"
count_impl_r="$(grep -Ec '^[[:space:]]+repo: repo$' "$ROOT/workflows/fleet-impl.yaml.tpl")"
count_merge_r="$(grep -Ec '^[[:space:]]+repo: repo$' "$ROOT/workflows/fleet-merge.yaml.tpl")"
tc3_fail=0
[ "$count_impl_sp" -eq 7 ] || { echo "FAIL: TC-3 fleet-impl spec_path: spec_path count=$count_impl_sp expected 7" >&2; tc3_fail=1; }
[ "$count_merge_sp" -eq 1 ] || { echo "FAIL: TC-3 fleet-merge spec_path: spec_path count=$count_merge_sp expected 1" >&2; tc3_fail=1; }
[ "$count_impl_c" -eq 7 ] || { echo "FAIL: TC-3 fleet-impl commit: commit count=$count_impl_c expected 7" >&2; tc3_fail=1; }
[ "$count_merge_c" -eq 1 ] || { echo "FAIL: TC-3 fleet-merge commit: commit count=$count_merge_c expected 1" >&2; tc3_fail=1; }
[ "$count_impl_r" -eq 7 ] || { echo "FAIL: TC-3 fleet-impl repo: repo count=$count_impl_r expected 7" >&2; tc3_fail=1; }
[ "$count_merge_r" -eq 1 ] || { echo "FAIL: TC-3 fleet-merge repo: repo count=$count_merge_r expected 1" >&2; tc3_fail=1; }
if [ "$tc3_fail" -eq 0 ]; then
  echo "ok: TC-3 fleet bind 计数锚 (impl 7 + merge 1 = 8)"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-4: drafter 出口在场 (rev-parse HEAD 指令 + 三字段 + 纪律语句)
# ---------------------------------------------------------------------------
draft="$ROOT/workflows/spec-gen/draft/templates/draft.md"
tc4_fail=0
grep -q '"repo"' "$draft" || { echo "FAIL: TC-4 draft.md missing \"repo\"" >&2; tc4_fail=1; }
grep -q '"commit"' "$draft" || { echo "FAIL: TC-4 draft.md missing \"commit\"" >&2; tc4_fail=1; }
grep -q '"spec_path"' "$draft" || { echo "FAIL: TC-4 draft.md missing \"spec_path\"" >&2; tc4_fail=1; }
grep -q 'rev-parse HEAD' "$draft" || { echo "FAIL: TC-4 draft.md missing rev-parse HEAD" >&2; tc4_fail=1; }
grep -q '真实 hash' "$draft" || { echo "FAIL: TC-4 draft.md missing 纪律语句" >&2; tc4_fail=1; }
if [ "$tc4_fail" -eq 0 ]; then
  echo "ok: TC-4 drafter 出口携带 triplet + rev-parse HEAD + 纪律语句"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-5: 生产链透传在场 (persona 回声 / rework 透传 / 三 re-seed helper 哨兵)
# ---------------------------------------------------------------------------
tc5_fail=0
reviewer="$ROOT/workflows/spec-gen/review/personas/spec-reviewer.md"
for line in '"repo": "{{repo}}"' '"commit": "{{commit}}"' '"spec_path": "{{spec_path}}"'; do
  grep -qF "$line" "$reviewer" || { echo "FAIL: TC-5 spec-reviewer.md missing echo line $line" >&2; tc5_fail=1; }
done

rework="$ROOT/workflows/spec-gen/rework/templates/spec-rework.md"
grep -q 'process.env.REPO' "$rework" || { echo "FAIL: TC-5 spec-rework.md missing REPO env" >&2; tc5_fail=1; }
grep -q 'process.env.COMMIT' "$rework" || { echo "FAIL: TC-5 spec-rework.md missing COMMIT env" >&2; tc5_fail=1; }
grep -q 'process.env.SPEC_PATH' "$rework" || { echo "FAIL: TC-5 spec-rework.md missing SPEC_PATH env" >&2; tc5_fail=1; }

helper_count="$(grep -rl 'B3 pointer triplet resolution (SPEC-005)' \
  "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" \
  "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" \
  "$ROOT/workflows/spec-gen/merger/templates/merger.md" 2>/dev/null | wc -l | tr -d ' ' || true)"
[ "$helper_count" -eq 3 ] || { echo "FAIL: TC-5 helper sentinel count=$helper_count expected 3" >&2; tc5_fail=1; }

for tpl in \
  "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" \
  "$ROOT/workflows/spec-gen/deploy-verify/templates/deploy-verify.md" \
  "$ROOT/workflows/spec-gen/merger/templates/merger.md"; do
  grep -q 'process.env.REPO_V' "$tpl" || { echo "FAIL: TC-5 $tpl missing REPO_V" >&2; tc5_fail=1; }
  grep -q 'process.env.COMMIT_V' "$tpl" || { echo "FAIL: TC-5 $tpl missing COMMIT_V" >&2; tc5_fail=1; }
  grep -q 'process.env.SPEC_PATH_V' "$tpl" || { echo "FAIL: TC-5 $tpl missing SPEC_PATH_V" >&2; tc5_fail=1; }
done

if [ "$tc5_fail" -eq 0 ]; then
  echo "ok: TC-5 生产链透传 (persona 回声 / rework 透传 / 三 re-seed helper)"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-6: seed payload 通道 (恰 5 文件; review 必填, 其余可选)
# ---------------------------------------------------------------------------
tc6_files="$(grep -lE '^[[:space:]]+spec_path: "\{\{spec_path\??\}\}"$' "$ROOT"/workflows/spec-gen/*/workflow.yaml 2>/dev/null | wc -l | tr -d ' ' || true)"
[ "$tc6_files" -eq 5 ] || { echo "FAIL: TC-6 spec_path payload file count=$tc6_files expected 5" >&2; fail=1; }
# review 必填形态
grep -qE '^[[:space:]]+spec_path: "\{\{spec_path\}\}"$' "$ROOT/workflows/spec-gen/review/workflow.yaml" \
  || { echo "FAIL: TC-6 review must use required {{spec_path}} form" >&2; fail=1; }
# 其余四个可选形态
for d in rework spec-check deploy-verify merger; do
  grep -qE '^[[:space:]]+spec_path: "\{\{spec_path\?\}\}"$' "$ROOT/workflows/spec-gen/$d/workflow.yaml" \
    || { echo "FAIL: TC-6 $d must use optional {{spec_path?}} form" >&2; fail=1; }
done
if [ "$tc6_files" -eq 5 ]; then
  echo "ok: TC-6 seed payload 通道 (恰 5; review 必填 / 其余可选)"
fi

# ---------------------------------------------------------------------------
# TC-7: seed 零改动锚 (bootstrap-loop.sh idea payload 段无 spec_path)
# ---------------------------------------------------------------------------
if grep -q 'spec_path' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "FAIL: TC-7 bin/bootstrap-loop.sh unexpectedly references spec_path" >&2
  fail=1
else
  echo "ok: TC-7 bootstrap-loop.sh seed 段零 spec_path (§3.10 亲核落定)"
fi

# ---------------------------------------------------------------------------
# TC-8: fixture 迁移完整性 (pipeline-contracts 全绿)
# ---------------------------------------------------------------------------
if bash "$ROOT/tests/pipeline-contracts.test.sh" >/dev/null 2>&1; then
  echo "ok: TC-8 pipeline-contracts 全绿 (fixture 迁移完整)"
else
  echo "FAIL: TC-8 pipeline-contracts 失败 (fixture 迁移不完整)" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "pointer-records FAILED"
  exit 1
fi
echo "pointer-records PASSED"
