# SPEC-006-b3-pointer-consumption-inject-tool — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先写失败测试，确认红，最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`
> 前置：**SPEC-005 已合入 master**（本 plan 假定 `contracts/` 三 schema 带 triplet、fleet bind/seed payload 已通、三 re-seed 模板含 `B3 pointer triplet resolution (SPEC-005)` helper 段并产出 `repo_v/commit_v/spec_path_v`）。开工前自检：`grep -c 'B3 pointer triplet resolution (SPEC-005)' workflows/spec-gen/spec-check/templates/spec-check.md` 必须为 1，否则停手报错（依赖序未满足）。

## Files

**Modify（精确路径）：**
- `workflows/spec-gen/review/templates/spec-review.md`（读点指针化）
- `workflows/spec-gen/review/personas/spec-reviewer.md`（git show 只读最小放行）
- `workflows/spec-gen/spec-check/templates/spec-check.md`（守卫 commit 化；只动 :18-24 守卫段与 REJECT feedback 文案）
- `tests/acceptance.sh`（check 清单 + pointer-consumption 调用块）

**Create：**
- `bin/spec-inject.sh`（可执行位 `chmod +x`，git mode 100755）
- `tests/pointer-consumption.test.sh`

**禁止触碰：**
- `workflows/spec-gen/deploy-verify/**`、`workflows/spec-gen/merger/**`（TC-A4 零触碰锚——亲核零读点）
- `workflows/spec-gen/rework/**`（透传已由 SPEC-005 完成）
- `workflows/spec-gen/contracts/**`（schema 属 SPEC-005）、fleet 三 tpl、`review/workflow.yaml`（含 `write: false` 行）
- dd-plugin repo 任何文件

## Interfaces

**Consumes：**
- SPEC-005 产物：三 schema triplet、spec-check 的 `repo_v/commit_v/spec_path_v` 变量、spec-rework 的 triplet 透传 task
- engine store-cli `put-if-absent`（exit 0=created / 1=已存在 / 2,3=错误；`$LOOP_STORE_CLI` 缺省 `/data/code/self/loop-engine/dist/lib/store-cli.js`）
- spec §3.4 工具执行序 1~8（签名级，编号即错误路径：exit 2 用法/形状、3 缺依赖、4 未 commit/dirty）

**Produces：**
- 指针寻址读点（spec-review）+ 指针可解析性守卫（spec-check）
- `bin/spec-inject.sh`：`<repo> <spec相对路径> <trigger_store_dir> [impl-plan相对路径]` → trigger record（id=`<spec_id>@<commit8>`，spec_file=`.spec-cache` 物化，feedback_file=plan 物化或空串）
- `tests/pointer-consumption.test.sh`：TC-A1~A4 / B1~B5 / C1~C4 / D1

## TDD 步骤（bite-sized，每步 commit）

### Step 1：失败测试骨架（A 组 + D 组）+ 确认红

新建 `tests/pointer-consumption.test.sh`，头部镜像 `pipeline-contracts.test.sh:1-30` 纪律（`set -euo pipefail` / ROOT / ENGINE_ROOT guard SKIP / `DD_PLUGIN_ROOT` 缺省）。先落静态锚：

- TC-A1/A2/A3（spec-review 指针读、persona 放行、spec-check 旧模式 `show "$branch":` 恰 0——当前为 1，红）。
- TC-D1 豁免锚（dd 四模板 triplet 占位符恰 0 **且** `{{spec_file}}` 各 ≥1 保留断言；dd 目录不可用 SKIP；注释写明 plan-b3 豁免依据 + B1 PR #6 `edb1a85` 教训）。

跑 `bash tests/pointer-consumption.test.sh` **确认红**（A1/A3 红；D1 应当已绿——豁免锚是保护性断言）。

commit：`test: pointer-consumption 失败骨架（读点/守卫锚 + dd 豁免锚）`

### Step 2：消费点物化（TC-A1/A2/A3 绿）

1. `spec-review.md`：头部加 repo/commit/spec_path 三条目（必填 `{{repo}}` 形态）；:14 步骤 1 按 spec §3.1 逐字替换（含 pointer unresolvable → REJECT 并入语句与 spec_file 派生语义括注）。
2. `spec-reviewer.md`：:7 按 spec §3.2 逐字替换（read-only git show 唯一例外）。
3. `spec-check.md`：删 :23 `rel_spec_file` 行；:24 判定行改 `[ -n "$commit_v" ] && git -C "${repo_v:-$repo}" show "$commit_v:$spec_path_v"`；:18-22 注释改指针预检语义（保留"最终裁决 accept_cmd"句）；REJECT feedback 文案改指针语义（spec §3.3 逐字）。
4. TC-A1/A2/A3 绿；`bash tests/pipeline-contracts.test.sh` 与 `tests/pointer-records.test.sh` 回归绿（SPEC-005 的 TC-5 helper 锚不受守卫改动影响）。

commit：`feat: spec-review 指针寻址读 spec + spec-check 守卫 commit 化（禁分支名语义闭环）`

### Step 3：spec-inject.sh 最小可用（TC-B1/B5 绿）

1. 落 `bin/spec-inject.sh`（spec §3.4 执行序 1~8 全量；INV-8 风格：`[spec-inject]` 前缀、`require_file` 模式、LOOP_STORE_CLI env 缺省）。`chmod +x`。
2. 测试补 B 组 fixture（`mktemp -d` git repo + SPEC-900 探针 spec/plan + trap 清理）与 TC-B1（全形状断言：id/commit hex40/`.spec-cache` 物化 `cmp` 逐字节/feedback_file）+ TC-B5（无第 4 参 → feedback_file 空串）。
3. 确认绿。

commit：`feat: bin/spec-inject.sh 人工指针注入（物化缓存 + put-if-absent）`

### Step 4：拒收路径（TC-B2/B3/B4 绿）

1. 补 TC-B2（未 commit → exit 4 + store 零新增 + fixture repo 状态前后不变——"不代 commit"机器证明）、TC-B3（committed 但 dirty → exit 4；恢复后可注入）、TC-B4（`not-a-spec.md` → exit 2）。
2. 实现侧核对 §3.4 步骤 3 的两条校验顺序与 exit 码；确认绿。

commit：`feat: spec-inject 拒收路径——只校验不代 commit（INV-2）`

### Step 5：组合 TC-C 组（C1~C4 绿）

1. **TC-C1**：TC-B1 real record → ajv（engine createRequire）过 `trigger.schema.json` 绿；删 commit 红；`commit:"main"` 红。
2. **TC-C4**：同参二次注入 → exit 0 + `already injected` + store 恰 1 + 内容 `cmp` 不变；`git commit --allow-empty` 后三次注入 → store 恰 2（新 commit8 新 id）。
3. **TC-C2**（渲染执行 spec-check）：sed 把 `spec-check.md` 的 `{{pr_id}}/{{spec_id}}/{{spec_file}}/{{workspace_repo}}/{{branch}}/{{base_commit}}/{{trigger_store_dir}}` 替换为 fixture 值、`{{repo?}}/{{commit?}}/{{spec_path?}}` 替换为空串（模拟 pr 无 triplet），`spec_id` 给 TC-B1 注入的 record id、`trigger_store_dir` 给其 store——origin trigger 兜底继承生效；守卫置于失败态（spec_path 指向不存在文件的变体 origin 记录，或直接用 base_commit 不含探针文件的 fixture 分支）。执行渲染产物，捕获 stdout 信封 JSON，node 断言 `task.id =~ ^SPEC-900-inject-probe@[0-9a-f]{8}-r[0-9]+$` 且 task.repo/commit/spec_path 逐字 == origin 记录原值。
   - 注意：渲染是**测试内**的 sed 近似（engine fill 的 `{{key?}}` 缺值=空串语义按 `src/template.ts` 对齐）；不得为此改模板本体。
4. **TC-C3**（生产者无关形状断言）：同法渲染 `spec-rework.md` APPROVE 路径（verdict=APPROVE、triplet 给 fixture 值），捕获 trigger task 键集合；与 TC-B5 record 键集合做对称差，断言恰 0（feedback_file 两侧同缺/同在的对称处理按 spec §4 TC-C3 括注）。
5. 确认 C 组全绿。

commit：`test: 组合 TC-C 组——指针×契约/redo 链/同管道/幂等键（design §5 之④）`

### Step 6：acceptance 接线 + 全量回归 + INV 自检

1. `tests/acceptance.sh`：check 清单加 `bin/spec-inject.sh`、`tests/pointer-consumption.test.sh`；pointer-records 块后加 pointer-consumption 调用块（同构八行）。
2. 补 TC-A4 自检（本分支 commit 范围不含 deploy-verify/merger 目录：`git log --oneline master.. -- workflows/spec-gen/deploy-verify workflows/spec-gen/merger | wc -l` 恰 0）。
3. `bash tests/acceptance.sh` 全绿；spec §5 grep 锚全跑。

commit：`test: pointer-consumption 接入 acceptance + 零触碰/豁免锚终检`

## INV 自检清单

- [ ] INV-1：TC-C3 键集合对称差恰 0（生产者无关机器证明）
- [ ] INV-2：TC-B2/B3 过；工具源码 grep 无 `git add`/`git commit`（只读操作清单：rev-parse/status/cat-file/show）
- [ ] INV-3：TC-B1 `cmp` 逐字节（缓存 == `git show`，非工作树 cp）；缓存路径形态 `$trigger_store_dir/../.spec-cache/<record_id>.md`
- [ ] INV-4：TC-C4 过（同键幂等 exit 0 / 新 commit 新消息）
- [ ] INV-5：TC-D1 恰 0 + 保留断言成对；dd-plugin repo `git status` 零改动
- [ ] INV-6：全 diff 无新增 status 枚举/事件 kind/store；spec-review 失败并入 REJECT、spec-check 失败并入既有 re-seed+哨兵
- [ ] INV-7：守卫语义升级备案已在 spec §2；`review/workflow.yaml` `write: false` 未动
- [ ] INV-8：`bash -n bin/spec-inject.sh` 过；`set -euo pipefail` 在场；exit 码族 2/3/4 与 spec §3.4 一致
- [ ] 依赖序：开工自检（SPEC-005 helper 锚在场）已执行
