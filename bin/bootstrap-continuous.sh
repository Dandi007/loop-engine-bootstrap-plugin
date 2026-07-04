#!/usr/bin/env bash
# 持续自举循环（batch 模式）：每轮 batch 完成后自动播种新 batch-idea 重跑
# 双 Drain 架构：Phase 1 impl + Phase 2 merge，循环往复
# KIMI 额度满时自动切换 CC DS 作为 impl
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_TARGET_REPO="${BOOT_TARGET_REPO:?set BOOT_TARGET_REPO}"
LOOP=0
KIMI_FAILS=0
MAX_KIMI_FAILS=2

echo "[bootstrap-continuous] starting batch continuous loop, target=$BOOT_TARGET_REPO"

while true; do
  LOOP=$((LOOP + 1))

  # KIMI→DS fallback: 连续 2 轮 work=0 时切换 impl 到 CC DS
  if [ "$KIMI_FAILS" -ge "$MAX_KIMI_FAILS" ]; then
    echo "[bootstrap-continuous] KIMI failed $KIMI_FAILS times, switching impl to CC DS"
    export DD_WORK_RUNTIME="claude-code"
    export DD_WORK_MODEL="set_claude_ccswitch_ds"
  else
    export DD_WORK_RUNTIME="${DD_WORK_RUNTIME:-kimicode}"
    export DD_WORK_MODEL="${DD_WORK_MODEL:-kimi-for-coding/k2p7}"
  fi

  echo "[bootstrap-continuous] === batch round $LOOP (impl: ${DD_WORK_RUNTIME}/${DD_WORK_MODEL}) ==="

  export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
  export DD_REVIEW_MODEL="${DD_REVIEW_MODEL:-set_claude_ccswitch_glm}"
  export DD_ACCEPT_CMD="${DD_ACCEPT_CMD:-npm test}"
  export BOOT_MAX_PASSES="${BOOT_MAX_PASSES:-64}"
  export BOOT_MERGE_MAX_PASSES="${BOOT_MERGE_MAX_PASSES:-16}"

  # Run the two-phase batch drain
  drain_output=$(bash "$PLUGIN_ROOT/bin/bootstrap-loop.sh" 2>&1) || true
  echo "$drain_output"

  # Check if work stage failed (no work tick)
  if echo "$drain_output" | grep -q '"work":0'; then
    KIMI_FAILS=$((KIMI_FAILS + 1))
    echo "[bootstrap-continuous] work stage had 0 ticks, impl may be exhausted (fail $KIMI_FAILS/$MAX_KIMI_FAILS)"
  elif echo "$drain_output" | grep -q '"work":[1-9]'; then
    KIMI_FAILS=0
  fi

  echo "[bootstrap-continuous] batch round $LOOP complete, seeding next..."
  sleep 5
done