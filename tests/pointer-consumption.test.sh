#!/usr/bin/env bash
# Static + behavior tests for SPEC-006-b3-pointer-consumption-inject-tool.
#
# Verifies:
#  - 消费点物化：spec-review 指针寻址读点 / persona 只读放行 / spec-check 守卫 commit 化（旧分支模式恰 0）
#  - bin/spec-inject.sh 行为：happy path / 拒收路径 / 幂等键
#  - 组合 TC-C 组：指针 × B2 契约 / 指针 × redo 链 / 生产者无关形状断言 / 幂等键正向
#  - dd 豁免锚：四模板 triplet 占位符恰 0 且 {{spec_file}} 保留断言成对
#
# 头部纪律镜像 pipeline-contracts.test.sh:1-30（set -euo pipefail / ROOT /
# ENGINE_ROOT guard SKIP / DD_PLUGIN_ROOT 缺省）。
#
# ajv 借自 engine 依赖树（engine package.json 依赖 ajv@^8.20.0）；本 repo 保持
# zero-npm-dependency。测试自建一次性 git repo 与临时 store，不依赖网络、不调 LLM。
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
# A 组：消费点物化（静态锚）
# ---------------------------------------------------------------------------

# TC-A1: spec-review 指针读在场（头部三条目 + git show 指令 + pointer unresolvable REJECT 并入语句）
tc_a1_fail=0
review_tpl="$ROOT/workflows/spec-gen/review/templates/spec-review.md"
grep -qF 'git -C {{repo}} show {{commit}}:{{spec_path}}' "$review_tpl" \
  || { echo "FAIL: TC-A1 spec-review.md missing pointer git show instruction" >&2; tc_a1_fail=1; }
grep -qF 'pointer unresolvable' "$review_tpl" \
  || { echo "FAIL: TC-A1 spec-review.md missing pointer unresolvable REJECT merge" >&2; tc_a1_fail=1; }
grep -qF -e '- repo: {{repo}}' "$review_tpl" \
  || { echo "FAIL: TC-A1 spec-review.md missing - repo: {{repo}} header" >&2; tc_a1_fail=1; }
grep -qF -e '- commit: {{commit}}' "$review_tpl" \
  || { echo "FAIL: TC-A1 spec-review.md missing - commit: {{commit}} header" >&2; tc_a1_fail=1; }
grep -qF -e '- spec_path: {{spec_path}}' "$review_tpl" \
  || { echo "FAIL: TC-A1 spec-review.md missing - spec_path: {{spec_path}} header" >&2; tc_a1_fail=1; }
if [ "$tc_a1_fail" -eq 0 ]; then
  echo "ok: TC-A1 spec-review 指针读在场（三条目 + git show + pointer unresolvable）"
else
  fail=1
fi

# TC-A2: persona 最小放行（read-only + git -C <repo> show；review/workflow.yaml write: false 原样）
tc_a2_fail=0
persona="$ROOT/workflows/spec-gen/review/personas/spec-reviewer.md"
grep -qF 'read-only' "$persona" \
  || { echo "FAIL: TC-A2 spec-reviewer.md missing read-only" >&2; tc_a2_fail=1; }
grep -qF 'git -C <repo> show' "$persona" \
  || { echo "FAIL: TC-A2 spec-reviewer.md missing git -C <repo> show" >&2; tc_a2_fail=1; }
grep -qE 'write: false' "$ROOT/workflows/spec-gen/review/workflow.yaml" \
  || { echo "FAIL: TC-A2 review/workflow.yaml missing write: false" >&2; tc_a2_fail=1; }
if [ "$tc_a2_fail" -eq 0 ]; then
  echo "ok: TC-A2 persona 最小放行（read-only git show；write: false 守住）"
else
  fail=1
fi

# TC-A3: spec-check 守卫 commit 化（旧模式 show "$branch": 恰 0；新模式恰 1；rel_spec_file 恰 0）
tc_a3_fail=0
sc_tpl="$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md"
old_count="$(grep -c 'show "$branch":' "$sc_tpl" || true)"
new_count="$(grep -c 'show "$commit_v:$spec_path_v"' "$sc_tpl" || true)"
rel_count="$(grep -c 'rel_spec_file' "$sc_tpl" || true)"
[ "$old_count" -eq 0 ] || { echo "FAIL: TC-A3 spec-check.md show \"\$branch\": count=$old_count expected 0" >&2; tc_a3_fail=1; }
[ "$new_count" -eq 1 ] || { echo "FAIL: TC-A3 spec-check.md show \"\$commit_v:\$spec_path_v\" count=$new_count expected 1" >&2; tc_a3_fail=1; }
[ "$rel_count" -eq 0 ] || { echo "FAIL: TC-A3 spec-check.md rel_spec_file count=$rel_count expected 0" >&2; tc_a3_fail=1; }
if [ "$tc_a3_fail" -eq 0 ]; then
  echo "ok: TC-A3 spec-check 守卫 commit 化（旧模式 0 / 新模式 1 / rel_spec_file 0）"
else
  fail=1
fi

# TC-A4: deploy-verify / merger 零触碰锚（本 spec 全部 commit 不含这两目录）
tc_a4_count="$(git log --oneline master..HEAD -- workflows/spec-gen/deploy-verify workflows/spec-gen/merger 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$tc_a4_count" -eq 0 ]; then
  echo "ok: TC-A4 deploy-verify/merger 零触碰（本分支 commit 范围 0）"
else
  echo "FAIL: TC-A4 deploy-verify/merger 被本 spec 触碰 ($tc_a4_count commit)" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# D 组：dd 豁免锚（INV-5）
# ---------------------------------------------------------------------------
# 豁免依据：plan-b3 定案「指针三元组=SSoT；spec_file 保留为派生物化字段（dd-plugin
# 4 消费点豁免区零改动+锚）」。
# 教训锚：plugin PR #6（edb1a85）——清零断言必须配豁免白名单/保留锚，防误伤豁免项。
# ---------------------------------------------------------------------------
if [ ! -d "$DD_PLUGIN_ROOT/workflows/spec" ]; then
  echo "SKIP: TC-D1 dd-plugin workflows/spec unavailable at $DD_PLUGIN_ROOT" >&2
else
  tc_d1_fail=0
  dd_tpls=( "$DD_PLUGIN_ROOT"/workflows/spec/{work,review,deploy,rework}/templates/*.md )
  triplet_count="$(grep -REc '\{\{ *(repo|commit|spec_path)\??' "${dd_tpls[@]}" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}' || true)"
  [ "$triplet_count" -eq 0 ] \
    || { echo "FAIL: TC-D1 dd-plugin triplet placeholder count=$triplet_count expected 0" >&2; tc_d1_fail=1; }
  for f in "${dd_tpls[@]}"; do
    sf_count="$(grep -c '{{spec_file}}' "$f" || true)"
    [ "$sf_count" -ge 1 ] \
      || { echo "FAIL: TC-D1 $f missing {{spec_file}} retention anchor (count=$sf_count)" >&2; tc_d1_fail=1; }
  done
  if [ "$tc_d1_fail" -eq 0 ]; then
    echo "ok: TC-D1 dd 豁免锚（triplet 恰 0 + {{spec_file}} 保留断言成对）"
  else
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "pointer-consumption FAILED (A/D group)"
  exit 1
fi

# ---------------------------------------------------------------------------
# B / C 组：spec-inject.sh 行为 + 组合场景（可执行测试，自建 fixture repo）
# ---------------------------------------------------------------------------
# fixture：mktemp -d 下 git repo + SPEC-900 探针 spec/plan；自建临时 store。
# 不依赖网络、不调 LLM。trap 清理。
# ---------------------------------------------------------------------------
ENGINE_DIST_TEMPLATE="$ENGINE_ROOT/dist/template.js"
if [ ! -f "$ENGINE_DIST_TEMPLATE" ]; then
  echo "SKIP: B/C group — engine dist/template.js missing" >&2
  exit 0
fi

BC_ROOT="$(mktemp -d)"
trap 'rm -rf "$BC_ROOT"' EXIT

# render_template：用 engine fill 渲染模板（对齐 acceptance.sh 的 render_template）。
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

# fixture repo + 探针 spec/plan
fixrepo="$BC_ROOT/repo"
git init -q --initial-branch=main "$fixrepo"
git -C "$fixrepo" config user.name "Test"
git -C "$fixrepo" config user.email "test@example.invalid"
mkdir -p "$fixrepo/docs/specs" "$fixrepo/docs/plans"
printf '# SPEC-900 inject probe\nbody line A\nbody line B\n' > "$fixrepo/docs/specs/SPEC-900-inject-probe.md"
printf '# impl plan\nstep 1\nstep 2\n' > "$fixrepo/docs/plans/SPEC-900-inject-probe.impl-plan.md"
echo "base" > "$fixrepo/README.md"
git -C "$fixrepo" add .
git -C "$fixrepo" commit -q -m "init probe"
fixrepo_abs="$(cd "$fixrepo" && pwd)"

STORE="$BC_ROOT/stores/trigger"

record_field() {
  # record_field <json-file> <key>
  node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))[process.argv[2]]??""' "$1" "$2"
}

# ---------------------------------------------------------------------------
# TC-B1: happy path 全形状
# ---------------------------------------------------------------------------
tc_b1_fail=0
fix_head="$(git -C "$fixrepo" rev-parse HEAD)"
fix_head8="${fix_head:0:8}"
if ! LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
    docs/specs/SPEC-900-inject-probe.md "$STORE" \
    docs/plans/SPEC-900-inject-probe.impl-plan.md >"$BC_ROOT/b1.out" 2>&1; then
  echo "FAIL: TC-B1 spec-inject exit non-zero" >&2; cat "$BC_ROOT/b1.out" >&2; tc_b1_fail=1
fi
store_count="$(find "$STORE" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$store_count" -eq 1 ] || { echo "FAIL: TC-B1 store count=$store_count expected 1" >&2; tc_b1_fail=1; }
rec="$STORE/SPEC-900-inject-probe@$fix_head8.json"
[ -f "$rec" ] || { echo "FAIL: TC-B1 record file missing: $rec" >&2; tc_b1_fail=1; }
if [ -f "$rec" ]; then
  [ "$(record_field "$rec" id)" = "SPEC-900-inject-probe@$fix_head8" ] || { echo "FAIL: TC-B1 id mismatch" >&2; tc_b1_fail=1; }
  [ "$(record_field "$rec" status)" = "open" ] || { echo "FAIL: TC-B1 status not open" >&2; tc_b1_fail=1; }
  [ "$(record_field "$rec" commit)" = "$fix_head" ] || { echo "FAIL: TC-B1 commit not full hash" >&2; tc_b1_fail=1; }
  [ "$(record_field "$rec" repo)" = "$fixrepo_abs" ] || { echo "FAIL: TC-B1 repo not abs" >&2; tc_b1_fail=1; }
  [ "$(record_field "$rec" spec_path)" = "docs/specs/SPEC-900-inject-probe.md" ] || { echo "FAIL: TC-B1 spec_path mismatch" >&2; tc_b1_fail=1; }
  [ "$(record_field "$rec" feedback)" = "(none)" ] || { echo "FAIL: TC-B1 feedback not (none)" >&2; tc_b1_fail=1; }
  spec_cache="$(record_field "$rec" spec_file)"
  case "$spec_cache" in
    */.spec-cache/SPEC-900-inject-probe@$fix_head8.md) ;;
    *) echo "FAIL: TC-B1 spec_file not .spec-cache form: $spec_cache" >&2; tc_b1_fail=1 ;;
  esac
  cmp -s <(git -C "$fixrepo" show "HEAD:docs/specs/SPEC-900-inject-probe.md") "$spec_cache" \
    || { echo "FAIL: TC-B1 spec cache != git show byte-for-byte" >&2; tc_b1_fail=1; }
  fb_file="$(record_field "$rec" feedback_file)"
  case "$fb_file" in
    */.spec-cache/SPEC-900-inject-probe@$fix_head8.impl-plan.md) ;;
    *) echo "FAIL: TC-B1 feedback_file not .spec-cache form: $fb_file" >&2; tc_b1_fail=1 ;;
  esac
  cmp -s <(git -C "$fixrepo" show "HEAD:docs/plans/SPEC-900-inject-probe.impl-plan.md") "$fb_file" \
    || { echo "FAIL: TC-B1 plan cache != git show byte-for-byte" >&2; tc_b1_fail=1; }
fi
if [ "$tc_b1_fail" -eq 0 ]; then
  echo "ok: TC-B1 happy path 全形状（id/commit hex40/.spec-cache cmp 逐字节/feedback_file）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-B2: 未 commit 拒收（INV-2，"不代 commit"机器证明）
# ---------------------------------------------------------------------------
tc_b2_fail=0
printf '# uncommitted spec\n' > "$fixrepo/docs/specs/SPEC-901-uncommitted.md"
before="$(git -C "$fixrepo" status --porcelain)"
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-901-uncommitted.md "$STORE" >"$BC_ROOT/b2.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 4 ] || { echo "FAIL: TC-B2 expected exit 4 got $rc" >&2; tc_b2_fail=1; }
store_count_after="$(find "$STORE" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$store_count_after" -eq 1 ] || { echo "FAIL: TC-B2 store grew to $store_count_after (零新增)" >&2; tc_b2_fail=1; }
after="$(git -C "$fixrepo" status --porcelain)"
[ "$before" = "$after" ] || { echo "FAIL: TC-B2 fixture repo state changed (不代 commit 破坏)" >&2; tc_b2_fail=1; }
rm -f "$fixrepo/docs/specs/SPEC-901-uncommitted.md"
if [ "$tc_b2_fail" -eq 0 ]; then
  echo "ok: TC-B2 未 commit 拒收 exit 4 + store 零新增 + repo 状态不变（INV-2）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-B3: 已 commit 但工作树 dirty 拒收；恢复后可注入
# ---------------------------------------------------------------------------
tc_b3_fail=0
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$BC_ROOT/stores/b3store" >"$BC_ROOT/b3.out" 2>&1
rc=$?
set -e
# dirty: append a line without commit
printf '\nextra dirty line\n' >> "$fixrepo/docs/specs/SPEC-900-inject-probe.md"
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$BC_ROOT/stores/b3store" >"$BC_ROOT/b3.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 4 ] || { echo "FAIL: TC-B3 dirty expected exit 4 got $rc" >&2; tc_b3_fail=1; }
git -C "$fixrepo" checkout -q -- docs/specs/SPEC-900-inject-probe.md
# recovered: inject into a fresh store should succeed
rm -rf "$BC_ROOT/stores/b3store"
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$BC_ROOT/stores/b3store" >"$BC_ROOT/b3.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "FAIL: TC-B3 recovered inject expected exit 0 got $rc" >&2; tc_b3_fail=1; }
if [ "$tc_b3_fail" -eq 0 ]; then
  echo "ok: TC-B3 committed 但 dirty 拒收 exit 4；恢复后可注入"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-B4: 文件名 governance（not-a-spec.md → exit 2）
# ---------------------------------------------------------------------------
tc_b4_fail=0
printf '# x\n' > "$fixrepo/not-a-spec.md"
git -C "$fixrepo" add .
git -C "$fixrepo" commit -q -m "add not-a-spec"
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  not-a-spec.md "$BC_ROOT/stores/b4store" >"$BC_ROOT/b4.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: TC-B4 governance expected exit 2 got $rc" >&2; tc_b4_fail=1; }
if [ "$tc_b4_fail" -eq 0 ]; then
  echo "ok: TC-B4 文件名 governance（not-a-spec.md → exit 2）"
else
  fail=1
fi
# rewind the governance commit so fixrepo HEAD stays at the probe commit for C-group.
git -C "$fixrepo" reset -q --hard HEAD~1

# ---------------------------------------------------------------------------
# TC-B5: 无第 4 参 → feedback_file == 空串；其余同 TC-B1
# ---------------------------------------------------------------------------
tc_b5_fail=0
b5_store="$BC_ROOT/stores/b5"
b5_head="$(git -C "$fixrepo" rev-parse HEAD)"
b5_head8="${b5_head:0:8}"
set +e
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$b5_store" >"$BC_ROOT/b5.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "FAIL: TC-B5 exit non-zero $rc" >&2; tc_b5_fail=1; }
b5_rec="$b5_store/SPEC-900-inject-probe@$b5_head8.json"
if [ -f "$b5_rec" ]; then
  [ "$(record_field "$b5_rec" feedback_file)" = "" ] || { echo "FAIL: TC-B5 feedback_file not empty" >&2; tc_b5_fail=1; }
  [ "$(record_field "$b5_rec" status)" = "open" ] || { echo "FAIL: TC-B5 status not open" >&2; tc_b5_fail=1; }
  [ "$(record_field "$b5_rec" commit)" = "$b5_head" ] || { echo "FAIL: TC-B5 commit mismatch" >&2; tc_b5_fail=1; }
else
  echo "FAIL: TC-B5 record missing" >&2; tc_b5_fail=1
fi
if [ "$tc_b5_fail" -eq 0 ]; then
  echo "ok: TC-B5 无第 4 参 → feedback_file 空串（其余同 TC-B1）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-C1: 指针 × B2 契约（real record 过 trigger.schema.json；删 commit 红；commit:"main" 红）
# ---------------------------------------------------------------------------
tc_c1_fail=0
c1_rec="$STORE/SPEC-900-inject-probe@$fix_head8.json"
ENGINE_ROOT="$ENGINE_ROOT" ROOT="$ROOT" REC="$c1_rec" node -e '
  const { createRequire } = require("node:module");
  const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
  const Ajv = req("ajv");
  const fs = require("node:fs");
  const path = require("node:path");
  const ajv = new Ajv({ allErrors: true });
  const schema = JSON.parse(fs.readFileSync(path.join(process.env.ROOT, "workflows/spec-gen/contracts/trigger.schema.json"), "utf8"));
  const v = ajv.compile(schema);
  const rec = JSON.parse(fs.readFileSync(process.env.REC, "utf8"));
  if (!v(rec)) { console.error("FAIL: TC-C1 real record rejected by trigger.schema: " + JSON.stringify(v.errors)); process.exit(1); }
  const noCommit = JSON.parse(JSON.stringify(rec)); delete noCommit.commit;
  if (v(noCommit)) { console.error("FAIL: TC-C1 record without commit should be rejected (required)"); process.exit(1); }
  const badCommit = JSON.parse(JSON.stringify(rec)); badCommit.commit = "main";
  if (v(badCommit)) { console.error("FAIL: TC-C1 record commit=main should be rejected (pattern)"); process.exit(1); }
' || tc_c1_fail=1
if [ "$tc_c1_fail" -eq 0 ]; then
  echo "ok: TC-C1 指针 × B2 契约（real record 绿 / 删 commit 红 / commit:main 红）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-C2: 指针 × redo 链（渲染 spec-check，守卫失败 → REJECT redo，task.id 含 @commit8-rN 且 triplet 逐字继承）
# ---------------------------------------------------------------------------
tc_c2_fail=0
# origin trigger = TC-B1 注入的 record（repo/commit 原值；spec_path 改指不存在文件以触发守卫失败）
origin_repo="$(record_field "$c1_rec" repo)"
origin_commit="$(record_field "$c1_rec" commit)"
# spec_id 用 origin record 的 id（SPEC-900-inject-probe@<commit8>）：
# spec-check 的 base_spec_id=${spec_id%%-r[0-9]*} 不剥离 @commit8 → origin 兜底命中同名文件；
# redo_spec_id = base_spec_id-r<ts> → @commit8-rN 共存（spec TC-C2 断言形态）。
c2_spec_id="SPEC-900-inject-probe@$fix_head8"
# 守卫失败场景：origin record 的 spec_path 改指不存在文件，触发 REJECT 分支；
# triplet 仍逐字继承 origin 记录当前值（repo/commit/spec_path）。origin_spec_path 取改后值。
origin_spec_path="docs/specs/does-not-exist.md"
mkdir -p "$BC_ROOT/c2/trigger"
node -e '
  const fs = require("node:fs");
  const r = JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  r.id = process.argv[3];
  r.spec_path = process.argv[4];
  fs.writeFileSync(process.argv[2], JSON.stringify(r, null, 2));
' "$c1_rec" "$BC_ROOT/c2/trigger/$c2_spec_id.json" "$c2_spec_id" "$origin_spec_path"
c2_script="$BC_ROOT/c2/run.sh"
render_template "$ROOT/workflows/spec-gen/spec-check/templates/spec-check.md" "$c2_script" \
  "workspace_repo=$fixrepo_abs" \
  "base_commit=$fix_head" \
  "branch=main" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "pr_store_dir=$BC_ROOT/c2/pr" \
  "trigger_store_dir=$BC_ROOT/c2/trigger" \
  "pr_id=pr-SPEC-900" \
  "spec_id=$c2_spec_id" \
  "spec_file=$fixrepo_abs/docs/specs/SPEC-900-inject-probe.md" \
  "repo=" \
  "commit=" \
  "spec_path="
c2_out="$(bash "$c2_script")"
ORIGIN_REPO="$origin_repo" ORIGIN_COMMIT="$origin_commit" ORIGIN_PATH="$origin_spec_path" \
C2_OUT="$c2_out" node -e '
  const out = JSON.parse(process.env.C2_OUT);
  const a = out.effects.find(x=>x.op==="enqueue"&&x.queue==="trigger");
  if (!a) { console.error("FAIL: TC-C2 no enqueue trigger effect"); process.exit(1); }
  if (!/^SPEC-900-inject-probe@[0-9a-f]{8}-r[0-9]+$/.test(a.task.id)) {
    console.error("FAIL: TC-C2 task.id not redo+@commit8 form: " + a.task.id); process.exit(1);
  }
  // triplet 逐字等于 origin record 原值（继承不漂移）
  if (a.task.repo !== process.env.ORIGIN_REPO || a.task.commit !== process.env.ORIGIN_COMMIT || a.task.spec_path !== process.env.ORIGIN_PATH) {
    console.error("FAIL: TC-C2 triplet drift: repo=" + a.task.repo + " commit=" + a.task.commit + " path=" + a.task.spec_path);
    process.exit(1);
  }
' || tc_c2_fail=1
if [ "$tc_c2_fail" -eq 0 ]; then
  echo "ok: TC-C2 指针 × redo 链（task.id @commit8-rN + triplet 逐字继承 origin）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-C3: 人工注入 × 同管道（生产者无关）—— rework APPROVE trigger task 键集合 == TC-B5 record 键集合（对称差恰 0）
# ---------------------------------------------------------------------------
tc_c3_fail=0
mkdir -p "$BC_ROOT/c3/idea" "$BC_ROOT/c3/trigger"
c3_script="$BC_ROOT/c3/run.sh"
render_template "$ROOT/workflows/spec-gen/rework/templates/spec-rework.md" "$c3_script" \
  "idea_store_dir=$BC_ROOT/c3/idea" \
  "trigger_store_dir=$BC_ROOT/c3/trigger" \
  "spec_verdict_id=verdict-SPEC-900" \
  "spec_id=SPEC-900-inject-probe" \
  "spec_file=$fixrepo_abs/docs/specs/SPEC-900-inject-probe.md" \
  "verdict=APPROVE" \
  "feedback=ok" \
  "feedback_file=" \
  "repo=$fixrepo_abs" \
  "commit=$fix_head" \
  "spec_path=docs/specs/SPEC-900-inject-probe.md"
c3_out="$(bash "$c3_script")"
REC_PATH="$b5_rec" C3_OUT="$c3_out" node -e '
  const rec = JSON.parse(require("fs").readFileSync(process.env.REC_PATH, "utf8"));
  const env = JSON.parse(process.env.C3_OUT);
  const task = env.effects.find(x=>x.op==="enqueue"&&x.queue==="trigger").task;
  // feedback_file 两侧同缺/同在的对称处理（spec §4 TC-C3 括注）：
  // rework APPROVE 出口无 feedback_file 键；TC-B5 record 有 feedback_file="" (空串=同缺)。
  // 比较前剔除 feedback_file，断言其余键集合逐字相等（对称差恰 0）。
  delete rec.feedback_file;
  delete task.feedback_file;
  const recKeys = Object.keys(rec).sort();
  const taskKeys = Object.keys(task).sort();
  const symDiff = recKeys.filter(k=>!taskKeys.includes(k)).concat(taskKeys.filter(k=>!recKeys.includes(k)));
  if (symDiff.length !== 0) {
    console.error("FAIL: TC-C3 key set symmetric diff != 0: rec=" + recKeys.join(",") + " task=" + taskKeys.join(","));
    process.exit(1);
  }
' || tc_c3_fail=1
if [ "$tc_c3_fail" -eq 0 ]; then
  echo "ok: TC-C3 生产者无关（rework APPROVE trigger task 键集合 == spec-inject record，对称差恰 0）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-C4: 幂等键（同参二次 → already injected + store 恰 1 + 内容不变；新 commit → 新记录 store 恰 2）
# ---------------------------------------------------------------------------
tc_c4_fail=0
c4_store="$BC_ROOT/stores/c4"
c4_head="$(git -C "$fixrepo" rev-parse HEAD)"
c4_head8="${c4_head:0:8}"
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$c4_store" docs/plans/SPEC-900-inject-probe.impl-plan.md >"$BC_ROOT/c4a.out" 2>&1
c4_rec="$c4_store/SPEC-900-inject-probe@$c4_head8.json"
cp "$c4_rec" "$BC_ROOT/c4_first.json"
c4b_out="$(LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$c4_store" docs/plans/SPEC-900-inject-probe.impl-plan.md 2>&1)"
echo "$c4b_out" | grep -q 'already injected' || { echo "FAIL: TC-C4 second inject missing 'already injected'" >&2; tc_c4_fail=1; }
c4_count="$(find "$c4_store" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$c4_count" -eq 1 ] || { echo "FAIL: TC-C4 store count=$c4_count expected 1 after re-inject" >&2; tc_c4_fail=1; }
cmp -s "$BC_ROOT/c4_first.json" "$c4_rec" || { echo "FAIL: TC-C4 record content changed (O_EXCL 不覆盖破坏)" >&2; tc_c4_fail=1; }
# new commit → new record
git -C "$fixrepo" commit -q --allow-empty -m "second"
LOOP_STORE_CLI="$LOOP_STORE_CLI" bash "$ROOT/bin/spec-inject.sh" "$fixrepo" \
  docs/specs/SPEC-900-inject-probe.md "$c4_store" docs/plans/SPEC-900-inject-probe.impl-plan.md >"$BC_ROOT/c4c.out" 2>&1
c4_count2="$(find "$c4_store" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$c4_count2" -eq 2 ] || { echo "FAIL: TC-C4 store count=$c4_count2 expected 2 after new commit" >&2; tc_c4_fail=1; }
if [ "$tc_c4_fail" -eq 0 ]; then
  echo "ok: TC-C4 幂等键（同参二次 already injected + 恰 1 不变；新 commit → 新记录 恰 2）"
else
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "pointer-consumption FAILED"
  exit 1
fi
echo "pointer-consumption PASSED"

