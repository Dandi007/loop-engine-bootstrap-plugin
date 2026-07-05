#!/usr/bin/env bash
# SPEC-004-b1-loop-events-wiring: loop 层事件接线静态 + smoke 测试。
# 不跑 drain、不调 LLM。头部纪律同既有测试文件。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
fail=0

# 与 acceptance.sh:9 同款自设 NODE_OPTIONS loader（幂等；TC-5 直跑 dist CLI 需要）。
export NODE_OPTIONS="--import file://$ENGINE_ROOT/scripts/register-node-esm-extension-loader.mjs"

# --- TC-1: 恰 2 处 phase_change append 调用（经 LOOP_EVENTS_CLI 变量，INV-5）---
# spec §4 字面量 'loop-events-cli.*append' 在 INV-5 派生变量实现下不匹配调用行；
# 语义锚死：append 调用恰好 2 处（每处带 --kind phase_change）。
tc1_cnt="$(grep -c -- '--kind phase_change' "$ROOT/bin/bootstrap-loop.sh" || true)"
if [ "$tc1_cnt" -eq 2 ]; then
  echo "ok: TC-1 two phase_change append calls"
else
  echo "FAIL: TC-1 phase_change call count=$tc1_cnt expected 2" >&2
  fail=1
fi

# --- TC-2: 失败容忍纪律，每处调用带 || true ---
# 多行调用：append 行 + 续行（--kind phase_change ...）合并后断言 || true 出现 2 次。
tc2_cnt="$(grep -A1 'append' "$ROOT/bin/bootstrap-loop.sh" | grep -c '|| true' || true)"
if [ "$tc2_cnt" -eq 2 ]; then
  echo "ok: TC-2 both append calls end with || true"
else
  echo "FAIL: TC-2 || true count=$tc2_cnt expected 2" >&2
  fail=1
fi

# --- TC-3a: impl->merge 事件归属 runs/impl + detail ---
if grep -q -- '--runs-root "\$RUN_ROOT/runs/impl"' "$ROOT/bin/bootstrap-loop.sh" \
   && grep -q '{"from":"impl","to":"merge"}' "$ROOT/bin/bootstrap-loop.sh" \
   && grep -q -- '--kind phase_change --label bootstrap' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "ok: TC-3a impl->merge event on runs/impl"
else
  echo "FAIL: TC-3a impl->merge event missing" >&2
  fail=1
fi

# --- TC-3b: merge->done 事件归属 runs/merge + detail ---
if grep -q -- '--runs-root "\$RUN_ROOT/runs/merge"' "$ROOT/bin/bootstrap-loop.sh" \
   && grep -q '{"from":"merge","to":"done"}' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "ok: TC-3b merge->done event on runs/merge"
else
  echo "FAIL: TC-3b merge->done event missing" >&2
  fail=1
fi

# --- TC-4: CLI 路径派生锚 + 无 require_file ---
if grep -q 'LOOP_EVENTS_CLI="\${LOOP_EVENTS_CLI:-\$(dirname "\$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "ok: TC-4 LOOP_EVENTS_CLI derived from dirname(LOOP_ENGINE_CLI) with env override"
else
  echo "FAIL: TC-4 LOOP_EVENTS_CLI definition missing or malformed" >&2
  fail=1
fi
tc4_req="$(grep -c 'require_file "\$LOOP_EVENTS_CLI"' "$ROOT/bin/bootstrap-loop.sh" || true)"
if [ "$tc4_req" -eq 0 ]; then
  echo "ok: TC-4 no require_file for LOOP_EVENTS_CLI (soft dependency)"
else
  echo "FAIL: TC-4 found $tc4_req require_file call(s) for LOOP_EVENTS_CLI" >&2
  fail=1
fi

# --- TC-5: smoke 正门真发一条 phase_change 事件 ---
if [ ! -f "$ENGINE_ROOT/dist/lib/loop-events-cli.js" ]; then
  echo "SKIP: TC-5 loop-events-cli.js missing (engine dist not built)" >&2
else
  tc5_tmp="$(mktemp -d)"
  if node "$ENGINE_ROOT/dist/lib/loop-events-cli.js" append --runs-root "$tc5_tmp" \
       --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}' \
       >/dev/null 2>&1; then
    if node -e '
      const fs = require("fs");
      const p = process.argv[1] + "/loop-events.jsonl";
      const lines = fs.readFileSync(p, "utf8").trim().split("\n");
      if (lines.length !== 1) { console.error("expected 1 line, got " + lines.length); process.exit(1); }
      const e = JSON.parse(lines[0]);
      if (e.kind !== "phase_change") { console.error("bad kind: " + e.kind); process.exit(1); }
      if (e.label !== "bootstrap") { console.error("bad label: " + e.label); process.exit(1); }
      if (e.detail.from !== "impl" || e.detail.to !== "merge") { console.error("bad detail: " + JSON.stringify(e.detail)); process.exit(1); }
      if (typeof e.ts !== "number") { console.error("bad ts type: " + typeof e.ts); process.exit(1); }
      console.log("ok");
    ' "$tc5_tmp" 2>&1 | grep -q '^ok$'; then
      echo "ok: TC-5 smoke append writes one valid phase_change event"
    else
      echo "FAIL: TC-5 event shape invalid" >&2
      fail=1
    fi
  else
    echo "FAIL: TC-5 append exited non-zero" >&2
    fail=1
  fi
  rm -rf "$tc5_tmp"
fi

# --- TC-6: 失败容忍语义仿真（CLI 缺失 + set -euo pipefail + || true 仍存活）---
tc6_out="$(bash -c 'set -euo pipefail; node /nonexistent/loop-events-cli.js append --runs-root /nonexistent --kind phase_change --label bootstrap --detail "{}" 2>/dev/null || true; echo survived')"
if [ "$tc6_out" = "survived" ]; then
  echo "ok: TC-6 || true absorbs CLI-missing failure under set -euo pipefail"
else
  echo "FAIL: TC-6 expected 'survived', got: $tc6_out" >&2
  fail=1
fi

# --- TC-7: 正门纪律（INV-2）repo 内无 loop-events.jsonl 直写/硬编码 ---
tc7_cnt="$(grep -rn 'loop-events\.jsonl' "$ROOT/bin" "$ROOT/workflows" "$ROOT/scripts" 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$tc7_cnt" -eq 0 ]; then
  echo "ok: TC-7 no direct loop-events.jsonl writes in bin/workflows/scripts"
else
  echo "FAIL: TC-7 found $tc7_cnt loop-events.jsonl reference(s) in bin/workflows/scripts" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "loop-events-wiring FAILED" >&2
  exit 1
fi
echo "loop-events-wiring PASSED"
