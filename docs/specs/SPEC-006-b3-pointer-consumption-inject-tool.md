# SPEC-006: 指针消费物化 + `bin/spec-inject.sh` 人工注入工具 + 组合 TC-C 组

> 批次：组件模型 B3（PROP-3 git 化：工作项指针消息三元组）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`，基线 master@b087fd0 + **SPEC-005 已合入**）
> 依赖序：**依赖 SPEC-005 先合入**——本 spec 消费其 schema triplet 字段、fleet bind / seed payload 通道与三 re-seed 的 triplet 解析 helper（`B3 pointer triplet resolution (SPEC-005)` 段）。engine 侧零改动。
> 定案来源：`../../design.md` §3.3 第 3 钉（人工模式=手工 commit+投指针，与 drafter 同管道生产者无关）+ §2 B3 验收要点（自举一轮全 git 化 + **人工注入 spec MR 走通同一管道**）；`../../plan-b3.md` 定案段（幂等键落注入口：putIfAbsent + id=`<spec_id>@<commit8>`；组合场景以本 spec TC-C 承担，形式偏离 design §5 已备案）。

## 1. 背景

### 1.1 人工模式与生产者无关原则

B0/B1 两例断链（SPEC-168 机械交接、SPEC-169 parse_failed，见 SPEC-005 §1.2）证明：**人工投递不是异常路径，是常驻的第二生产者**。B2 让人工记录过同一道形状闸门；本 spec 把人工投递工具化——`bin/spec-inject.sh` 产出的 trigger 记录与 drafter 管道产出的 trigger 记录**形状同构、闸门同一、幂等键同一**（TC-C3 机器断言），操作员从"按 runbook 手拼 JSON"升级为"一条命令投指针"。roadmap 自身的批投喂随之升级（design §4：B3 落地后投喂方式自动升级为指针消息，吃自己狗粮——B3-3 投喂即用本工具）。

### 1.2 消费侧现状（master@b087fd0 亲核）与"读点"甄别

六道工序中真正**读 spec 内容**的消费点只有两处；其余是透传/守卫：

| 工序 | spec 相关行为 | 本 spec 处置 |
|---|---|---|
| spec-review | `spec-review.md:14`「Read the spec at `{{spec_file}}`」——读全文 | **指针寻址**：`git -C {{repo}} show {{commit}}:{{spec_path}}` |
| spec-check | `spec-check.md:23-24` `git show "$branch":"$rel_spec_file"`——分支树守卫 | **commit 化**：守卫改为指针可解析性检查（禁分支名语义闭环） |
| spec-rework | 只透传不读 | SPEC-005 已带 triplet 透传，本 spec 零触碰 |
| deploy-verify / merger | **不读 spec 内容**（只跑 `accept_cmd`；spec_file 仅出现在 heredoc 变量与 re-seed 透传 :13,:53 / :14,:74） | 亲核落定：**零读点，本 spec 零触碰**（导航「deploy-verify/merger 读点同理」经甄别为透传，已由 SPEC-005 覆盖） |
| dd work/review/deploy/rework | `work.md:9,50` / `review.md:15,38` / `deploy.md:16-19,64` / `rework.md:41` 消费 spec_file | **豁免区零改动**——spec_file=派生物化字段的存在理由（SPEC-005 INV-3），配豁免锚 TC |

### 1.3 物化前置校验与失败路径纪律（拍板）

指针物化（`git show`）失败——commit 不存在、spec_path 不在该 commit 树上、repo 路径失效——**按该工序既有失败路径处置，不发明新失败通道**：

| 工序 | 既有失败路径 | 指针失败并入方式 |
|---|---|---|
| spec-review | 信封 verdict=REJECT（`spec-reviewer.md:32` REJECT generously 纪律） | 读不到 spec 全文 → REJECT，feedback 写明 pointer unresolvable |
| spec-check | REJECT 分支 → re-seed trigger（`spec-check.md:34-52`） | 守卫 `git show "$commit_v:$spec_path_v"` 失败 → 走既有 REJECT re-seed；triplet 解析全空时 re-seed 被出站闸门拦截留 `contract_violations` 哨兵（SPEC-005 INV-5 ③——哨兵也是既有 B2 通道） |

### 1.4 幂等键 `(repo, commit)` 的落地形态

- 注入口：`put-if-absent`（store-cli `src/lib/store-cli.ts:64-89`：created → exit 0；已存在 → exit 1 + 既有记录 JSON，**绝不覆盖**——`store.ts:94-112` O_EXCL）。
- 键编码：record id = `<spec_id>@<commit前8位>`。同 spec 同 commit 二次注入 → 同 id → EEXIST → created:false（TC-C4）。冲突域 = 单 trigger store（run-scoped、单 workspace 实操），足够；spec 修订 = 新 commit = 新 id 新消息（PROP-3 第 1 钉）。
- 队列/git 分工不变：store 管 O_EXCL 认领与调度，git 管内容与版本（本工具绝不写目标 repo——**只校验不代 commit**，拍板）。

## 2. 不变量（INV）

- **INV-1（生产者无关，机器可查）**：`spec-inject.sh` 产出的 trigger 记录与管道生产者（spec-rework APPROVE 出口）产出的 trigger task **键集合逐字相等**（值不同）；两者过同一份 `trigger.schema.json` 闸门。TC-C3 断言。
- **INV-2（工具不写目标 repo）**：spec 文件未 commit（工作树对该文件 dirty / 未跟踪 / 不在 HEAD 树）→ **报错退出，不代 add 不代 commit**（拍板：工具不改用户 repo）。工具对目标 repo 的全部操作为只读（`rev-parse` / `status --porcelain -- <path>` / `cat-file -e` / `show`）。
- **INV-3（物化缓存是派生物，指针是 SSoT）**：`spec_file` 指向工具经 `git show` 导出的缓存文件 `$trigger_store_dir/../.spec-cache/<record_id>.md`（内容 = `git show $commit:$spec_path` 逐字节输出，**不是工作树拷贝**——工作树可能已漂移）。缓存可丢弃可重建，重建入口唯一（同一 triplet）。
- **INV-4（幂等注入）**：同 `(repo, commit)`（同 id）二次注入 → `created:false`，提示既有记录 id 与 status，**exit 0**（幂等成功语义，操作员脚本可安全重跑）；不同 commit 注入同 spec → 新记录（rework 新 commit 新消息）。
- **INV-5（dd 豁免区零改动 + 豁免锚）**：dd-plugin 四模板零 triplet 引用（恰 0 锚）**且** `{{spec_file}}` 消费保留在场（保留断言——B1 PR #6 教训：清零断言必须配豁免白名单/保留锚，防误伤）。豁免依据：plan-b3 定案「指针三元组=SSoT；spec_file 保留为派生物化字段（dd-plugin 4 消费点豁免区零改动+锚）」。
- **INV-6（失败路径零新增）**：指针不可解析的处置全部并入既有通道（§1.3 表）；本 spec 不新增任何 status 枚举值、不新增事件 kind、不新增 store。
- **INV-7（守卫语义升级备案）**：spec-check 守卫从「spec 在 impl 分支树上」改为「指针在 workspace 可解析」（拍板：git show 改用 commit 而非 branch）。行为差异：worker 分支不含 spec 文件时守卫不再拦截——该守卫本就是快速预检（`spec-check.md:19` 注释：最终裁决以目标 repo `make gate` / accept_cmd 为准），分支内容纪律仍由 deploy-verify 的 accept_cmd 执法。engine 通道的 `make gate`「diff 恰 1 spec」纪律不受本 spec 影响（B3 plugin 为主，engine 通道投喂时操作员按其 gate 纪律办）。
- **INV-8（bash 工具纪律）**：`bin/spec-inject.sh` 风格对齐 `bin/bootstrap-loop.sh`：`#!/usr/bin/env bash` + `set -euo pipefail`、`LOOP_STORE_CLI` env 缺省 `/data/code/self/loop-engine/dist/lib/store-cli.js`（:9 同源）、缺依赖 fail-fast 带指引（`require_file` 模式 :13-21）、错误信息带 `[spec-inject]` 前缀。

## 3. 涉及文件与改动精确描述

### 3.1 `workflows/spec-gen/review/templates/spec-review.md`（读点指针化）

- 头部条目区（:3-5）追加三行：`- repo: {{repo}}`、`- commit: {{commit}}`、`- spec_path: {{spec_path}}`（必填占位符——spec-pr 契约 required + io.in 校验保证，SPEC-005 已开通 bind/payload）。
- :14 步骤 1 改为（逐字）：

```
1. Read the spec via the pointer (authoritative content, immune to branch drift):
   run `git -C {{repo}} show {{commit}}:{{spec_path}}` and review its full output.
   If this command fails (bad commit / missing path), the pointer is unresolvable:
   the verdict MUST be REJECT with feedback "pointer unresolvable: <the git error>".
   (`{{spec_file}}` is a derived materialized copy; do not treat it as the source of truth.)
```

### 3.2 `workflows/spec-gen/review/personas/spec-reviewer.md`（工具纪律最小放行）

:7「Do not modify any file. Do not run shell commands.」改为（逐字）：

```
- Do not modify any file. Do not run shell commands, with exactly one exception:
  the read-only `git -C <repo> show <commit>:<path>` used to fetch the spec content.
```

（写权限仍 `write: false`——`review/workflow.yaml` harness 段零改动。）

### 3.3 `workflows/spec-gen/spec-check/templates/spec-check.md`（守卫 commit 化）

SPEC-005 的 helper 已在本模板产出 `repo_v/commit_v/spec_path_v`。守卫段（:18-24）改为：

- 注释更新：INV-3 guard 语义 = 指针可解析性预检（保留「最终裁决以 accept_cmd/make gate 为准」句）。
- :23 `rel_spec_file="${spec_file#$repo/}"` 删除（spec_path_v 接管；缓存路径形态的 spec_file 不再参与守卫——机械strip 对 `.spec-cache/` 路径本就失效）。
- :24 判定行改为：

```bash
if [ -n "$commit_v" ] && git -C "${repo_v:-$repo}" show "$commit_v:$spec_path_v" >/dev/null 2>&1; then
```

（`repo_v` 为空时回落 workspace `$repo`——继承/兜底链全空属 REJECT 分支，由既有 re-seed + 出站闸门处置，INV-6。）旧模式 `show "$branch":` 全文恰 0（TC 锚）。REJECT 分支 feedback 文案同步改写为指针语义：`"REJECT: spec pointer unresolvable (repo=$repo_v commit=$commit_v path=$spec_path_v). Re-commit the spec and re-inject, or fix the workspace clone."`

### 3.4 新建 `bin/spec-inject.sh`（人工注入工具，签名级）

**用法**：`spec-inject.sh <repo> <spec相对路径> <trigger_store_dir> [impl-plan相对路径]`

```bash
#!/usr/bin/env bash
set -euo pipefail
# spec-inject.sh — 人工模式指针注入（design §3.3 第 3 钉；SPEC-006）
# 只校验不代 commit（INV-2）；幂等键 (repo,commit) 以 id=<spec_id>@<commit8> 落地（INV-4）。
LOOP_STORE_CLI="${LOOP_STORE_CLI:-/data/code/self/loop-engine/dist/lib/store-cli.js}"
```

执行序（每步为签名级契约，编号即错误路径）：

1. **参数与依赖**：argc ∉ {3,4} → usage 到 stderr，exit 2。`LOOP_STORE_CLI` 文件不存在 → exit 3（提示 build engine，措辞对齐 `bootstrap-loop.sh:16-20`）。
2. **repo 校验**：`git -C "$repo" rev-parse --git-dir` 失败 → exit 2（`[spec-inject] not a git repository: $repo`）。`repo` 规范化为绝对路径（`cd && pwd`）——record 的 `repo` 字段值。
3. **committed 校验（INV-2，spec 与 impl-plan 逐个）**：
   - `git -C "$repo" cat-file -e "HEAD:$spec_path"` 失败 → exit 4（`not committed at HEAD`——未跟踪/未提交/路径错三合一提示，明示"工具不代 commit，请自行 commit 后重试"）。
   - `git -C "$repo" status --porcelain -- "$spec_path"` 非空 → exit 4（`working tree dirty for $spec_path; commit your changes first`）——防"已 commit 旧版但工作树有新改动"的指针/肉眼错位。
   - 提供第 4 参时对 impl-plan 相对路径做同样两条校验（**同 commit 覆盖 spec 与 plan**）。
4. **取 commit**：`commit="$(git -C "$repo" rev-parse HEAD)"`（拍板）；自检 `[[ "$commit" =~ ^[0-9a-f]{7,40}$ ]]`。commit8=`${commit:0:8}`。
5. **构造 id**：`spec_id="$(basename "$spec_path" .md)"`；校验 `[[ "$spec_id" =~ ^SPEC-[0-9]+ ]]` 否则 exit 2（编号 governance：文件名必须 `SPEC-NNN-slug.md` 形态）；`record_id="${spec_id}@${commit8}"`。（下游效应亲核：dd work 分支名 = `dd/<trigger id>` → `dd/SPEC-NNN-slug@a1b2c3d4`——`@` 后不跟 `{`，是合法 git refname；`%%-r[0-9]*` redo 剥离不受 `@` 影响。）
6. **物化缓存（INV-3）**：`cache_dir="$trigger_store_dir/../.spec-cache"`，`mkdir -p`（`trigger_store_dir` 亦 `mkdir -p`——支持 loop 启动前预投）。`git -C "$repo" show "$commit:$spec_path" > "$cache_dir/$record_id.md"`。impl-plan 提供时同法导出 `"$cache_dir/$record_id.impl-plan.md"`。
7. **构造 record**（node -e JSON，字段顺序即形状契约——TC-C3 键集合断言的左侧）：

```json
{ "id": "<record_id>", "status": "open",
  "spec_file": "<cache_dir 绝对路径>/<record_id>.md",
  "feedback": "(none)",
  "repo": "<repo 绝对路径>", "commit": "<full hash>", "spec_path": "<spec_path>",
  "feedback_file": "<plan 缓存绝对路径，无第 4 参时为空串>" }
```

  （`feedback_file` 承载 impl-plan 缓存路径——对齐 B1/B2 操作员投喂实况形状：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/trigger/*.json` 以 feedback_file 传 impl-plan，dd work.md:11-14 会整读该文件。）
8. **投递（INV-4）**：`node "$LOOP_STORE_CLI" "$trigger_store_dir" put-if-absent "$record_json"`：
   - exit 0（created）→ stdout `[spec-inject] created: <record_id> -> <trigger_store_dir>`，exit 0。
   - exit 1（已存在）→ stdout `[spec-inject] already injected (idempotent, repo+commit key): <record_id> status=<既有 status>`，**exit 0**。
   - 其它 exit → 原样透传报错退出。

### 3.5 新建 `tests/pointer-consumption.test.sh` + `tests/acceptance.sh` 接线

头部纪律镜像 `pipeline-contracts.test.sh:1-30`（ENGINE_ROOT guard SKIP / DD_PLUGIN_ROOT 缺省）。TC 见 §4。测试自建一次性 git repo 与临时 store（`mktemp -d` + trap 清理，模式对齐 `.runtime/test-acceptance` 系测试的自建 repo 做法），**不依赖网络、不调 LLM**。

`tests/acceptance.sh`：check 清单（:14-38 末）追加 `check "bin/spec-inject.sh"`、`check "tests/pointer-consumption.test.sh"`；pointer-records 块（SPEC-005 接线）之后追加同构调用块 `# --- pointer-consumption tests (SPEC-006-b3-pointer-consumption-inject-tool) ---`。

## 4. 测试要求

### RED 场景列表（tests/pointer-consumption.test.sh，落地前全红）

**A 组：消费点物化（静态锚）**

1. **TC-A1（spec-review 指针读在场）**：`spec-review.md` grep 含 `git -C {{repo}} show {{commit}}:{{spec_path}}` 与 `pointer unresolvable`（REJECT 并入语句）；头部三条目在场。
2. **TC-A2（persona 最小放行）**：`spec-reviewer.md` grep 含 `read-only` 与 `git -C <repo> show`；`review/workflow.yaml` 的 `write: false` 原样（守住只读边界）。
3. **TC-A3（spec-check 守卫 commit 化，旧模式恰 0）**：`grep -c 'show "$branch":' spec-check.md` 恰 0（当前为 1，红）；`grep -c 'show "$commit_v:$spec_path_v"' spec-check.md` 恰 1；`rel_spec_file` 引用恰 0。
4. **TC-A4（deploy-verify/merger 零触碰锚）**：`git diff --name-only <SPEC-005 合入点>.. -- workflows/spec-gen/deploy-verify workflows/spec-gen/merger | wc -l` 恰 0（§1.2 甄别落定的回归锚；实现侧以「本 spec 全部 commit 不含这两目录」自检承载）。

**B 组：spec-inject.sh 行为（可执行测试，自建 fixture repo）**

fixture：`mktemp -d` 下 `git init` + `git config user.*` + 写 `docs/specs/SPEC-900-inject-probe.md` + `docs/plans/SPEC-900-inject-probe.impl-plan.md` + commit；`STORE="$tmp/stores/trigger"`。

5. **TC-B1（happy path 全形状）**：`bin/spec-inject.sh "$fixrepo" docs/specs/SPEC-900-inject-probe.md "$STORE" docs/plans/SPEC-900-inject-probe.impl-plan.md` exit 0；store 内恰 1 文件，id == `SPEC-900-inject-probe@<rev-parse HEAD 前8位>`；record 断言：status=open、commit == full `rev-parse HEAD`（40 hex）、repo == fixrepo 绝对路径、spec_path 原值、`spec_file` 落 `.spec-cache/` 且**内容 == `git show HEAD:docs/specs/...` 逐字节**（`cmp`）、feedback="(none)"、feedback_file 落 `.spec-cache/*.impl-plan.md` 且内容同法一致。
6. **TC-B2（未 commit 拒收，INV-2）**：新建未 commit 的 spec 文件 → exit 4，store 零新增，**fixture repo 工作树/HEAD 无任何变化**（`git status --porcelain` 前后一致——"不代 commit"的机器证明）。
7. **TC-B3（已 commit 但工作树 dirty 拒收）**：对已 commit 的 spec 追加一行不 commit → exit 4；`git checkout` 恢复后可注入。
8. **TC-B4（文件名 governance）**：注入 `docs/specs/not-a-spec.md`（已 commit）→ exit 2。
9. **TC-B5（无第 4 参）**：feedback_file == 空串；其余同 TC-B1。

**C 组：组合场景（design §5 之④，plan-b3 备案由本 spec 承担）**

10. **TC-C1（指针 × B2 契约）**：TC-B1 产出的真实 record 过 `trigger.schema.json` ajv 校验**绿**；同 record 删 `commit` 字段后校验**红**（required），改 `commit:"main"` 后校验**红**（pattern）——注入工具与 B2 闸门的咬合证明。
11. **TC-C2（指针 × redo 链）**：把 `spec-check.md` 以 sed 渲染（`{{pr_id}}` 等占位符替换为 fixture 值；`{{repo?}}/{{commit?}}/{{spec_path?}}` 替换为空串——模拟本批 pr 无 triplet）后 bash 执行，fixture 提供：TC-B1 注入的 origin trigger 记录 + 指向 fixture repo 的守卫**失败**场景（spec_path 改指不存在文件触发 REJECT 分支）。断言 stdout 信封：`task.id` 匹配 `^SPEC-900-inject-probe@[0-9a-f]{8}-r[0-9]+$`（redo 后缀与 `@commit8` 共存）且 `task.repo/commit/spec_path` **逐字等于 origin trigger 记录的原值**（继承不漂移，SPEC-005 INV-4/INV-5 ② 的运行态证明）。
12. **TC-C3（人工注入 × 同管道，生产者无关）**：把 `spec-rework.md` APPROVE 路径同法渲染执行（triplet 占位符给 fixture 值），捕获其 trigger task；与 TC-B5 注入 record 比较：**排序后键集合逐字相等**（`id,status,spec_file,feedback,repo,commit,spec_path,feedback_file` vs 同集），仅值不同——形状 diff 为空的机器断言（INV-1）。（比较基线取 B5 无第 4 参形态；rework 出口无 feedback_file 时以两侧同缺处理，断言实现取对称差恰 0。）
13. **TC-C4（幂等键）**：TC-B1 之后**同参二次**注入 → exit 0 + stdout 含 `already injected`，store 仍恰 1 文件、record 内容逐字节不变（O_EXCL 不覆盖）；随后 fixture repo 追加空 commit（`--allow-empty`）再注入 → **新记录**（新 commit8 新 id），store 恰 2 文件——"rework=新 commit 新消息"的正向证明。

**D 组：dd 豁免锚（INV-5）**

14. **TC-D1（恰 0 + 保留断言成对）**：`grep -REc '\{\{ *(repo|commit|spec_path)\??' "$DD_PLUGIN_ROOT"/workflows/spec/{work,review,deploy,rework}/templates/*.md` 恰 0；**且** 四模板各自 `grep -c '{{spec_file}}'` ≥ 1（`work.md:9,50` / `review.md:15,38` / `deploy.md:16-19,64` / `rework.md:41` 消费不变的保留锚）。`$DD_PLUGIN_ROOT` 不可用 → SKIP 并 stderr 声明。测试体注释写明豁免依据（plan-b3 定案 spec_file=派生物化字段）+ B1 PR #6 教训（清零断言误伤豁免项，`edb1a85`）。

### 组合场景归属备案

design §5 要求"每批含一个组合场景 spec"；B3 按 plan-b3 定案由本 spec 的 TC-C 组承担（plugin acceptance 是单一确定性套件，独立 composition spec 为空壳）——形式偏离、实质保留，验收五项之④以 TC-C1~C4 作答。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（pointer-consumption 块 + SPEC-005 的 pointer-records 块 + 既有全部 TC 零回归）。
- 北极星实测（批间人工验收位，Task B3-4，不在本 spec TC 内）：真实 workspace 上 `bin/spec-inject.sh` 投一条真 spec → drain 一轮 → work 认领实现 → spec-check 守卫以 commit 寻址放行 → 合入——人工注入走通同一管道。
- grep 锚（plugin repo 根执行）：
  ```bash
  grep -c 'show "$branch":' workflows/spec-gen/spec-check/templates/spec-check.md   # 预期 0（旧守卫清零）
  grep -c 'git -C {{repo}} show {{commit}}:{{spec_path}}' workflows/spec-gen/review/templates/spec-review.md  # 预期 1
  test -x bin/spec-inject.sh && echo ok                                             # 可执行位
  grep -REc '\{\{ *(repo|commit|spec_path)\??' /data/code/self/loop-engine-dev-dispatch-plugin/workflows/spec/*/templates/*.md  # 预期全 0
  git log --oneline <本 spec 分支> -- workflows/spec-gen/deploy-verify workflows/spec-gen/merger | wc -l      # 预期 0（TC-A4）
  ```

## 6. 豁免清单

| 豁免项 | 范围 | 依据 | 锚 |
|---|---|---|---|
| dd-plugin 四模板消费 spec_file 不改指针寻址 | `dd work.md:9,50` / `review.md:15,38` / `deploy.md:16-19,64` / `rework.md:41` | plan-b3 定案：pointer=SSoT、spec_file=派生物化缓存注入，dd 零改动；dd 契约化随其自身 roadmap（B4 收编候选） | TC-D1（恰 0 + `{{spec_file}}` 保留断言成对；B1 PR #6 教训注释进测试体） |
| deploy-verify / merger 不做指针读改造 | 两工序模板全文件 | 亲核零读点（§1.2）：只跑 accept_cmd，透传已由 SPEC-005 覆盖 | TC-A4 零触碰锚 |
| spec-inject.sh 不创建/关联真实 GitLab/GitHub MR | `mr` 字段本批无生产者 | design §3.3 `mr` 为可选元数据；北极星「人工注入 spec MR」的 MR 指人工 spec 提交流程整体，工具以指针消息承载；MR 元数据接入随后续批次 | trigger schema `mr` 可选（SPEC-005），零断言 |
| 工具不校验 spec 内容质量 | 只做 committed/形状/governance 文件名校验 | 内容质量由管道下游（spec-review/gate）执法——同管道原则的另一面 | 无（Non-goal） |

# References
- 设计 SSoT：`../../design.md` §3.3（人工模式第 3 钉）+ §2 B3 验收要点 + §4（投喂升级为指针消息）+ §5 之④；PROP-3 原文 `../../../loop-engine-概念梳理-问题清单/issues.md`
- 批次定案：`../../plan-b3.md`（幂等键落注入口 putIfAbsent + id=`<spec_id>@<commit8>`；组合场景 TC-C 承担备案；spec_file 派生物化 + dd 4 消费点豁免）
- 依赖 spec：`SPEC-005-b3-pointer-records.md`（schema triplet / bind / seed payload / triplet 解析 helper——本 spec 消费其 `repo_v/commit_v/spec_path_v` 变量与哨兵注释锚）
- engine 签名核对（main=7be3aa0，零改动）：`src/lib/store-cli.ts:64-89`（put-if-absent exit 0/1/2/3 语义）、`src/lib/store.ts:94-112`（putIfAbsent O_EXCL 不覆盖）、`src/template.ts`（`{{key?}}` 可选空串——TC-C2 sed 渲染模拟的对象语义）
- plugin 实况核对（master=b087fd0）：`spec-review.md:14`、`spec-reviewer.md:7,32`、`spec-check.md:18-24,34-52`、`deploy-verify.md:13,53`（透传非读点）、`merger.md:14,74`（同）、`bin/bootstrap-loop.sh:9,13-21`（LOOP_STORE_CLI 缺省与 require_file 纪律）、`tests/acceptance.sh:14-38,626-633`
- 操作员投喂形状实况：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/trigger/*.json`（feedback_file 承载 impl-plan——工具第 4 参语义来源）
- 豁免锚教训：plugin PR #6（`edb1a85`）
