#!/usr/bin/env bash
# 占位 acceptance：scaffold 阶段只校验 spec 要求的关键构件存在。
# KIMI 实现 fleet.yaml.tpl / spec-gen pipelines / bin 后，逐步替换为真实断言。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check(){ if [ ! -e "$ROOT/$1" ]; then echo "MISSING: $1" >&2; fail=1; else echo "ok: $1"; fi; }

# INV-2 复用不分叉：fleet 里 Impl 四 pipeline 应指向 dev-dispatch，而非拷贝定义
check "workflows/fleet.yaml.tpl"
check "workflows/spec-gen/draft/workflow.yaml"
check "workflows/spec-gen/review/workflow.yaml"
check "workflows/spec-gen/rework/templates"
check "bin/bootstrap-loop.sh"

if [ "$fail" -ne 0 ]; then echo "acceptance FAILED (scaffold placeholders missing)"; exit 1; fi
echo "acceptance PASSED"
