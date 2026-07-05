# SPEC-004: bootstrap-loop.sh 经 loop-events CLI 正门发 phase_change 事件（B1 遗留接线）

> 批次：组件模型 B2 波段投喂（内容属 B1 PROP-5 遗留：装配层 loop 事件接线）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`，基线 master@edb1a85）
> 依赖序：**无前置依赖，可先投**——engine 侧 `loop-events-cli` 已随 SPEC-170 合入（engine main=944c3af，`dist/lib/loop-events-cli.js` 存在）。与 SPEC-003 无文件交集（本 spec 只动 `bin/bootstrap-loop.sh` + tests），可与 SPEC-003 串行同波段。
> 定案来源：`../../design.md` §3.1 loop 层事件契约（B1 形状锁死）；`../../plan-b2.md` §范围表 SPEC-004 行 + Task B2-1 recon（接线点 = bootstrap-loop.sh:106/111）。

## 1. 背景

B1 批 SPEC-170 落了 loop 层事件的完整地基：`appendLoopEvent` + `loop-events.jsonl` 磁盘契约（drain 契约 v2）+ 引擎内三种 kind（round_start/round_end/pipeline_drained）由 runResident 在轮次边界自动发；**外部两种 kind（phase_change/fallback_triggered）设计为由装配层经 CLI 正门发**（`loop-events-cli.ts:2-5` 注释即此约定）。wf-observe 的 loop 状态 endpoint（SPEC-001-b1）靠这条事件流回答「loop 在哪个阶段」。

但 plugin 侧至今没接线：`bin/bootstrap-loop.sh` 的 Phase 1（impl drain，:106）→ Phase 2（merge drain，:111）切换是纯 bash 顺序执行，事件流里没有 phase 边界——观测接口只能看到两段各自的 round_*/pipeline_drained，无法回答「现在是 impl 还是 merge 阶段」。这正是 B1 验收要点「纯靠接口回答 loop 在哪个阶段」在 bootstrap 装配层的最后一公里。

B2 的两例交卷断链活体（SPEC-168 push 前断 / SPEC-169 信封 parse_failed，见 `../../progress.md`、`../../acceptance-b1.md`）复盘时都需要人工翻 drain stdout 拼时间线；phase 边界事件入流后，事故定位可直接问事件流「断在哪个阶段之后」。

### 侦察事实与范围外声明（fallback_triggered）

- `bin/bootstrap-loop.sh` 内**无任何模型 fallback 逻辑**（全文核对 :1-114）。
- 模型 fallback 切换逻辑存在于 `bin/bootstrap-continuous.sh:18-26`（KIMI 连续 2 轮 work=0 → 切 CC DS）——但该切换发生在**轮与轮的间隙**：上一轮 RUN_ROOT 的 drain 已结束、新一轮 RUN_ROOT 尚未由 bootstrap-loop.sh 创建（RUN_ID 按启动时刻生成，:5-6），切换时刻**没有可归属的 runs root**，接线需先解决事件归属设计问题。
- 故 **fallback_triggered 不在本 spec 范围**：本 spec 只接 phase_change 两处；bootstrap-continuous.sh 零改动。fallback_triggered 接线留待后续小 spec（届时需拍板归属规则，如写入下一轮 runs root 或引入 loop 级 runs root）。

## 2. 不变量（INV）

- **INV-1（主流程零扰动，`|| true` 纪律）**：两处事件调用均以 `|| true` 收尾；CLI 文件不存在、node 不可用、runs root 目录不存在（drain 早夭未建目录）、`--detail` 异常等任何失败都**不得改变 bootstrap-loop.sh 的既有控制流与退出码**。事件是观测旁路，不是主流程依赖——与 `LOOP_ENGINE_CLI`/`LOOP_STORE_CLI` 的 `require_file` 硬依赖（:12-23）刻意区别：**不对 loop-events CLI 做 require_file**。
- **INV-2（正门纪律）**：只经 `loop-events-cli.js append` 发事件，不直写 `loop-events.jsonl`（repo 内 grep 不得出现对该文件名的直写；文件名常量属 engine `loop-events.ts:22` 私有契约）。
- **INV-3（事件归属规则：写入刚结束阶段的 runs root）**：`phase_change {from:"impl",to:"merge"}` 写 `$RUN_ROOT/runs/impl`（Phase 1 runs root）；`phase_change {from:"merge",to:"done"}` 写 `$RUN_ROOT/runs/merge`（Phase 2 runs root）。规则一致：phase_change 事件追加到**它所终结的那个阶段**的事件流，与该阶段引擎自发的 round_*/pipeline_drained 同文件汇流，读端按 ts 排序即得完整阶段时间线。
- **INV-4（事件形状对齐 design §3.1）**：kind=`phase_change` ∈ `LOOP_EVENT_KINDS`（engine `loop-events.ts:8-10`，CLI 对非法 kind 退出码 2 拒收）；label=`bootstrap`（装配层归因）；detail 为 JSON 对象 `{"from":...,"to":...}`（CLI `--detail` 走 JSON.parse 宽进，`loop-events-cli.ts:29-32`）。
- **INV-5（CLI 路径派生，不新增硬编码绝对路径）**：loop-events CLI 路径从既有 `LOOP_ENGINE_CLI`（:8，缺省 `/data/code/self/loop-engine/dist/cli.js`）派生：`$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js`，并允许 `LOOP_EVENTS_CLI` 环境变量覆盖——与 :8-9 两个 CLI 变量同纪律。
- **INV-6（运行环境前提沿用，不新增 loader 设置）**：engine dist 为无扩展名 import 的 ESM（`dist/lib/loop-events-cli.js:8` `import ... from "./loop-events"`），需 loader 才能直跑——与 :93 处 `store-cli` 调用**同一前提**，生产路径由 `bootstrap-continuous.sh:30` 注入 `NODE_OPTIONS`（tsx loader），测试路径由 `tests/acceptance.sh:9` 注入 register loader。本 spec 不在 bootstrap-loop.sh 内新增 NODE_OPTIONS 设置；无 loader 场景下 node 报错由 INV-1 的 `|| true` 容忍。

## 3. 涉及文件与改动精确描述

### 3.1 `bin/bootstrap-loop.sh`

**改动 1**：在 :9（`LOOP_STORE_CLI=...` 行）之后新增一行：

```bash
LOOP_EVENTS_CLI="${LOOP_EVENTS_CLI:-$(dirname "$LOOP_ENGINE_CLI")/lib/loop-events-cli.js}"
```

（不加入 :36 的 export 列表——仅本脚本使用；不做 require_file，见 INV-1/INV-5。）

**改动 2**：Phase 1 → Phase 2 切换处。现状 :103-112：

```bash
# === PHASE 1: Batch draft + parallel impl + verify ===
echo "[bootstrap-loop] Phase 1: batch draft + parallel impl + verify"
echo "[bootstrap-loop] run_root=$RUN_ROOT target=$BOOT_TARGET_REPO"
impl_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_IMPL" "$RUN_ROOT/runs/impl" 2>&1) || true
echo "$impl_result"

# === PHASE 2: Sequential merge ===
echo "[bootstrap-loop] Phase 2: sequential merge"
merge_result=$(node "$LOOP_ENGINE_CLI" drain "$FLEET_MERGE" "$RUN_ROOT/runs/merge" 2>&1) || true
```

在 :107（`echo "$impl_result"`）之后、`# === PHASE 2` 注释行之前插入：

```bash
# loop 层事件正门（design §3.1）：Phase 1 结束 → 进入 merge。
# 写入刚结束阶段（impl）的 runs root；观测旁路，失败容忍（|| true），不中断主流程。
node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/impl" \
  --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}' || true
```

**改动 3**：Phase 2 结束处。在 :112（`echo "$merge_result"`）之后、:114（`echo "[bootstrap-loop] batch complete"`）之前插入：

```bash
node "$LOOP_EVENTS_CLI" append --runs-root "$RUN_ROOT/runs/merge" \
  --kind phase_change --label bootstrap --detail '{"from":"merge","to":"done"}' || true
```

**CLI 参数形式核对**（engine `src/lib/loop-events-cli.ts`，dist 同构）：

- 用法 `loop-events append --runs-root <dir> --kind <kind> --label <label> [--detail <json>]`（:14）；flag 成对解析（:17-22），四个 flag 顺序无关但必须成对。
- 退出码：0 ok / 1 append 失败（runs root 目录不存在等）/ 2 用法或 kind 非法（:4，:15,24-27,34）。三种非 0 均被 `|| true` 吸收。
- `--detail` 先按 JSON.parse 解析、失败按原始字符串收（:29-32）——本 spec 传严格 JSON 单引号字面量，无 shell 展开风险。
- 落盘形状：`{ts, kind, label, detail}` 追加到 `<runsRoot>/loop-events.jsonl`（`loop-events.ts:29-41`），与 drain 契约 v2 对齐。

**其余零改动**：`bin/bootstrap-continuous.sh` 不动（fallback 范围外，§1）；stores 播种、fleet 渲染、drain 调用行逐字不变。

### 3.2 新建 `tests/loop-events-wiring.test.sh`

bash 静态 + smoke 测试（不跑 drain、不调 LLM）。头部纪律同既有测试文件（`set -euo pipefail`、`ROOT` 定位、`ENGINE_ROOT` 缺省 `/data/code/self/loop-engine`）；smoke 段 guard：`[ -f "$ENGINE_ROOT/dist/lib/loop-events-cli.js" ]` 不满足则 SKIP（镜像 acceptance.sh:38-39 纪律）。TC 见 §4。

### 3.3 `tests/acceptance.sh` 接线

在 complete-effect 测试块（:614-621）之后追加同构块：

```bash
# --- loop-events wiring tests (SPEC-004-b1-loop-events-wiring) ---
echo "running loop-events wiring tests"
if bash "$ROOT/tests/loop-events-wiring.test.sh"; then
  echo "ok: loop-events wiring tests passed"
else
  echo "FAIL: loop-events wiring tests failed" >&2
  fail=1
fi
```

（注意：acceptance.sh:9 已全局设 `NODE_OPTIONS` register loader，smoke 段直跑 dist CLI 可用。）

## 4. 测试要求

### RED 场景列表（tests/loop-events-wiring.test.sh）

1. **TC-1（接线计数锚，恰 2）**：`grep -c 'loop-events-cli.*append' "$ROOT/bin/bootstrap-loop.sh"` 恰为 2（当前 0，红）。
2. **TC-2（失败容忍纪律，恰 2）**：`grep -c 'loop-events-cli.*append.*|| true\|^\s*--kind phase_change.*|| true' bin/bootstrap-loop.sh` ——两条 append 调用行（含续行）均以 `|| true` 收尾；实现上断言「出现 `append` 与 `|| true` 的调用共 2 处」（多行调用时对续行终止符断言，写法允许微调但语义锚死：**每处调用都带 `|| true`**）。
3. **TC-3（归属与 detail 锚）**：grep 断言其一含 `--runs-root "$RUN_ROOT/runs/impl"` 且 detail 为 `{"from":"impl","to":"merge"}`；另一含 `--runs-root "$RUN_ROOT/runs/merge"` 且 detail 为 `{"from":"merge","to":"done"}`；两处 label 均为 `bootstrap`、kind 均为 `phase_change`。
4. **TC-4（CLI 路径派生锚）**：grep 断言 bootstrap-loop.sh 含 `LOOP_EVENTS_CLI=` 定义且从 `dirname "$LOOP_ENGINE_CLI"` 派生、支持环境覆盖（`${LOOP_EVENTS_CLI:-...}` 形式）；且 **无** 对 loop-events CLI 的 `require_file` 调用（INV-1 软依赖）。
5. **TC-5（smoke：正门真发一条）**：`tmp=$(mktemp -d)`；执行与脚本同形状的调用 `node "$ENGINE_ROOT/dist/lib/loop-events-cli.js" append --runs-root "$tmp" --kind phase_change --label bootstrap --detail '{"from":"impl","to":"merge"}'`；断言退出 0 且 `$tmp/loop-events.jsonl` 恰 1 行、JSON 字段 `kind=="phase_change" && label=="bootstrap" && detail.from=="impl" && detail.to=="merge"` 且 `ts` 为 number。
6. **TC-6（失败容忍语义仿真）**：在 `bash -c 'set -euo pipefail; node /nonexistent/loop-events-cli.js append --runs-root /nonexistent --kind phase_change --label bootstrap --detail "{}" || true; echo survived'` 子 shell 中断言输出 `survived` 且退出 0——证明 `set -euo pipefail` 下 `|| true` 写法确实兜住 CLI 缺失。
7. **TC-7（正门纪律，INV-2）**：`grep -rn 'loop-events\.jsonl' bin/ workflows/ scripts/ | wc -l` 恰 0（repo 内无对事件文件的直写/硬编码；tests/ 目录豁免——TC-5 断言读文件属读端验证）。

### 组合场景断言

- **零回归**：`bash tests/acceptance.sh` 既有全部 TC（fleet 渲染/manifest 校验/state-flow 七场景/enqueue-routes/complete-effect/两条 grep 清零断言）全绿——本 spec 未触碰任何 workflow/template/store 路径，任何回归都说明改错了文件。
- **范围外声明验证**：`git diff --name-only master -- bin/bootstrap-continuous.sh | wc -l` 恰 0（fallback 范围外，INV 之外的防御性自检）。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（含新增 loop-events-wiring 块）。
- grep 计数锚（在 plugin repo 根执行）：
  ```bash
  grep -c 'loop-events-cli' bin/bootstrap-loop.sh          # 预期 3（1 定义 + 2 调用）
  grep -c '|| true' <(grep -A1 'loop-events-cli.*append' bin/bootstrap-loop.sh)  # 每处调用带 || true（写法允许等价变体，语义见 TC-2）
  grep -rn 'loop-events\.jsonl' bin/ workflows/ scripts/ | wc -l   # 预期 0（正门纪律）
  git diff --name-only master -- bin/bootstrap-continuous.sh | wc -l  # 预期 0
  ```

## 6. 豁免清单

| 豁免/范围外项 | 说明 | 锚 |
|---|---|---|
| `fallback_triggered` 接线 | bootstrap-loop.sh 内无 fallback 逻辑（侦察事实）；KIMI→DS 切换在 bootstrap-continuous.sh:18-26，处于轮间隙、无可归属 runs root，接线留待后续小 spec | `git diff` 断言 bootstrap-continuous.sh 零改动（§4 组合断言） |
| 事件发送失败的告警 | 观测旁路失败仅由 CLI stderr 自然透出（不重定向抑制），不做重试/告警——与 engine `appendLoopEvent` 「写失败警告一次后静默」哲学对齐（`loop-events.ts:21,36-39`） | INV-1 |

# References
- 设计 SSoT：`../../design.md` §3.1 loop 层事件契约（B1 形状锁死：`{ts, kind, label, detail}`，kind 含 phase_change/fallback_triggered）
- recon 定案：`../../plan-b2.md` Task B2-1（接线点 bootstrap-loop.sh:106/111；仅 phase_change）
- engine 签名核对（main=944c3af）：`src/lib/loop-events-cli.ts:3-4,14-35`（用法/flag 解析/退出码）、`src/lib/loop-events.ts:8-10,22,29-41`（kinds/文件名/append 语义）、`dist/lib/loop-events-cli.js`（存在性 + :8 无扩展名 import → loader 前提）
- plugin 实况核对（master=edb1a85）：`bin/bootstrap-loop.sh:5-9,12-23,36,103-114`、`bin/bootstrap-continuous.sh:18-26,30,37`、`tests/acceptance.sh:9,38-39,605-621`
- 动机素材：`../../progress.md` 2026-07-04 23:31（SPEC-168 事故时间线靠人工拼）、`../../acceptance-b1.md` SPEC-169 行
