# SPEC-004-b1-loop-events-wiring — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先写失败测试，确认红，最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`
> 无前置依赖：engine dist 已含 `dist/lib/loop-events-cli.js`（SPEC-170 已合入）。

## Files

**Modify（精确路径）：**
- `bin/bootstrap-loop.sh`（3 处插入：1 行变量定义 + 2 处事件调用）
- `tests/acceptance.sh`（新测试块接线，1 处追加）

**Create：**
- `tests/loop-events-wiring.test.sh`

**禁止触碰：**
- `bin/bootstrap-continuous.sh`（fallback 范围外声明）
- `workflows/`、`scripts/` 下任何文件

## Interfaces

**Consumes：**
- engine `dist/lib/loop-events-cli.js`：`append --runs-root <dir> --kind <kind> --label <label> [--detail <json>]`，退出码 0/1/2
- 既有变量 `LOOP_ENGINE_CLI`（bootstrap-loop.sh:8）、`RUN_ROOT`（:6）
- 现有 `tests/acceptance.sh`（:9 已设 NODE_OPTIONS loader；扩充不破坏）

**Produces：**
- bootstrap-loop.sh：Phase1→Phase2 与 Phase2→done 两条 phase_change 事件走正门
- tests/loop-events-wiring.test.sh：TC-1~TC-7

## TDD 步骤（bite-sized，每步 commit）

### Step 1：写失败测试 + 确认红

新建 `tests/loop-events-wiring.test.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
fail=0

# TC-1: 恰 2 处 append 调用
cnt="$(grep -c 'loop-events-cli.*append' "$ROOT/bin/bootstrap-loop.sh" || true)"
if [ "$cnt" -eq 2 ]; then echo "ok: TC-1 two append calls"; else echo "FAIL: TC-1 append count=$cnt expected 2" >&2; fail=1; fi

# TC-3: 归属与 detail 锚（两条各自成行断言）
if grep -q -- '--runs-root "\$RUN_ROOT/runs/impl"' "$ROOT/bin/bootstrap-loop.sh" \
   && grep -q '{"from":"impl","to":"merge"}' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "ok: TC-3a impl->merge event on runs/impl"
else echo "FAIL: TC-3a" >&2; fail=1; fi
if grep -q -- '--runs-root "\$RUN_ROOT/runs/merge"' "$ROOT/bin/bootstrap-loop.sh" \
   && grep -q '{"from":"merge","to":"done"}' "$ROOT/bin/bootstrap-loop.sh"; then
  echo "ok: TC-3b merge->done event on runs/merge"
else echo "FAIL: TC-3b" >&2; fail=1; fi

# ...（TC-2/4/5/6/7 见后续步骤）
[ "$fail" -eq 0 ] || { echo "loop-events-wiring FAILED"; exit 1; }
```

`bash tests/loop-events-wiring.test.sh` **确认红**（当前 bootstrap-loop.sh 无任何 loop-events 调用）。

### Step 2：最小实现——bootstrap-loop.sh 三处插入

1. :9 之后加：
   ```bash
   LOOP_EVENTS_CLI="${LOOP_EVENTS_CLI:-$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"
   ```
2. `echo "$impl_result"`（:107）之后、`# === PHASE 2` 注释之前插入（逐字见 spec §3.1 改动 2）：
   ```bash
   node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/impl" \
     --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}' || true
   ```
3. `echo "$merge_result"` 之后、`batch complete` echo 之前插入（spec §3.1 改动 3）：
   ```bash
   node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/merge" \
     --kind phase_change --label bootstrap --detail '{"from":"merge","to":"done"}' || true
   ```
4. **不加** require_file、**不加** export、**不动** bootstrap-continuous.sh。
5. `bash tests/loop-events-wiring.test.sh` — TC-1/TC-3 绿。

commit：`feat: bootstrap-loop phase_change 事件走 loop-events 正门（SPEC-004）`

### Step 3：补齐纪律 TC（TC-2/TC-4/TC-7）

- TC-2：断言两处调用行（含反斜杠续行的末行）均以 `|| true` 收尾——实现建议：`grep -A1 'loop-events-cli.*append' bin/bootstrap-loop.sh | grep -c '|| true'` 恰 2。
- TC-4：断言含 `LOOP_EVENTS_CLI="${LOOP_EVENTS_CLI:-$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"` 定义；且 `grep -c 'require_file "\$LOOP_EVENTS_CLI"' bin/bootstrap-loop.sh` 恰 0。
- TC-7：`grep -rn 'loop-events\.jsonl' "$ROOT/bin" "$ROOT/workflows" "$ROOT/scripts" | wc -l` 恰 0。

确认绿。commit：`test: loop-events 接线纪律锚（|| true / 软依赖 / 正门）`

### Step 4：smoke + 失败容忍仿真（TC-5/TC-6）

- TC-5（guard：`[ -f "$ENGINE_ROOT/dist/lib/loop-events-cli.js" ]` 否则 SKIP 输出后跳过）：
  ```bash
  tmp="$(mktemp -d)"
  node "$ENGINE_ROOT/dist/lib/loop-events-cli.js" append --runs-root "$tmp" \
    --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}'
  node -e '
  const l = require("fs").readFileSync(process.argv[1] + "/loop-events.jsonl", "utf8").trim().split("\n");
  if (l.length !== 1) process.exit(1);
  const e = JSON.parse(l[0]);
  process.exit(e.kind === "phase_change" && e.label === "bootstrap" && e.detail.from === "impl" && e.detail.to === "merge" && typeof e.ts === "number" ? 0 : 1);
  ' "$tmp"
  ```
  注意：该段依赖调用方（acceptance.sh:9）已设 NODE_OPTIONS loader；单独跑本测试文件时如未设 loader，dist import 失败会使 TC-5 假红——测试文件头部按 acceptance.sh:9 同款自设 `NODE_OPTIONS`（幂等，重复设置无害）。
- TC-6：
  ```bash
  out="$(bash -c 'set -euo pipefail; node /nonexistent/loop-events-cli.js append --runs-root /nonexistent --kind phase_change --label bootstrap --detail "{}" 2>/dev/null || true; echo survived')"
  [ "$out" = "survived" ]
  ```

确认绿。commit：`test: loop-events smoke + 失败容忍仿真`

### Step 5：acceptance 接线 + 全量回归

1. `tests/acceptance.sh` complete-effect 块之后追加调用块（spec §3.3 逐字）。
2. 全量验收 + 范围自检：
   ```bash
   bash tests/acceptance.sh
   git diff --name-only master -- bin/bootstrap-continuous.sh workflows/ scripts/ | wc -l   # 必须 0
   ```

commit：`test: loop-events-wiring 接入 acceptance`

## INV 自检清单

- [ ] INV-1：两处调用带 `|| true`（TC-2）；无 require_file（TC-4）；TC-6 仿真存活
- [ ] INV-2：repo 内无 `loop-events.jsonl` 直写/硬编码（TC-7）
- [ ] INV-3：impl→merge 写 runs/impl，merge→done 写 runs/merge（TC-3）
- [ ] INV-4：kind=phase_change、label=bootstrap、detail 严格 JSON（TC-3/TC-5）
- [ ] INV-5：LOOP_EVENTS_CLI 从 LOOP_ENGINE_CLI dirname 派生 + 可覆盖（TC-4）
- [ ] INV-6：bootstrap-loop.sh 未新增 NODE_OPTIONS 设置（`git diff` 检查改动仅 3 处插入）
