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
echo "pointer-consumption PASSED (A/D group skeleton)"
