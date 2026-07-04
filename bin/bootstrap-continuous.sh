#!/usr/bin/env bash
# 持续自举循环（batch 模式）：每轮 batch 完成后自动播种新 batch-idea 重跑
# 双 Drain 架构：Phase 1 impl + Phase 2 merge，循环往复
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOT_TARGET_REPO="${BOOT_TARGET_REPO:?set BOOT_TARGET_REPO}"
LOOP=0

echo "[bootstrap-continuous] starting batch continuous loop, target=$BOOT_TARGET_REPO"

while true; do
  LOOP=$((LOOP + 1))

  echo "[bootstrap-continuous] === batch round $LOOP ==="

  export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
  export DD_REVIEW_MODEL="${DD_REVIEW_MODEL:-set_claude_ccswitch_glm}"
  export DD_ACCEPT_CMD="${DD_ACCEPT_CMD:-npm test}"
  export BOOT_MAX_PASSES="${BOOT_MAX_PASSES:-64}"
  export BOOT_MERGE_MAX_PASSES="${BOOT_MERGE_MAX_PASSES:-16}"

  # Run the two-phase batch drain
  drain_output=$(bash "$PLUGIN_ROOT/bin/bootstrap-loop.sh" 2>&1) || true
  echo "$drain_output"

  echo "[bootstrap-continuous] batch round $LOOP complete, seeding next..."
  sleep 5
done