# SPEC-007: B4 输入原语锚集 —— dd 收编收账 + .dd-review 正名 + 裸路径北极星机器化

> 批次：组件模型 B4（PROP-2 输入原语：消灭自由路径 + 收编 B0/B3 豁免洞）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`，基线 master@33939fc）
> 依赖：**dd-plugin PR #4 已合入**（`/data/code/self/loop-engine-dev-dispatch-plugin` master@3838d72——work/review triplet 条件透传、rework REJECT enqueue 化 + routes.trigger、pr status update 豁免保留）。本 spec **零 dd repo 改动**，只在本 repo 落锚收账。engine 侧零依赖（provenance/journal 归 engine SPEC-175，另线并行）。
> 定案来源：`../../design.md` §2 B4 行（验收：grep template/persona 无裸路径）+ PROP-2 原文（`../../../loop-engine-概念梳理-问题清单/issues.md:43-53`）+ `../../plan-b4.md` 定案段（2026-07-06 00:02）+ 用户范围拍板（2026-07-05，偏离 plan-b4 处见 §2 备案）。

## 1. 背景

### 1.1 PROP-2 两类输入（issues.md:47-51 锁死，不得偏离）

1. **注入的数据**（小而关键的结构化输入：spec 正文 / verdict / feedback / 目标）→ Queue record / Context key / `{{deps}}`，**内容入账**；
2. **供给的资源**（大而探索性：代码库）→ 不搬内容，钉资源：`workspace: {repo, commit}` 声明式版本化，**版本入账**；
- 统一表述：**每个输入要么是注入的数据（内容入账）、要么是供给的资源（版本入账），唯独不许 prompt 文案里出现自由路径。**

B4 recon 定案（plan-b4 2026-07-06 00:02）：占位符注入已是两 repo 模板的主流形态；唯一硬编码约定 `.dd-review/` **保留并正名**（见 §3.2）；journal 版本入账走 engine SPEC-175；本 spec 承担 plugin 侧全部**锚集**——把 B4 的收编事实固化成机器可查的回归断言。

### 1.2 B0 豁免演进史（put 收编 / update 保留）

dd-plugin spec 模式三柱（work/review/rework）自 B0 起是显式豁免区（b0-inventory 定案，`fleet-impl.yaml.tpl:135-137` 注释为活体）。豁免项两类，命运在 B4 分叉：

| 豁免项 | B0~B3 状态 | B4 处置（dd PR #4） |
|---|---|---|
| dd rework REJECT `store-cli put` 直投 trigger | 洞（不经 routes/契约闸门；SPEC-005 §6 记录在案） | **收编**：改 enqueue effect + workflow.yaml `routes.trigger`（`rework.md:48-63`、`rework/workflow.yaml:7-8`） |
| dd rework APPROVE/REJECT 的 pr status `update`（`rework.md:43,45`） | 豁免 | **保留**：跨 store status 推进，引擎无对应 effect（complete 只推进认领柱自己 claim 的记录）；豁免依据已写注释（`rework/workflow.yaml:4-6`） |
| dd work/review 产 pr/verdict 无 triplet | 豁免（SPEC-005 INV-2/INV-6） | **收编**：条件透传——`{{repo?}}` 等可选占位符 + 「空则整键省略」指令锚（`work.md:51-53,63`、`review.md:39-41,51`） |
| dd deploy redo `put` 直投（`deploy.md:69`） | 洞（遗留柱） | **不动**（非 B4 收编面，bootstrap 主链用本 repo 的 deploy-verify，dd deploy 仅 dd 独立模式消费）——本 spec 配保留锚记账 |

### 1.3 动机活体：acceptance 现红（起草时亲测）

dd PR #4 合入当刻，本 repo `bash tests/acceptance.sh` **即红**：`pointer-consumption.test.sh:97-115` 的 TC-D1 断言 dd 四模板 triplet 占位符**恰 0**，现值 **9**（work/review/rework 各 3）。这正是 B1 PR #6（edb1a85）确立的纪律的镜像面：**豁免消失时，豁免锚必须同步翻转**——翻转义务落在持锚的 repo，本 spec 即该义务的载体（地位等同 SPEC-005 §3.8 的存量 fixture 迁移：不做则 acceptance 假红，验收命令无法成立）。

### 1.4 本 spec 的分工边界

| 半边 | 归属 |
|---|---|
| dd 侧模板/workflow.yaml 改动（透传、enqueue 化、注释） | **dd PR #4（已完成，本 spec 只读）** |
| journal provenance（workspace commit + 消费指针入账） | **engine SPEC-175（另线）** |
| 本 repo：TC-D1 豁免锚迁移 + dd 收编锚集 + `.dd-review` 正名（verdict schema description）+ 裸路径北极星 TC + pr optional 防手滑锚 + dd rework fixture 回归 TC | **本 spec** |

## 2. 不变量（INV）

- **INV-1（dd repo 只读）**：本 spec 全部改动落 bootstrap repo；dd-plugin repo（`DD_PLUGIN_ROOT` 缺省 `/data/code/self/loop-engine-dev-dispatch-plugin`）零改动，TC 对其只做 grep/渲染只读访问。dd 侧不可用时相关 TC 走 SKIP（镜像 `pointer-consumption.test.sh:97-98` 纪律），不 FAIL。
- **INV-2（pr triplet 保持 optional——观察升级备案，偏离 plan-b4 定案）**：plan-b4 定案文本为「pr schema triplet 升 required（dd 收编后成立）」，用户 2026-07-05 重新拍板：**dd work 是 LLM 节点，triplet echo 是模板指令依从性而非机器保证，需观察一批（B4）真实投喂的依从率，稳定后 B5/B6 升 required**。故本批 pr.schema.json **零改动**；防手滑双锚：pointer-records TC-1（`tests/pointer-records.test.sh:56-60` 已有）+ 本 spec TC-7 各自独立断言 `pr.required` 不含 triplet——升 required 是显式三处同批操作（pr.schema required + 两处 TC），改一漏一必红。
- **INV-3（verdict schema 演进 = description-only）**：`verdict.schema.json` 只给 `feedback_file` 追加 `description`（§3.2 逐字）；`required` / `verdict.enum` / `status.enum` / `additionalProperties: true` 逐字不变——ajv 校验行为零变化，**全仓 fixture 零迁移**（TC-5 反向断言防顺手改形状）。
- **INV-4（豁免翻转必同步改锚——PR #6 镜像纪律）**：TC-D1 的 dd triplet 恰 0 锚随收编**翻转**为「deploy 恰 0 + work/review/rework 各恰 3（可选形态）」；所有**残留**豁免（deploy put 直投、rework update 恰 2、fleet tpl loop_store_cli 恰 1、pr triplet optional、dd 柱零 io）一律配保留断言，禁只删不改。
- **INV-5（fleet tpl rework loop_store_cli 豁免有意保留——偏离 plan-b4 定案）**：plan-b4 定案文本为「fleet tpl rework input 去 loop_store_cli + TC-12 恰 1→恰 0」，用户重新拍板保留：dd rework 的 update 豁免延续（INV-4 表），模板仍消费 `{{loop_store_cli}}`——去掉 input 即 B1 Wave1 事故重演（占位符解析失败，tick 同步死亡，`fleet-impl.yaml.tpl:135-137` 注释活体）。`complete-effect.test.sh:467-489` 的 TC-12 恰 1 锚**逐字不动**；本 spec 在 §6 记账「有意保留非遗漏」。
- **INV-6（裸路径口径钉死）**：北极星 grep 口径为两段管道（§3.4 逐字）：raw 段 `/(data|home|tmp|usr|var)/` 抓一切系统绝对路径前缀；排除段以 `-oE` token 化后滤掉 `}}` / `$` 前缀（`{{workspace_repo}}/.dd-review/`、`"$repo"/tmp/x` 等**变量根**合法形态）。亲核实况（2026-07-05，master@33939fc / dd@3838d72）：两 repo 全部 templates + personas + fleet tpl 连 **raw 段都恰 0**——排除段是前向防御非现状需要，TC 落全管道口径防未来误伤。
- **INV-7（bootstrap 零触碰清单）**：六工序模板与 personas、`trigger/spec-pr/pr/idea.schema.json` 四正本、13 个 symlink 的链接结构、两 fleet tpl、`bin/*`、五 workflow.yaml——全部零触碰（本 spec 只动 `verdict.schema.json` 正本一处 + 两个测试文件 + acceptance 接线）。
- **INV-8（dd 柱零 io 声明现状不变——执法面备案）**：dd 三 workflow.yaml 仍无 `io:` 段（`pipeline-contracts.test.sh:276-296` TC-9 恰 0 锚不动）。dd rework re-seed 的 trigger 出站**无契约执法面**（enqueue 出站校验挂在发出方 io.out 上）——triplet 闭环由 review echo + 模板「空则省略」纪律 + 本 spec TC-8/9 fixture 固化保障；「dd 柱补 io 声明」列范围外候选（dd 自有 roadmap，见 §6）。

## 3. 涉及文件与改动精确描述

### 3.1 存量锚迁移：`tests/pointer-consumption.test.sh` TC-D1（修当前红，最先做）

D 组（:97-115）改动：

1. `dd_tpls` glob（:101）从 `{work,review,deploy,rework}` **缩至 `{deploy}`**——triplet 恰 0 锚只对未收编的 deploy 柱继续成立；
2. `{{spec_file}}` 保留断言（:105-109）**维持四模板全量**（glob 单列 `{work,review,deploy,rework}` 不变）——spec_file 派生物化字段本批不收编（§6）；
3. 段头注释（:93-95）追加一行：`# B4 收编（SPEC-007）：work/review/rework 已透传 triplet，恰 0 锚缩至 deploy；收编面的恰 3 锚移交 tests/input-primitives.test.sh TC-2。`

不动 A/B/C 组任何断言。迁移后 `bash tests/pointer-consumption.test.sh` 必须全绿（当前红的唯一来源即 TC-D1，起草时亲测）。

### 3.2 `.dd-review` 正名：`workflows/spec-gen/contracts/verdict.schema.json`

`feedback_file` property（:14）演进为（description 逐字）：

```json
"feedback_file": { "type": "string",
  "description": "reviewer 详细反馈的物化文件路径。约定通道：workspace 内 .dd-review/（dd review.md:19-23 指令产生，为绕 CLI 长 result 截断而生），经本字段注入下游引用——PROP-2「注入的数据」合规形态：路径值由 record 字段携带入账，模板经 {{feedback_file?}} 占位符消费，不属 prompt 文案自由路径。" }
```

symlink 网络零触碰：verdict 正本被 `review/contracts` 与 `rework/contracts` 两处 symlink 指向（13 个 symlink 之二），演进自动透传。idea/trigger/spec-pr/pr 四正本零改动（INV-7）。

### 3.3 新建 `tests/input-primitives.test.sh`

头部纪律镜像 `pointer-consumption.test.sh:15-24`：`set -euo pipefail`、`ROOT`、`ENGINE_ROOT` 缺省、`DD_PLUGIN_ROOT` 缺省 `/data/code/self/loop-engine-dev-dispatch-plugin`、**`LOOP_STORE_CLI` 自带缺省 `${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}`**（对齐 `acceptance.sh:77`；修正 pointer-consumption:185 裸用环境变量、standalone 跑不了的纪律缺口）。静态 TC（TC-1~TC-7）不需 ajv；行为 TC（TC-8~TC-10）需 `$ENGINE_ROOT/dist/template.js` 与 store-cli，缺则 SKIP。dd 侧 `$DD_PLUGIN_ROOT/workflows/spec` 缺则 TC-1~TC-4、TC-6 的 dd 半边与 TC-8~TC-10 全部 SKIP（INV-1）。

`render_template` helper 逐字镜像 `pointer-consumption.test.sh:138-157`（engine `fill`；ctx 以空白切分——**fixture 值一律无空格 token**）。TC 见 §4。

### 3.4 裸路径北极星口径（TC-6 内嵌，口径写进 TC 注释逐字）

```bash
# 北极星（design §2 B4 行）：grep template/persona 无裸路径。
# 口径两段：raw 段抓系统绝对路径前缀；-oE token 化后排除段滤掉变量根
# （}} 或 $ 前缀：{{workspace_repo}}/.dd-review/、"$repo"/tmp/x 合法）。
# 亲核 2026-07-05（master@33939fc / dd@3838d72）：raw 段即恰 0，排除段为前向防御。
np_hits() {
  grep -roE '[^[:space:]]*/(data|home|tmp|usr|var)/[^[:space:]]*' "$@" 2>/dev/null \
    | grep -vE '(\}\}|\$)' | wc -l | tr -d ' '
}
```

作用面：

| repo | 文件集 |
|---|---|
| bootstrap | `workflows/spec-gen/*/templates/*.md`、`workflows/spec-gen/*/personas/*.md`（draft/review 两处 persona）、`workflows/*.tpl`（3 个 fleet tpl，加严件：manifest 里 `${LOOP_STORE_CLI}` 等 env 展开形态被排除段放行） |
| dd（spec 模式） | `$DD_PLUGIN_ROOT/workflows/spec/*/templates/*.md`、`$DD_PLUGIN_ROOT/workflows/spec/{work,review}/personas/*.md`（rework/deploy 无 personas 目录，**glob 必须显式列存在路径**，防 nullglob 缺省下字面展开报错） |

dd 的 deterministic/live 两模式不进 TC 作用面（dd 自有 roadmap，非 bootstrap 验收面）；亲核记录：其全树现状同为 0，B5/B6 扩面时零迁移成本。

### 3.5 `tests/acceptance.sh` 接线

- check 清单（:14-41 段末，`bin/spec-inject.sh` 行后）追加 `check "tests/input-primitives.test.sh"`；
- pointer-consumption 调用块（:651-658）之后追加同构块：

```bash
# --- input-primitives tests (SPEC-007-b4-input-primitives-anchors) ---
echo "running input-primitives tests"
if bash "$ROOT/tests/input-primitives.test.sh"; then
  echo "ok: input-primitives tests passed"
else
  echo "FAIL: input-primitives tests failed" >&2
  fail=1
fi
```

### 3.6 亲核落定：dd 实况锚清单（master@3838d72，逐处行号）

本 spec 全部 dd 侧断言依据（起草时逐处亲核，实现时不得信本表以外的旧快照）：

| 锚 | 位置 | 现值 |
|---|---|---|
| `Pointer passthrough rule` 指令 | `spec/work/templates/work.md:63`、`spec/review/templates/review.md:51` | 恰 2 文件、各恰 1 处 |
| triplet 可选占位符 | `work.md:51-53`、`review.md:39-41`、`rework.md:29-40`（heredoc） | 各模板恰 3 |
| workflow.yaml payload 可选形态 | `work/workflow.yaml:27-29`、`review/workflow.yaml:26-28`、`rework/workflow.yaml:25-27` | 各恰 3 |
| rework routes 正门 | `rework/workflow.yaml:7-8`（`routes:` + `trigger: "{{trigger_store_dir}}"`） | 在场 |
| rework update 豁免 | `rework.md:43`（approved）、`rework.md:45`（rejected） | 恰 2，APPROVE/REJECT 各 1 |
| update 豁免依据注释 | `rework/workflow.yaml:4-6`（含「引擎无对应 effect」） | 在场 |
| rework put 直投 | `rework.md` 仅 :48 **注释**提及（`# …不再 store-cli put 直投…`）——去注释行后恰 0 | 恰 0 |
| rework enqueue 出口 | `rework.md:62`（`op: "enqueue", queue: "trigger"`） | 恰 1 |
| deploy put 直投残留 | `deploy.md:69`（`node "$loop_store_cli" "$trigger_store_dir" put`） | 恰 1（§6 豁免） |
| deploy triplet 占位符 | `deploy.md` | 恰 0 |

## 4. 测试要求

### TC 列表（tests/input-primitives.test.sh）

1. **TC-1（dd 收编指令锚）**：`grep -rlF 'Pointer passthrough rule' "$DD_PLUGIN_ROOT"/workflows/spec/*/templates/*.md | wc -l` 恰 **2**；work.md 与 review.md 各 `grep -cF` 恰 1；rework.md、deploy.md 恰 0（rework 是 bash 模板，「空则省略」逻辑在 node 代码里不在指令文案里——防锚漂移到错误载体）。
2. **TC-2（dd triplet 通道形态锚，恰 N 全配依据）**：对 work.md / review.md / rework.md 三模板：可选形态 `grep -Ec '\{\{(repo|commit|spec_path)\?\}\}'` 各恰 **3**；必填形态 `grep -Ec '\{\{(repo|commit|spec_path)\}\}'` 各恰 **0**（必填占位符缺值 = tick 同步死亡，B1 PR #6 教训——上游 pr/verdict 无契约保证 triplet 在场，INV-2）。deploy.md 两形态各恰 0。三 workflow.yaml（work/review/rework）payload 可选形态各恰 **3**（双层通道齐备，缺一层模板拿不到值——SPEC-005 §1.5 机制）。
3. **TC-3（dd rework 正门 + update 豁免保留锚）**：`rework/workflow.yaml` 含 `routes:` 段且 `grep -qE '^\s+trigger: "\{\{trigger_store_dir\}\}"'`；注释锚 `grep -q '引擎无对应 effect'` 在场。`rework.md`：去注释后零 put——`grep -vE '^[[:space:]]*#' | grep -cE '(store-cli|store_cli).*[[:space:]]put[[:space:]]'` 恰 **0**（:48 注释行提及 put 属豁免史记录，必须先滤注释——口径依据 §3.6）；enqueue 出口 `grep -cF 'op: "enqueue", queue: "trigger"'` 恰 **1**；update `grep -cE '"\$loop_store_cli" "\$pr_store_dir" update'` 恰 **2**，且含 `"approved"` 与 `"rejected"` 的 update 行各恰 1（APPROVE/REJECT 各一，豁免依据：跨 store status 推进引擎无对应 effect）。
4. **TC-4（dd deploy 残留豁免保留锚）**：`deploy.md` 的 `grep -cE '"\$loop_store_cli" "\$trigger_store_dir" put'` 恰 **1** + triplet 占位符恰 0（§6 豁免项，恰 1 消失即说明有人动了豁免区——INV-4 禁只删不改）。
5. **TC-5（`.dd-review` 正名锚）**：node 断言 `verdict.schema.json` 的 `properties.feedback_file.description` 非空且含子串 `.dd-review`；**反向零漂移**：`required` 逐字 `["id","status","spec_id","verdict","feedback"]`、`additionalProperties === true`、`verdict.enum` 逐字 `["APPROVE","REJECT"]`（INV-3 description-only）。symlink：`find workflows/spec-gen/*/contracts -name 'verdict.schema.json' -type l | wc -l` 恰 **2**；全网络 `-name '*.schema.json' -type l | wc -l` 仍恰 **13**。
6. **TC-6（裸路径北极星，恰 0）**：§3.4 口径逐字落地，bootstrap 文件集与 dd spec 模式文件集分别断言 `np_hits` 恰 **0**；dd 侧不可用走 SKIP。
7. **TC-7（pr optional 防手滑锚）**：node 断言 `pr.schema.json` 的 `required` 逐字 `["id","status","spec_id","spec_file","branch","base_commit"]`（不含 triplet 三键）——与 pointer-records TC-1 互为双锚（INV-2：B5/B6 升 required 时两 TC + schema 三处同批改）。
8. **TC-8（rework REJECT 带 triplet：re-seed 闭环，行为 fixture）**：mktemp 下自建 pr store + trigger store；`store-cli put` 一条 pr 记录 `{"id":"pr-SPEC-990","status":"reviewing","spec_id":"SPEC-990","spec_file":"<fixture 绝对路径>","branch":"dd/SPEC-990","base_commit":"<hex40>"}`；render_template 渲染 `$DD_PLUGIN_ROOT/workflows/spec/rework/templates/rework.md`，ctx：`loop_store_cli/trigger_store_dir/pr_store_dir/pr_id=pr-SPEC-990/spec_id=SPEC-990/spec_file=<同上>/verdict=REJECT/feedback=badwork/feedback_file=/repo=<fixture repo 绝对路径>/commit=<hex40>/spec_path=docs/specs/SPEC-990.md`（值全部无空格 token）；bash 执行后断言：
   - envelope `effects[0]` 为 `op==="enqueue" && queue==="trigger"`；
   - `task.id` 匹配 `^SPEC-990-r[0-9]+$`（redo 链模式，SPEC-005 INV-4 沿用）；
   - `task.repo/commit/spec_path` 与 ctx 逐字相等（verdict 链经 review echo 的 triplet 原值继承）；
   - trigger store 目录 json 数恰 **0**（enqueue 是 effect 声明非直投——正门收编的行为证明）；
   - pr 记录 `status === "rejected"`（update 豁免真实生效，与 TC-3 静态锚互证）。
9. **TC-9（rework REJECT 不带 triplet：省略语义）**：同构 fresh store/记录，ctx 的 `repo=/commit=/spec_path=` 置空；断言 task **无** repo/commit/spec_path 三键（`"repo" in task === false` 等），且键集合逐字恰 `{feedback, feedback_file, id, spec_file, status}`（排序后比对）——「空则整键省略、禁空串」指令的机器固化（空串会撞 trigger.schema 的 `minLength/pattern`）。
10. **TC-10（rework APPROVE 回归）**：ctx `verdict=APPROVE`；断言 `effects[0].op === "halt"`、pr 记录 `status === "approved"`、trigger store 恰 0——dd PR #4 operator 冒烟五断言的固化收尾。

### RED 纪律（本 spec 的特殊形态）

本 spec 主体是**收账锚**：dd 侧行为已实现，TC-1~TC-4、TC-6~TC-10 写完即绿。RED 证明改为两条：

- **真红**：TC-5（verdict description 未加前红）+ acceptance 全量（TC-D1 迁移前红，count=9 起草时亲测）——两处天然 RED 承载 TDD 序；
- **注错自证**：对写完即绿的回归 TC（TC-8~TC-10 为主），落地时**故意注错一次断言期望值**（如 `task.id` 正则改错）跑红，确认 harness 真执行到该断言，再改回——防「永绿断言」假保护（写进 impl-plan 步骤，逐 TC 记录）。

### 组合场景断言

- TC-8 即组合场景：指针 triplet（B3）× enqueue 正门（B0）× redo 链（`-r<epoch>`）× update 豁免（B0 残留）四机制同 fixture 交汇。
- 迁移后全套件互证：`pointer-consumption.test.sh` 全绿（TC-D1 翻转完整）+ `complete-effect.test.sh` 全绿（TC-12 恰 1 未被误伤）+ `pipeline-contracts.test.sh` 全绿（TC-9 dd 零 io 未被误伤、verdict fixture 零迁移即 INV-3 的行为证明）。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（新增 input-primitives 块 + TC-D1 迁移后 pointer-consumption 恢复绿 + 既有全部 TC 零回归）。
- grep 计数锚（plugin repo 根执行，DD=dd repo 根）：
  ```bash
  grep -rlF 'Pointer passthrough rule' $DD/workflows/spec/*/templates/*.md | wc -l   # 恰 2
  grep -Ec '\{\{(repo|commit|spec_path)\?\}\}' $DD/workflows/spec/work/templates/work.md      # 恰 3（review.md / rework.md 同）
  grep -vE '^[[:space:]]*#' $DD/workflows/spec/rework/templates/rework.md | grep -cE '(store-cli|store_cli).*[[:space:]]put[[:space:]]'   # 恰 0
  grep -cE '"\$loop_store_cli" "\$pr_store_dir" update' $DD/workflows/spec/rework/templates/rework.md   # 恰 2
  grep -cE '"\$loop_store_cli" "\$trigger_store_dir" put' $DD/workflows/spec/deploy/templates/deploy.md # 恰 1（豁免保留）
  node -p 'JSON.parse(require("fs").readFileSync("workflows/spec-gen/contracts/verdict.schema.json","utf8")).properties.feedback_file.description.includes(".dd-review")'   # true
  grep -c '^      loop_store_cli: ${LOOP_STORE_CLI}$' workflows/fleet-impl.yaml.tpl   # 恰 1（TC-12 锚不动）
  find workflows/spec-gen/*/contracts -name '*.schema.json' -type l | wc -l           # 恰 13
  ```
- 北极星实测（§3.4 口径两文件集各恰 0）。
- 零改动清单自检：`git diff --name-only` 恰 4 文件（`verdict.schema.json`、`tests/pointer-consumption.test.sh`、`tests/input-primitives.test.sh` 新增、`tests/acceptance.sh`）；dd repo `git -C $DD status --porcelain` 空。

## 6. 豁免清单（B4 后余量，全部配保留断言）

| 豁免项 | 范围 | 依据 | 锚 |
|---|---|---|---|
| dd deploy redo `put` 直投 | `deploy.md:69` | 遗留柱非 B4 收编面（bootstrap 主链走本 repo deploy-verify）；B5+ 候选 | TC-4 恰 1 + triplet 恰 0 |
| dd rework pr status `update` | `rework.md:43,45` | 跨 store status 推进，引擎无对应 effect（complete 只覆盖认领记录本身） | TC-3 恰 2 + 注释锚「引擎无对应 effect」 |
| fleet-impl rework input `loop_store_cli` | `fleet-impl.yaml.tpl:137` | update 豁免的消费通道；去掉 = B1 Wave1 tick 同步死亡重演。**有意保留非遗漏（偏离 plan-b4，用户拍板）** | complete-effect TC-12 恰 1（不动） |
| pr triplet optional | `pr.schema.json` | LLM echo 依从性观察批（B4），B5/B6 升 required（INV-2 三处同批） | TC-7 + pointer-records TC-1 双锚 |
| dd 三柱零 `io:` 声明 | dd 三 workflow.yaml | dd 自有 roadmap；rework 出站无执法面由 fixture TC 补位（INV-8） | pipeline-contracts TC-9 恰 0（不动） |
| `spec_file` 派生字段 | 四 schema + dd 四消费点 | 本批不收编（消费仍走物化缓存路径）；PROP-2 关账后评估 | TC-D1 的 `{{spec_file}}` 保留断言（四模板全量，不缩） |

# References
- 设计 SSoT：`../../design.md` §2 B4 行（验收：grep template/persona 无裸路径；journal 可答版本——后者归 engine SPEC-175）；PROP-2 原文 `../../../loop-engine-概念梳理-问题清单/issues.md:43-53`（两类输入 + 唯独不许自由路径，用户 2026-07-04 提案 + agent 边界修正）
- 批次定案：`../../plan-b4.md` 定案段（2026-07-06 00:02）；用户范围拍板 2026-07-05（pr optional 保持 / TC-12 不动 两处偏离 plan-b4，INV-2/INV-5 备案）
- dd 收编实况（master@3838d72，PR #4）：`work.md:51-53,63`、`review.md:19-23,39-43,51`、`rework.md:29-48,43,45,62`、`rework/workflow.yaml:4-8,25-27`、`work/workflow.yaml:27-29`、`review/workflow.yaml:26-28`、`deploy.md:69`
- 本 repo 实况（master@33939fc）：`pointer-consumption.test.sh:97-115`（TC-D1 现红 count=9 亲测）、`pointer-records.test.sh:56-60`（TC-1 pr required 锚）、`complete-effect.test.sh:467-489`（TC-12）、`pipeline-contracts.test.sh:276-296`（TC-9）、`verdict.schema.json:14`、`acceptance.sh:14-41,54,77,213-232,651-658`、`fleet-impl.yaml.tpl:135-137`
- 裸路径亲核：2026-07-05 两 repo 全 templates/personas/tpl raw grep `/(data|home|tmp|usr|var)/` 恰 0（含 dd deterministic/live 全树）
- 豁免锚教训：plugin PR #6（edb1a85，清零断言误伤豁免项——本 spec INV-4 的镜像义务来源）；B1 Wave1 loop_store_cli 事故（fleet-impl 注释活体）
- `.dd-review` 通道起源：dd commit dcc1113（reviewer 详细 feedback 走文件通道，绕 claude CLI 长 result 截断）
