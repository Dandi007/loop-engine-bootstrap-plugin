# SPEC-005-b3-pointer-records — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先写失败测试，确认红，最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`
> 前置：无 engine 侧依赖（engine main=7be3aa0 已含 B2 契约执法，本 spec 零 engine 改动）；本 spec 必须先于 SPEC-006 合入。

## Files

**Modify（精确路径）：**
- `workflows/spec-gen/contracts/trigger.schema.json`（正本；symlink 自动透传）
- `workflows/spec-gen/contracts/spec-pr.schema.json`
- `workflows/spec-gen/contracts/pr.schema.json`
- `workflows/spec-gen/draft/templates/draft.md`
- `workflows/spec-gen/review/personas/spec-reviewer.md`
- `workflows/spec-gen/rework/templates/spec-rework.md`
- `workflows/spec-gen/spec-check/templates/spec-check.md`
- `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`
- `workflows/spec-gen/merger/templates/merger.md`
- `workflows/spec-gen/{review,rework,spec-check,deploy-verify,merger}/workflow.yaml`（seed payload 三行；draft 不动）
- `workflows/fleet-impl.yaml.tpl`（7 处 bind）+ `workflows/fleet-merge.yaml.tpl`（1 处 bind）
- `tests/pipeline-contracts.test.sh`（fixture 迁移：:98-100 good-trigger 补 triplet、:112-114 good-spec-pr 补 triplet、:131-134 宽进探针换键名）
- `tests/acceptance.sh`（check 清单 + pointer-records 调用块）

**Create：**
- `tests/pointer-records.test.sh`（TC-1~TC-8）

**禁止触碰：**
- dd-plugin repo 任何文件（`/data/code/self/loop-engine-dev-dispatch-plugin`）
- `contracts/{idea,verdict}.schema.json`、六工序 `contracts/` 下 13 个 symlink
- `bin/bootstrap-loop.sh`、`bin/bootstrap-continuous.sh`、`workflows/fleet.yaml.tpl`、`workflows/spec-gen/draft/workflow.yaml`
- `workflows/spec-gen/review/templates/spec-review.md`（读点物化属 SPEC-006）、spec-check 的守卫判定行（`spec-check.md:24` 的 `git show "$branch":…` 本 spec 不动，SPEC-006 接管）

## Interfaces

**Consumes：**
- spec §3.1 三 schema 演进（required 表 + 四 property 全文 + spec_file description 逐字）
- spec §3.5 triplet 解析 helper bash 段（三模板逐字一致）
- engine 依赖树 `ajv`（`createRequire($ENGINE_ROOT/package.json)`，本 repo 保持零 npm 依赖）
- 占位符纪律：上游无契约保证的通道一律 `{{key?}}`（spec §1.5 / INV-5——必填占位符缺值 = tick 同步死亡）

**Produces：**
- trigger/spec-pr 记录：triplet required；pr 记录：triplet 可选 + pattern 执法
- 生产链全透传：draft→spec-pr→(persona 回声)→spec-verdict→(rework 透传)→trigger；pr→(origin trigger 兜底继承)→re-seed trigger
- fleet bind 8 处 + seed payload 5 处的双层通道
- `tests/pointer-records.test.sh` TC-1~TC-8

## TDD 步骤（bite-sized，每步 commit）

### Step 1：失败测试骨架（TC-1/TC-3 先行）+ 确认红

新建 `tests/pointer-records.test.sh`，头部纪律镜像 `tests/pipeline-contracts.test.sh:1-30`（`set -euo pipefail`、`ROOT`、`ENGINE_ROOT` guard SKIP、`DD_PLUGIN_ROOT` 缺省）。先落 TC-1（三 schema triplet 声明形状：properties 四键 / commit.pattern 逐字 / trigger+spec-pr required 含 triplet / **pr required 不含** / spec_file.description 非空）与 TC-3（bind 计数锚：`grep -Ec '^[[:space:]]+spec_path: spec_path$'` fleet-impl 恰 7、fleet-merge 恰 1；`commit: commit`、`repo: repo` 同——**必须行首缩进锚定**，规避 `base_commit: base_commit` 子串）。

跑 `bash tests/pointer-records.test.sh` **确认红**（schema 无 triplet、bind 计数 0）。

commit：`test: pointer-records 失败测试骨架（TC-1 schema 形状 + TC-3 bind 锚）`

### Step 2：三 schema 演进（TC-1 绿）+ fixture 迁移（TC-8 绿）

1. 按 spec §3.1 逐字改三正本：四 property（repo/commit/spec_path/mr）+ required 表 + spec_file description。**不动** idea/verdict 正本与任何 symlink。
2. 迁移 `tests/pipeline-contracts.test.sh` 三处 fixture（spec §3.8）：good-trigger（:98-100）与 good-spec-pr（:112-114）补 hex40 triplet；宽进探针（:131-134）`"repo"/"commit"` 键改 `"zzz_b4_future":"x"`。
3. 补 TC-2（ajv 正反例）：正例 4（trigger hex40 / trigger `-r<epoch>` id 同 commit / pr 无 triplet / pr hex7），反例 6（trigger commit="main"、"feature/x"、缺 repo；spec-pr 缺 commit；pr commit="main"；trigger commit="def456" 6 位下界外）。
4. `bash tests/pointer-records.test.sh`：TC-1/TC-2 绿；`bash tests/pipeline-contracts.test.sh` 全绿（TC-8 承载）。

commit：`feat: B3 契约演进——trigger/spec-pr triplet required、pr 可选+pattern 执法（fixture 同步迁移）`

### Step 3：fleet 8 处 bind + 5 处 seed payload（TC-3/TC-6 绿）

1. `fleet-impl.yaml.tpl` :45/:63/:88/:110/:137/:159/:182 与 `fleet-merge.yaml.tpl` :20：每处 `spec_file: spec_file` 行后插三行 `repo: repo` / `commit: commit` / `spec_path: spec_path`（缩进对齐所在 bind 块）。
2. 五 workflow.yaml seed payload（spec §3.7 表）：review 用必填 `"{{repo}}"` 形态，rework/spec-check/deploy-verify/merger 用可选 `"{{repo?}}"` 形态。draft/workflow.yaml 零触碰。
3. 补 TC-6（payload 通道恰 5 + 形态逐文件断言）与 TC-7（bootstrap-loop.sh seed 段零 spec_path）。
4. 回归：`bash tests/acceptance.sh` 既有 fleet-impl/fleet-merge `loadFleetManifest` 校验必须仍绿（bind 是自由映射 `fleet.ts:64`，零 schema 阻力）。

commit：`feat: fleet 8 处 bind + 5 workflow seed payload 打通 triplet 双层通道`

### Step 4：生产侧模板——draft 出口 + persona 回声 + rework 透传（TC-4/TC-5 前半绿）

1. `draft.md`：Step 3 final commit 后加 `git -C {{workspace_repo}} rev-parse HEAD` 取 spec commit 的指令步；信封 task（:79-84）加 `"repo"/"commit"/"spec_path"` 三字段 + "真实 hash、禁占位串"纪律语句（对齐 dd work.md:38 措辞）。
2. `spec-reviewer.md`：verdict task（:18-27）加三回声行 `"repo": "{{repo}}"` 等（必填形态）。
3. `spec-rework.md`：heredoc 区加三变量（`{{repo?}}` 可选形态）；APPROVE trigger task 与 REJECT idea task 各加三字段（env 透传）。
4. 补 TC-4（draft 出口在场）与 TC-5 的 persona/rework 断言，确认绿。

commit：`feat: 生产侧 draft 出口/persona 回声/rework 透传携带指针三元组`

### Step 5：三处 re-seed 继承 helper（TC-5 后半绿）

1. 按 spec §3.5 把**逐字一致**的 helper 段（哨兵注释 `B3 pointer triplet resolution (SPEC-005)`）插入 `spec-check.md` / `deploy-verify.md` / `merger.md` 的 heredoc 变量区之后；spec-check / deploy-verify / merger 模板 heredoc 区补 `trigger_store_dir="{{trigger_store_dir}}"` 声明。
2. 三处 re-seed trigger task 各加三字段（env 前缀行同步加 `REPO_V=… COMMIT_V=… SPEC_PATH_V=…`）。解析全空不特判（出站闸门兜底，INV-5 ③）。
3. 补全 TC-5（helper 哨兵注释恰 3 + task 字段在场），确认绿。
4. 回归自检：`grep -n 'loop_store_cli' workflows/spec-gen/{rework,spec-check,deploy-verify,merger}/templates/*.md` 恰 0（helper 用 node 直读文件，不触 acceptance.sh:645/654 的 B0 恰 0 锚）。

commit：`feat: 三处 re-seed 继承指针原值（bind 优先 + origin trigger 兜底 + 闸门哨兵兜底）`

### Step 6：acceptance 接线 + 全量回归 + INV 自检

1. `tests/acceptance.sh`：check 清单（:14-38 末）加 `tests/pointer-records.test.sh`；pipeline-contracts 块（:626-633）后加 pointer-records 调用块（spec §3.9 逐字）。
2. `bash tests/acceptance.sh` 全绿。
3. spec §5 grep 锚全跑一遍 + 零改动清单自检。

commit：`test: pointer-records 接入 acceptance + 豁免/零改动锚自检`

## INV 自检清单

- [ ] INV-1：commit pattern `^[0-9a-f]{7,40}$` 三 schema 逐字一致（TC-1）；repo/spec_path 无 pattern；mr 仅 type:object
- [ ] INV-2：pr required 不含 triplet（TC-1 锚）；无 triplet pr 记录 ajv 通过（TC-2 正例）——拍板偏离已在 spec §2 备案，实现侧照 spec 执行
- [ ] INV-3：三 schema spec_file 保持 required、值语义不变、description 注记在场（TC-1）
- [ ] INV-4：redo id 模式零改动（`${spec_id%%-r[0-9]*}-r$(date +%s)` 各处原样）；`-r` id + 同 commit 正例过（TC-2）
- [ ] INV-5：所有可能缺值通道用 `{{key?}}`（rework/spec-check/deploy-verify/merger payload 与模板）；grep 确认无必填 `{{repo}}` 出现在 pr/verdict 消费链模板中（review 侧必填是契约保证的例外）
- [ ] INV-6：dd-plugin repo `git status` 零改动；`grep -REc '\{\{ *(repo|commit|spec_path)\??' $DD_PLUGIN_ROOT/workflows/spec/*/templates/*.md` 全 0
- [ ] INV-7：未触碰 loader/engine；enqueue 仍走 routes→putIfAbsent
- [ ] INV-8：idea/verdict schema `git diff` 零改动；additionalProperties:true 三 schema 保持
- [ ] symlink 网络：`find workflows/spec-gen/*/contracts -name '*.schema.json' -type l | wc -l` 仍恰 13
