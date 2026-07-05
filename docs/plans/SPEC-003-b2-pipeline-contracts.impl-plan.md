# SPEC-003-b2-pipeline-contracts — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先写失败测试，确认红，最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`
> 前置：engine 侧 B2 io 支持已合入（本 spec 投喂顺序由操作员保证；实现侧无需检查 engine 行为——本 spec 全部 TC 为静态断言，不依赖 engine 新代码路径）。

## Files

**Modify（精确路径）：**
- `workflows/spec-gen/draft/workflow.yaml`
- `workflows/spec-gen/review/workflow.yaml`
- `workflows/spec-gen/rework/workflow.yaml`
- `workflows/spec-gen/spec-check/workflow.yaml`
- `workflows/spec-gen/deploy-verify/workflow.yaml`
- `workflows/spec-gen/merger/workflow.yaml`
- `tests/acceptance.sh`（check 清单 + 新测试块接线）

**Create：**
- `workflows/spec-gen/contracts/{idea,spec-pr,verdict,trigger,pr}.schema.json`（5 正本）
- 六工序 `contracts/` 下 13 个相对 symlink（清单见 spec §3.3）
- `tests/pipeline-contracts.test.sh`

**禁止触碰（INV-2/INV-6）：**
- `workflows/spec-gen/*/templates/*.md`、`workflows/spec-gen/*/personas/*.md`
- `workflows/fleet-impl.yaml.tpl`、`workflows/fleet-merge.yaml.tpl`、`workflows/fleet.yaml.tpl`
- dd-plugin repo 任何文件

## Interfaces

**Consumes：**
- spec §3.2 五份 schema 全文（逐字落盘）
- spec §3.4 六段 io YAML（逐字插入）
- engine 依赖树 `ajv`（`$ENGINE_ROOT/node_modules/ajv`）与 `yaml`（`$ENGINE_ROOT/node_modules/yaml`），经 `createRequire($ENGINE_ROOT/package.json)` 获取——本 repo 保持零 npm 依赖
- 现有 `tests/acceptance.sh`（扩充不破坏）

**Produces：**
- 六 workflow.yaml：io 段声明（in 1 队列 + out 覆盖全 routes）
- contracts 正本 5 + symlink 13
- tests/pipeline-contracts.test.sh：TC-1~TC-9

## TDD 步骤（bite-sized，每步 commit）

### Step 1：写失败测试骨架 + 确认红

新建 `tests/pipeline-contracts.test.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
fail=0
if [ ! -d "$ENGINE_ROOT/node_modules/ajv" ]; then
  echo "SKIP: engine node_modules/ajv missing; npm install in $ENGINE_ROOT" >&2
  exit 0
fi
# TC-1: 恰 6 个 workflow.yaml 有 io 段
io_count="$(grep -l '^io:' "$ROOT"/workflows/spec-gen/*/workflow.yaml 2>/dev/null | wc -l | tr -d ' ')"
if [ "$io_count" -eq 6 ]; then echo "ok: TC-1 io section on all 6 workflows"; else echo "FAIL: TC-1 io count=$io_count expected 6" >&2; fail=1; fi
# ...（TC-2~TC-9 逐条同构）
[ "$fail" -eq 0 ] || { echo "pipeline-contracts FAILED"; exit 1; }
```

先只落 TC-1、TC-2，跑 `bash tests/pipeline-contracts.test.sh` **确认红**（当前 io 段 0 个、正本目录不存在）。

### Step 2：落正本 5 份 schema（TC-2/TC-3 绿）

1. `mkdir -p workflows/spec-gen/contracts`，按 spec §3.2 **逐字**写入 5 份 `*.schema.json`。
2. 补 TC-3（ajv 编译循环，snippet 见 spec §3.6，`new Ajv({ allErrors: true })`）。
3. `bash tests/pipeline-contracts.test.sh`：TC-2/TC-3 绿，TC-1 仍红（预期）。

commit：`feat: B2 contracts 正本 5 schema（trigger/pr/verdict/spec-pr/idea）`

### Step 3：fixture 正反例（TC-4/TC-5/TC-6）

1. 测试体内嵌 heredoc fixtures：
   - 好记录 5 类各 1（trigger 用 `SPEC-170-...-r1783237261` 型带 -r 后缀 id；verdict 各出 pr_id/spec_pr_id 变体各 1，共 6 条正例）。
   - 坏记录 4 条：pr `status:"bogus"`；trigger 缺 `spec_file`；verdict `verdict:"MAYBE"`；idea `id:""`。
   - 宽进 1 条：pr 记录混入 `repo`/`commit` 未知字段必须**通过**。
2. node 校验循环：`validate(record)` 按预期通过/拒绝，否则 FAIL。
3. 确认 TC-4/TC-5/TC-6 绿。

commit：`test: contracts 正反例 fixture（宽进严出锚）`

### Step 4：13 个 symlink（TC-7 绿）

按 spec §3.3 清单逐个：

```bash
for w in draft:idea,spec-pr review:spec-pr,verdict rework:verdict,trigger,idea \
         spec-check:pr,trigger deploy-verify:pr,trigger merger:pr,trigger; do
  dir="workflows/spec-gen/${w%%:*}/contracts"; mkdir -p "$dir"
  IFS=, read -ra names <<< "${w#*:}"
  for n in "${names[@]}"; do ln -s "../../contracts/$n.schema.json" "$dir/$n.schema.json"; done
done
```

补 TC-7（symlink 恰 13 / 非 symlink 恰 0 / realpath 落正本目录）。确认绿。`git add` 时确认 git 以 symlink 模式（120000）收录。

commit：`feat: 六工序 contracts symlink（单一事实源防漂移）`

### Step 5：六 workflow.yaml 加 io 段（TC-1/TC-8 绿）

1. 按 spec §3.4 逐字插入 io 段——位置统一在 `routes:` 块之后、`seed:` 之前；**两空格缩进对齐现有段**；不动任何既有行。
2. 补 TC-8：用 engine `yaml` 包解析六 workflow.yaml，断言 `Object.keys(io.out).sort()` 与 `Object.keys(routes).sort()` 逐一相等、`io.in.queue`/`io.in.contract` 非空、contract 路径全部以 `contracts/` 开头。
3. `bash tests/pipeline-contracts.test.sh` 全绿（除 TC-9 未写）。

commit：`feat: 六道工序 workflow.yaml 声明 io 契约段`

### Step 6：豁免锚 + acceptance 接线 + 全量回归

1. 补 TC-9 豁免锚：`grep -l '^io:' "$DD_PLUGIN_ROOT"/workflows/spec/*/workflow.yaml | wc -l` 恰 0；`[ -d "$DD_PLUGIN_ROOT" ]` 不满足则 `echo SKIP` 不判失败。测试体注释写明豁免依据（design §2「自举六道工序」+ B1 PR #6 教训）。
2. `tests/acceptance.sh`：
   - `check` 清单（:14-33 段末尾）追加 5 行正本路径；
   - 在 complete-effect 测试块之后追加 pipeline-contracts 调用块（spec §3.5 逐字）。
3. 全量验收 + INV 范围自检：

```bash
bash tests/acceptance.sh
git diff --name-only master -- 'workflows/spec-gen/*/templates/*' 'workflows/spec-gen/*/personas/*' 'workflows/*.tpl' | wc -l   # 必须 0
```

commit：`test: pipeline-contracts 接入 acceptance + 豁免锚`

## INV 自检清单

- [ ] INV-1：acceptance.sh 既有 fleet-impl/fleet-merge loadFleetManifest 校验全绿（旧 dist 剥离 io 段不报错）
- [ ] INV-2：`git diff --stat` 无 templates/*.md、personas/*.md
- [ ] INV-3：5 schema 均 `additionalProperties: true`；TC-6 宽进正例通过；id 无 pattern 锁
- [ ] INV-4：TC-9 豁免锚（dd-plugin 恰 0）+ 注释依据
- [ ] INV-5：TC-7 symlink 恰 13、拷贝恰 0、realpath 全落正本目录
- [ ] INV-6：三个 fleet *.tpl 零改动；io 段无 `{{` 占位符（`grep '{{' workflows/spec-gen/contracts/ 各 workflow.yaml io 段` 为 0）
- [ ] INV-7：TC-8 六 workflow io.out 键集合 == routes 键集合
