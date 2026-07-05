# SPEC-003: 自举六道工序 record 契约声明 —— contracts/*.schema.json + workflow.yaml io 段

> 批次：组件模型 B2（PROP-1 收编：io 声明 + record 契约）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`，基线 master@edb1a85）
> 依赖序：**依赖 engine 侧 B2 io 支持先合入**（`SPEC-172-b2-io-contracts-runtime` + `SPEC-173-b2-composition-check`）。依赖性质见 INV-1：engine `Workflow` zod 为非 strict `z.object`（`src/types.ts:100-106`，未知键剥离而非拒绝），故本 spec 的 io 段在旧引擎下被静默忽略、**解析层无硬依赖**；依赖是语义依赖——先合 engine 侧才能避免「声明了契约却无人执法」的假绿窗口，且若 engine 侧实现最终收紧 schema 也不受影响。
> 定案来源：`../../design.md` §2 B2 行（验收要点「自举六道工序全声明契约；坏记录被拦且有事件」）+ §3.2 io 契约草形；`../../plan-b2.md` Task B2-1 recon 定案。

## 1. 背景

### 1.1 动机活体：两例交卷断链（B1 批实证）

record 契约不是理论洁癖，B1 批留下两具活体：

- **SPEC-168（push 前断）**：worker 第 201 turn 撞 `error_max_turns` 截停（tick 2.9h / $369.84），交卷顺序为「先 complete trigger 后 push」——断在 push/建 PR/投 pr 记录之前，留下 **trigger=done / 分支未 push / pr store 空** 三重不一致，drain 见队列空以 drained 正常退出。处置为操作员**机械交接**：本地 gate 自检 → push → gh PR → **按 wave3a schema 手投 pr store 记录** → 重启 drain（`../../progress.md` 2026-07-04 23:31/23:35 条目）。
- **SPEC-169（信封 parse_failed）**：work 交卷信封解析失败断链，同样走机械交接手投记录（`../../acceptance-b1.md` SPEC-169 行）。

两例的共同点：**断链之后记录靠人手投**。手投记录没有任何形状校验——字段拼错、status 写歪、枚举越界都会静默进入队列，直到下游某站以更离奇的方式失败。record 契约让「机械交接」与 drafter 产出走同一道校验闸门（生产者无关），坏记录在 claim/enqueue 边界被拦且有事件（engine 侧执法）。

### 1.2 本 spec 的分工边界

B2 验收要点两半句的归属：

| 半句 | 归属 |
|---|---|
| 「自举六道工序全声明契约」 | **本 spec**：六 workflow.yaml 加 `io:` 段 + `contracts/*.schema.json` 落盘 |
| 「坏记录被拦且有事件」 | **engine 侧 B2 spec**：claim 入站校验失败 → record 推 `contract_rejected`；enqueue 出站校验失败 → contract_violations 哨兵；fleet 装配期 out/in 兼容检查（兼容 = schema 深度相等） |

本 spec 的 acceptance 只做**静态**校验（io 段存在性、schema ajv 可编译、正反例 fixture、豁免锚、symlink 完整性）；运行期拦截行为由 engine 侧 spec 的测试负责。

### 1.3 「六道工序」= bootstrap-plugin 自有六 workflow

`workflows/spec-gen/{draft,review,rework,spec-check,deploy-verify,merger}`。**dd-plugin 三道（work/review/rework，第三 repo `/data/code/self/loop-engine-dev-dispatch-plugin`）豁免不声明**，见 §6 豁免清单。

### 1.4 六道工序的 io 拓扑（盘点实况）

| workflow | in（claim store → record 类别） | out（routes queue → record 类别） |
|---|---|---|
| draft | idea store → idea | `spec-pr` → spec-pr |
| review | spec-pr store → spec-pr | `verdict` → verdict |
| rework | spec-verdict store → verdict | `trigger` → trigger；`idea` → idea |
| spec-check | pr store → pr | `trigger` → trigger |
| deploy-verify | pr store → pr | `trigger` → trigger |
| merger | pr store → pr | `trigger` → trigger |

claim store 依据：`workflows/fleet-impl.yaml.tpl:14-22`（draft←idea）、`:37-45`（spec-review←spec-pr）、`:55-66`（spec-rework←spec-verdict）、`:151-161`（spec-check←pr）、`:174-184`（deploy-verify←pr）、`workflows/fleet-merge.yaml.tpl:12-22`（merger←pr）。routes 依据：六 workflow.yaml 现有 `routes:` 段（见 §3.2）。

去重后 record 类别恰 **5 类**：idea / spec-pr / verdict / trigger / pr（verdict 与 spec-verdict 同形——spec-gen review 产 `spec_pr_id` 变体、dd review 产 `pr_id` 变体，同一 schema 以可选字段覆盖两者）。

### 1.5 record 形状实况来源（起草时逐条核对）

- trigger：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/trigger/*.json` + enqueue 构造处 `spec-rework.md:30-43`、`spec-check.md:38-52`、`deploy-verify.md:45-59`、`merger.md:66-80`
- pr：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/pr/*.json`（含 diff/diff_file/claimed_by 全字段样本）
- verdict：`b1-20260705-135500/stores/verdict/*.json`（pr_id 变体）+ `20260704-131809/stores/spec-verdict/*.json`（spec_pr_id 变体）+ 构造处 `review/personas/spec-reviewer.md:12-30`
- spec-pr：`20260704-131809/stores/spec-pr/*.json` + 构造处 `draft/templates/draft.md:72-88`
- idea：`20260704-131809/stores/idea/*.json` + 种子构造 `bin/bootstrap-loop.sh:83-93` + rework REJECT 构造 `spec-rework.md:49-63`

## 2. 不变量（INV）

- **INV-1（向后兼容，io 段 opt-in）**：engine `Workflow` zod schema 为非 strict `z.object`（`/data/code/self/loop-engine/src/types.ts:100-106`）——未知顶级键被**剥离**而非拒绝。故渲染后 fleet 在无 io 支持的旧引擎下：io 段静默失效，六道工序行为**逐字不变**；`bash tests/acceptance.sh` 既有 fleet-impl/fleet-merge `loadFleetManifest` 校验必须继续全绿。缺省无 io 段的 workflow（dd-plugin 三道）在新引擎下行为同样逐字不变（design §3.2 末行）。
- **INV-2（templates/personas 文案零改动）**：本 spec 只动六个 `workflow.yaml` + 新增 `contracts/`；六道工序的 `templates/*.md`、`personas/*.md` **一字不动**（`git diff --stat` 不得出现这些文件）。
- **INV-3（schema 宽进严出）**：所有 schema `"additionalProperties": true`（不锁死未来字段，B3 指针消息三元组等扩展不返工契约）；**必填字段集合与枚举锚死**。id 的 `-r<epoch>` rework 后缀（`spec-rework.md:47-48`、`spec-check.md:36-37` 等处的 `${x%%-r[0-9]*}-r$(date +%s)` 模式）属命名约定，**不进契约**（不锁 pattern，只锁 `type:string, minLength:1`）。
- **INV-4（dd-plugin 三道豁免 + 豁免锚）**：dd-plugin work/review/rework（及遗留 deploy 目录）不加 io 段；acceptance 必须带**豁免锚断言（恰 0）**而非只对本 repo 计数——B1 教训：B0 清零断言误伤豁免项，fleet-impl rework input 的 `loop_store_cli` 被误删导致 rework tick 同步死亡，靠 PR #6 回滚 + TC 改豁免白名单才修复（`edb1a85` commit message）。
- **INV-5（单一事实源，防六份拷贝漂移）**：5 份 schema 正本唯一落 `workflows/spec-gen/contracts/`；六工序目录内 `contracts/*.schema.json` 全部为**相对 symlink** 指向正本。acceptance 断言：工序目录下无普通文件拷贝（`! -type l` 计数恰 0）、symlink 恰 13 个且 realpath 全部落在正本目录内。
- **INV-6（fleet template 零改动）**：`contract:` 值为 config_dir 相对字面量路径（不含 `{{占位符}}`），无需 fleet input 注入新变量；`fleet-impl.yaml.tpl` / `fleet-merge.yaml.tpl` / `fleet.yaml.tpl` **零改动**。
- **INV-7（io.out 与 routes 键集合一致）**：每个 workflow 的 `io.out` 键集合 == 该 workflow `routes:` 键集合（出站队列全覆盖，无多无漏）——这是组合期检查（out/in 兼容）能配对的前提。

## 3. 涉及文件与改动精确描述

### 3.1 契约落位与共享机制（设计判断，理由写明）

**engine 侧 contract resolve 语义核对**：design §3.2 定 contract = `config_dir/contracts/*.schema.json`；engine 现有加载器全部以 `join(configDir, rel)` 读文件（`src/loader.ts:62-66` templateLoader、`:73-78` contractLoader、`:85-87` personaLoader），io contract 加载将沿同一 config_dir 相对纪律。六道工序各自的 config_dir 是 `workflows/spec-gen/<工序>/`（`fleet-impl.yaml.tpl:5/29/51/147/168`、`fleet-merge.yaml.tpl:5`），故 schema 文件**必须存在于每个工序目录的 `contracts/` 下**。

**共享机制拍板：正本 + 相对 symlink**。三方案比较：

| 方案 | 否决/采纳理由 |
|---|---|
| 六份实体拷贝 | 否决：同类 record schema 六处漂移是本 spec 要防的第一事故形态（INV-5） |
| `contract: ../contracts/x.schema.json` 越出 config_dir | 否决：依赖 engine 允许路径上溯，engine 侧 B2 spec 未承诺该语义，且违背 config_dir 自包含纪律 |
| **正本目录 + 相对 symlink**（采纳） | 正本唯一（`workflows/spec-gen/contracts/`）；声明路径仍是 config_dir 内相对路径（engine 语义零假设，`readFileSync` 透明穿透 symlink）；git 原生保存 symlink；漂移在 acceptance 用 symlink 完整性锚拦住 |

fallback 备案：若 engine 侧最终实现对 contract 路径做 realpath 沙箱校验（拒绝解析到 config_dir 外），则退化为「生成脚本从正本刷六份拷贝 + acceptance 比对内容哈希一致」；本 spec 按 symlink 实施，fallback 仅在 engine 侧合入后实测不通过时启用（届时以小 spec 跟进，不在本 spec 内预实现）。

### 3.2 新增：`workflows/spec-gen/contracts/`（正本，5 文件）

#### `trigger.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "trigger record",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "status", "spec_file", "feedback"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "status": { "enum": ["open", "done"] },
    "spec_file": { "type": "string", "minLength": 1 },
    "feedback": { "type": "string" },
    "spec_id": { "type": "string" },
    "feedback_file": { "type": "string" },
    "claimed_by": { "type": "string" }
  }
}
```

> status 无 `contract_rejected`：trigger 的消费者是 dd work（豁免，不声明 io.in），claim 入站校验不会发生在 trigger store 上，该店记录进不了 `contract_rejected` 态。这是有意的不对称，见 pr schema 对照。

#### `pr.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "pr record",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "status", "spec_id", "spec_file", "branch", "base_commit"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "status": { "enum": ["ready", "reviewing", "approved", "checking", "ready-to-deploy", "verifying", "ready-to-merge", "merging", "merged", "rejected", "verify_failed", "merge_conflict", "contract_rejected"] },
    "spec_id": { "type": "string", "minLength": 1 },
    "spec_file": { "type": "string", "minLength": 1 },
    "branch": { "type": "string", "minLength": 1 },
    "base_commit": { "type": "string", "minLength": 1 },
    "diff": { "type": "string" },
    "diff_file": { "type": "string" },
    "claimed_by": { "type": "string" }
  }
}
```

> status 枚举全集 13 值的来源：claim 流转 ready→reviewing（`fleet-impl.yaml.tpl:104-105`）、approved→checking（`:153-154`）、ready-to-deploy→verifying（`:176-177`）、ready-to-merge→merging（`fleet-merge.yaml.tpl:14-15`）；complete effect 终态 ready-to-deploy/rejected（`spec-check.md:29,48`）、ready-to-merge/verify_failed（`deploy-verify.md:49,65`）、merged/merge_conflict（`merger.md:70,86`）；approved/rejected 由 dd rework 直调 update 写入（B0 豁免项）；`contract_rejected` = engine B2 claim 拒收态（plan-b2.md B2-1 定案：含 rejected 子串，B1 `/status` anomaly 判定天然捕获）——pr store 被 review/spec-check/deploy-verify/merger 四站 claim，是入站校验的主战场，拒收态必须在枚举内。

#### `verdict.schema.json`（verdict 与 spec-verdict 同形）

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "verdict record (spec-verdict & dd verdict share this shape)",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "status", "spec_id", "verdict", "feedback"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "status": { "enum": ["decided", "reworked", "contract_rejected"] },
    "spec_id": { "type": "string", "minLength": 1 },
    "verdict": { "enum": ["APPROVE", "REJECT"] },
    "feedback": { "type": "string" },
    "spec_file": { "type": "string" },
    "feedback_file": { "type": "string" },
    "pr_id": { "type": "string" },
    "spec_pr_id": { "type": "string" },
    "claimed_by": { "type": "string" }
  }
}
```

> `spec_pr_id`（spec-gen review 变体，persona `spec-reviewer.md:19-21`）与 `pr_id`（dd review 变体，`b1-20260705-135500/stores/verdict/*.json`）均列为可选：同形契约以可选字段覆盖两变体。status 含 `contract_rejected`：spec-verdict store 被 spec-rework（本 spec 声明 io.in）claim。

#### `spec-pr.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "spec-pr record",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "status", "spec_id", "spec_file"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "status": { "enum": ["ready", "reviewing", "contract_rejected"] },
    "spec_id": { "type": "string", "minLength": 1 },
    "spec_file": { "type": "string", "minLength": 1 },
    "claimed_by": { "type": "string" }
  }
}
```

#### `idea.schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "idea record",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "status", "feedback"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "status": { "enum": ["open", "done", "contract_rejected"] },
    "feedback": { "type": "string" },
    "feedback_file": { "type": "string" },
    "spec_file": { "type": "string" },
    "claimed_by": { "type": "string" }
  }
}
```

> `feedback_file` / `spec_file` 可选：种子 idea（`bootstrap-loop.sh:83-93`）无 spec_file、feedback_file 为空串；rework REJECT idea（`spec-rework.md:49-63`）带 spec_file。空串合法（宽进）。

### 3.3 新增：六工序 `contracts/` symlink（恰 13 个）

与各工序 `templates/` 同级建 `contracts/` 目录，内放相对 symlink（`ln -s ../../contracts/<f> workflows/spec-gen/<工序>/contracts/<f>`）：

| 工序 | symlink（→ `../../contracts/` 下正本） |
|---|---|
| draft | idea.schema.json, spec-pr.schema.json |
| review | spec-pr.schema.json, verdict.schema.json |
| rework | verdict.schema.json, trigger.schema.json, idea.schema.json |
| spec-check | pr.schema.json, trigger.schema.json |
| deploy-verify | pr.schema.json, trigger.schema.json |
| merger | pr.schema.json, trigger.schema.json |

### 3.4 六个 workflow.yaml 加 `io:` 段

形状遵 design §3.2：`io: { in: {queue, contract}, out: {<queue名>: contract} }`。`in.queue` 是逻辑队列名 = 上游 out 的队列名（组合期配对锚，非 store 路径）；`contract` 是 config_dir 相对路径字面量（无占位符，INV-6）。

#### `workflows/spec-gen/draft/workflow.yaml`（routes 在 :12-13，io 插在 routes 之后、`seed:`（:14）之前）

```yaml
io:
  in: { queue: idea, contract: contracts/idea.schema.json }
  out:
    spec-pr: contracts/spec-pr.schema.json
```

#### `workflows/spec-gen/review/workflow.yaml`（routes :12-13，io 插在 :13 与 `seed:`（:14）之间）

```yaml
io:
  in: { queue: spec-pr, contract: contracts/spec-pr.schema.json }
  out:
    verdict: contracts/verdict.schema.json
```

#### `workflows/spec-gen/rework/workflow.yaml`（routes :4-6，io 插在 :6 与 `seed:`（:7）之间）

```yaml
io:
  in: { queue: verdict, contract: contracts/verdict.schema.json }
  out:
    trigger: contracts/trigger.schema.json
    idea: contracts/idea.schema.json
```

#### `workflows/spec-gen/spec-check/workflow.yaml`（routes :4-5，io 插在 :5 与 `seed:`（:6）之间）

```yaml
io:
  in: { queue: pr, contract: contracts/pr.schema.json }
  out:
    trigger: contracts/trigger.schema.json
```

#### `workflows/spec-gen/deploy-verify/workflow.yaml`（routes :4-5，同上位置）

```yaml
io:
  in: { queue: pr, contract: contracts/pr.schema.json }
  out:
    trigger: contracts/trigger.schema.json
```

#### `workflows/spec-gen/merger/workflow.yaml`（routes :4-5，同上位置）

```yaml
io:
  in: { queue: pr, contract: contracts/pr.schema.json }
  out:
    trigger: contracts/trigger.schema.json
```

> 组合期兼容的免费性质：review.out[verdict] 与 rework.in 引用**同一份正本**（symlink 汇聚），draft.out[spec-pr] 与 review.in 同理，rework.out[idea] 与 draft.in 同理——「兼容 = schema 深度相等」在共享正本下恒真，六道工序间零配对风险。pr/trigger 的对侧（dd work）豁免无契约，组合检查按 opt-in 语义跳过。

### 3.5 `tests/acceptance.sh` 接线

- 文件存在性 `check` 清单（:14-33 现有段）追加 5 个正本文件路径。
- 在 enqueue-routes/complete-effect 测试块（:605-621）之后追加同构块，调用新测试文件：

```bash
# --- pipeline-contracts static tests (SPEC-003-b2-pipeline-contracts) ---
echo "running pipeline-contracts static tests"
if bash "$ROOT/tests/pipeline-contracts.test.sh"; then
  echo "ok: pipeline-contracts tests passed"
else
  echo "FAIL: pipeline-contracts tests failed" >&2
  fail=1
fi
```

### 3.6 新建 `tests/pipeline-contracts.test.sh`

bash 静态测试（不调 LLM、不跑 drain）。头部沿用 acceptance.sh 纪律：`set -euo pipefail`、`ROOT` 定位、`ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"`；**ajv 取自 engine 依赖树**（engine `package.json` dependencies 已含 `ajv@^8.20.0`，本 repo 保持零依赖），guard 纪律镜像 acceptance.sh:38-39：`[ -d "$ENGINE_ROOT/node_modules/ajv" ]` 不满足则 SKIP（stderr 提示 build/install engine）。ajv 编译方式（拍板「node -e 方式」，非引擎 CLI——引擎 CLI 无 schema 编译子命令）：

```bash
ENGINE_ROOT="$ENGINE_ROOT" node -e '
const { createRequire } = require("node:module");
const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
const Ajv = req("ajv");
const ajv = new Ajv({ allErrors: true });   // 与 engine src/output-contract.ts:101 同参
const schema = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
ajv.compile(schema);                         // 编译失败即抛错退出非 0
' "$schema_file"
```

TC 内容见 §4。

## 4. 测试要求

### RED 场景列表（tests/pipeline-contracts.test.sh）

1. **TC-1（io 段计数锚，恰 6）**：`grep -l '^io:' "$ROOT"/workflows/spec-gen/*/workflow.yaml | wc -l` 恰为 6（当前为 0，红）。
2. **TC-2（正本齐全，恰 5）**：`workflows/spec-gen/contracts/` 下 `*.schema.json` 恰 5 个，文件名集合 == {idea, spec-pr, verdict, trigger, pr}。
3. **TC-3（ajv 全部可编译）**：5 份正本逐一用 §3.6 snippet 编译，全部退出 0。
4. **TC-4（好记录通过）**：内嵌 fixture（从 §1.5 实况样本裁剪，每类 1 例，含 trigger 的 `-r<epoch>` 后缀 id 变体与 verdict 的 pr_id/spec_pr_id 两变体）经对应 schema `validate()` 通过。
5. **TC-5（坏记录被拒，≥4 例）**：① pr 记录 `status:"bogus"`（枚举外）被拒；② trigger 记录缺 `spec_file`（必填缺失）被拒；③ verdict 记录 `verdict:"MAYBE"` 被拒；④ idea 记录 `id:""`（minLength）被拒。
6. **TC-6（宽进回归，INV-3）**：带未知字段的 pr 记录（如 `{"repo":"x","commit":"y"}` 混入——B3 指针消息前瞻字段）**通过**校验（additionalProperties:true 生效）。
7. **TC-7（symlink 完整性，INV-5）**：`find workflows/spec-gen/*/contracts -name '*.schema.json' -type l | wc -l` 恰 13；`! -type l` 同范围计数恰 0；每个 symlink `realpath` 存在且位于 `workflows/spec-gen/contracts/` 目录下。
8. **TC-8（io/routes 键集合一致，INV-7）**：用 engine 依赖树的 `yaml` 包（`createRequire` 同 §3.6 方式）解析六 workflow.yaml，逐个断言 `Object.keys(io.out).sort() == Object.keys(routes).sort()`，且 `io.in.queue`/`io.in.contract` 非空、所有 contract 路径以 `contracts/` 开头。
9. **TC-9（豁免锚，恰 0，INV-4）**：`grep -l '^io:' "$DD_PLUGIN_ROOT"/workflows/spec/*/workflow.yaml 2>/dev/null | wc -l` 恰为 0（`DD_PLUGIN_ROOT` 缺省 `/data/code/self/loop-engine-dev-dispatch-plugin`；目录不可用则 SKIP 该条并 stderr 声明）。豁免依据注释进测试体：design §2 B2 行「自举六道工序」不含 dd 三道；B1 教训 PR #6（清零断言误伤豁免）。

### 组合场景断言

- **INV-1 回归（旧引擎剥离容忍）**：acceptance.sh 既有 fleet-impl/fleet-merge `loadFleetManifest` 校验（:78-124）在加 io 段后必须依旧全绿——即当前 engine dist（无 io 支持）加载带 io 段的 workflow 不报错（zod 剥离语义实证）。不新写 TC，以「现有全部 TC 零回归」承载。
- **INV-2 断言**：`git diff --name-only` 范围检查写进 impl-plan 自检（templates/personas 零触碰）；acceptance 层以既有 state-flow 七场景（spec-rework/spec-check/deploy-verify/merger 全路径）零回归承载。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（含新增 pipeline-contracts 块与既有全部 TC 零回归）。
- grep 计数锚（在 plugin repo 根执行）：
  ```bash
  grep -l '^io:' workflows/spec-gen/*/workflow.yaml | wc -l                      # 预期 6
  ls workflows/spec-gen/contracts/*.schema.json | wc -l                          # 预期 5
  find workflows/spec-gen/*/contracts -name '*.schema.json' -type l | wc -l      # 预期 13
  find workflows/spec-gen/*/contracts -name '*.schema.json' ! -type l | wc -l    # 预期 0
  grep -l '^io:' /data/code/self/loop-engine-dev-dispatch-plugin/workflows/spec/*/workflow.yaml 2>/dev/null | wc -l   # 预期 0（豁免锚）
  git diff --name-only master -- 'workflows/spec-gen/*/templates/*' 'workflows/spec-gen/*/personas/*' 'workflows/*.tpl' | wc -l  # 预期 0（INV-2/INV-6）
  ```

## 6. 豁免清单

| 豁免项 | 范围 | 依据 | 锚 |
|---|---|---|---|
| dd-plugin 三道（work/review/rework）+ 遗留 deploy 目录 | `/data/code/self/loop-engine-dev-dispatch-plugin/workflows/spec/*/workflow.yaml` 不加 io 段 | 第三 repo，design §2 B2 行范围 =「自举六道工序」；dd 三道的契约化随其自身 roadmap | TC-9 豁免锚（恰 0）+ 注释写明依据。**豁免必须配保留断言**（B1 教训 PR #6：清零断言误伤豁免项） |
| dd work 产 pr / dd review 产 verdict 的**出站**无契约 | pr/trigger/verdict 的 dd 侧生产端 | 同上；本 spec 的 pr/verdict schema 仍拦住这些记录的**入站**（spec-gen 四站 claim 时校验），坏记录不因生产端豁免而漏网 | 由 engine 侧 claim 校验承载，非本 repo TC |

# References
- 设计 SSoT：`../../design.md` §2 B2 行 + §3.2 io 契约草形（用户 2026-07-04 拍板）
- recon 定案：`../../plan-b2.md` Task B2-1（contract_rejected 命名、六道范围、ajv 零新依赖）
- 动机活体：`../../progress.md` 2026-07-04 23:31（SPEC-168 三重不一致）、`../../acceptance-b1.md`（SPEC-169 parse_failed）、`../../findings.md`「先 complete trigger 后 push」条目
- engine 签名核对（main=944c3af）：`src/types.ts:100-106`（Workflow 非 strict）、`src/loader.ts:62-87`（config_dir 相对加载纪律）、`src/output-contract.ts:101`（ajv 同参先例）、`src/fleet.ts:117`（claim 点）、`package.json` dependencies（ajv ^8.20.0 / yaml ^2.5.0）
- plugin 实况核对（master=edb1a85）：六 workflow.yaml、`fleet-impl.yaml.tpl:14-187`、`fleet-merge.yaml.tpl:12-25`、`tests/acceptance.sh:9,38-39,605-621`
- record 实况样本：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/{trigger,pr,verdict}/`、`~/.loop-engine/bootstrap/20260704-131809/stores/{idea,spec-pr,spec-verdict}/`
- B1 豁免锚教训：plugin PR #6（`edb1a85` fix: fleet-impl rework input 恢复 loop_store_cli + TC-12 改豁免白名单）
