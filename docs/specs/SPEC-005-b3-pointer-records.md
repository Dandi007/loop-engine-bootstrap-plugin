# SPEC-005: 指针消息三元组 —— 契约演进 + 生产侧全链落 {repo, commit, spec_path}

> 批次：组件模型 B3（PROP-3 git 化：工作项指针消息三元组）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`，基线 master@b087fd0）
> 依赖序：**本 spec 先于 SPEC-006 合入**（006 的消费物化与注入工具依赖本 spec 的 schema 字段、fleet bind 与 seed payload 通道）。engine 侧**零改动**（B3 定案：bind 纯字段复制 `fleet.ts:149-151`，enqueue 幂等 `loader.ts:297-314`，出站/入站契约执法 B2 已在 main=7be3aa0——本批只用不改）。
> 定案来源：`../../design.md` §2 B3 行 + §3.3 指针消息（形状锁死）；`../../plan-b3.md` 定案段（2026-07-05 21:40 recon 后拍板）。

## 1. 背景

### 1.1 PROP-3 三钉子（design §3.3 锁死，不得偏离）

1. **三元组 `{repo, commit, spec_path}` + 可选 `mr` 元数据；禁分支名，只认 commit hash**；rework = 新 commit 新消息（指 spec 修订链，见 INV-4）。
2. **幂等键 `(repo, commit)`**；队列仍管调度与 O_EXCL 认领（`store.ts:94-112` putIfAbsent / claim），git 管内容与版本。
3. **人工模式 = 手工 spec commit + 投指针消息**（SPEC-006 提供 `bin/spec-inject.sh`）；与 drafter 产出走同一管道——**生产者无关**。

### 1.2 动机活体：断链交接缺不可变锚点（B0/B1 实证）

- **SPEC-168（push 前断）**：worker 撞 `error_max_turns` 截停，留下 trigger=done / 分支未 push / pr store 空三重不一致；操作员机械交接手投 pr 记录（`../../progress.md` 2026-07-04 23:31/23:35 条目）。手投时 spec 内容"是哪个版本"全靠操作员对现场的记忆——spec_file 是活动砂地上的路径，交接期间 workspace 分支切换随时改写其内容。
- **SPEC-169（信封 parse_failed）**：同样机械交接手投（`../../acceptance-b1.md` SPEC-169 行）。
- B2 契约批让手投记录过了**形状**闸门；本批指针化让手投记录有**内容版本**锚点：`(repo, commit)` 不可变，机械交接/重投指向的 spec 内容永远逐字可复原（`git show commit:spec_path`），且同 (repo,commit) 重复投递被幂等键吸收。

### 1.3 本 spec 的分工边界

| 半边 | 归属 |
|---|---|
| 契约演进（trigger/spec-pr/pr 三 schema 加 triplet + mr）+ 生产侧全链（drafter 出口 / persona 回声 / spec-rework 透传 / 三处 re-seed 继承 / fleet bind / seed payload 通道） | **本 spec** |
| 消费侧物化（git show 读点）、spec-check 守卫 commit 化、`bin/spec-inject.sh` 人工注入工具、dd 豁免锚、组合 TC-C 组 | **SPEC-006** |

### 1.4 triplet 载体面盘点（起草时逐处亲核，master@b087fd0）

record 类别 × 生产者 × 本批 triplet 可达性：

| record | 生产者 | 本批带 triplet？ | 依据 |
|---|---|---|---|
| spec-pr | drafter（本 repo，改） | **是（required）** | `draft/templates/draft.md:69-88` 信封 task |
| trigger | spec-rework APPROVE（本 repo，改）；spec-check/deploy-verify/merger re-seed（本 repo，改）；人工注入（SPEC-006 工具/操作员） | **是（required）** | `spec-rework.md:30-43`、`spec-check.md:38-52`、`deploy-verify.md:45-59`、`merger.md:66-80` |
| trigger（豁免洞） | dd rework REJECT 直投（`dd rework.md:36-48`，store-cli `put` 直调，B0 豁免项） | 否（已知洞） | 该路径不经任何契约闸门（dd work 无 io.in，直投不走 routes），见 §6 豁免清单 |
| pr | **dd work（豁免区零改动）** | **否（optional）** | `dd work.md:40-58` 信封 task 无 triplet，且豁免区禁改——见 INV-2 |
| verdict / spec-verdict | dd review（豁免）；spec-reviewer persona（本 repo，改：回声） | dd 侧否 / spec-gen 侧回声携带 | schema 不动（additionalProperties:true 宽进，`contracts/verdict.schema.json`） |
| idea | 种子（`bootstrap-loop.sh:84-94`）；spec-rework REJECT | 否（schema 不动；REJECT 路径可选回声） | 种子是纯 idea 记录**无任何 spec 字段**——亲核结论：**seed 零改动**（plan-b3 导航中"若 seed 构造含 spec 类 record 则同改"的条件不成立） |

### 1.5 数据通道机制实况（engine main=7be3aa0，行号亲核）

record 字段进入模板要过**两层**通道，缺一层模板就拿不到值：

1. **fleet 层 claim bind**（`fleet.ts:149-151`：`bound[payloadKey] = claimedRecord[recordField]`，纯字段复制，字段缺失得 `undefined`）；
2. **workflow 层 seed payload**（各 `workflow.yaml` 的 `seed[].payload` 用 `{{key}}` 从 fleet input 转填进模板 context）。

占位符纪律（`template.ts` fill）：`{{key}}` 必填——值为 `undefined/null` 即 throw，**tick 同步死亡**（B1 PR #6 的 loop_store_cli 事故同形）；`{{key?}}` 可选——缺值渲染空串。故凡上游 record **可能**缺 triplet 的通道（pr 店、verdict 店）一律用 `{{key?}}` 可选形态；上游契约**保证**存在的通道（spec-pr 店，io.in 校验后必有）用必填形态 fail-fast。

契约执法口（B2 已在，本批首次真实生效）：claim 入站 `fleet.ts:133-146`（失败→`contract_rejected` + 空转）；enqueue 出站 `engine.ts:329-334`（失败→`contract_violation` 事件 + contract_violations 哨兵 + 拒绝施加该条，**不拖垮同信封其它 effect**——complete 照常施加）。

## 2. 不变量（INV）

- **INV-1（commit pattern 是唯一硬校验，宽进严出）**：三 schema 的 `commit` 一律 `"pattern": "^[0-9a-f]{7,40}$"`——「禁分支名只认 commit hash」的机器可查形态（`"main"`、`"feature/x"`、`"HEAD"` 全被拒）。`repo` / `spec_path` 只锁 `type:string, minLength:1` **不 pattern**（本地绝对路径或 URL 都合法，宽进）；`mr` 只锁 `type:object` 宽形状。
- **INV-2（pr 的 triplet 本批为可选——拍板偏离备案）**：plan-b3 拍板文本为三 schema triplet 均 required，但 **pr 记录的唯一生产者是 dd work（豁免区零改动，`dd work.md:40-58` 信封无 triplet）**，而 spec-check/deploy-verify/merger 自 B2 起对 pr 店声明 `io.in`（各 workflow.yaml），claim 入站校验live（`fleet.ts:133-146`）——pr triplet 若 required，**首个真实投喂批的每条 pr 在 spec-check 认领处全线 `contract_rejected`，主链即死**。故本批：trigger / spec-pr 的 triplet **required**（生产面全为 bootstrap 侧可控，见 §1.4）；pr 的 triplet **声明进 properties 但不进 required**（pattern 仍对"字段在场"的值执法）。pr 升 required 是 **B4 dd 收编候选**（写范围外）。
- **INV-3（spec_file 语义降级但值不变）**：指针三元组 = SSoT；`spec_file` 降级为**派生物化字段**（dd 豁免区 4 消费点 `work.md:9,50` / `review.md:15,38` / `deploy.md:16-19,64` / `rework.md:41` 继续消费，零改动）。三 schema 的 `spec_file` 保持 required 不动，语义注释写进 schema `description`。B4 收编候选，写范围外。
- **INV-4（redo 链模式不变，triplet 继承原值）**：re-seed id 仍为 `${spec_id%%-r[0-9]*}-r$(date +%s)` 模式（`spec-check.md:36-37` 等），**不进契约 pattern**（B2 INV-3 沿用）。re-seed 的 triplet 继承**原 spec 的指针原值**——impl 重试**同 commit 合法**：PROP-3「rework = 新 commit 新消息」指 **spec 修订链**（spec 内容变了才换 commit），本批不动 spec-rework 的修订语义，impl 失败重试不改 spec 内容故不换指针。
- **INV-5（继承链闭合 + 缺值不死 tick）**：trigger 的 bootstrap 侧生产面（spec-rework APPROVE + 三 re-seed）本批**全部**携带 triplet。继承源优先级：① fleet bind 透传值（`{{repo?}}` 等，非空即用；本批 pr 店无 triplet 故为空，B4 收编后自动生效的前向兼容通道）→ ② **origin trigger 记录直读**（`$trigger_store_dir/<base_spec_id>.json` 只读文件解析——redo 链的 base id 即原 trigger 记录 id，该记录在 git 化主链上必带 triplet）→ ③ 兜底：解析全空时**照常 enqueue**，由 B2 出站闸门拦截留 `contract_violations` 哨兵（**不发明新失败通道**；complete effect 不受牵连，`engine.ts:331` 归因粒度per-effect）。任何通道缺值都不得用必填占位符导致 tick 同步死亡（B1 PR #6 教训）。
- **INV-6（dd 豁免 + 豁免必配保留断言）**：dd-plugin 四模板（work/review/rework + 遗留 deploy）零改动、零 triplet 占位符引用；dd 产 pr / verdict / rework-直投 trigger 无 triplet **合法**。豁免锚断言（恰 0 + `{{spec_file}}` 保留在场断言）主体落 SPEC-006；本 spec 的 TC 不得断言"trigger 店全量记录带 triplet"（dd rework 直投洞在场）。
- **INV-7（幂等 enqueue 既有语义零改动）**：enqueue → `putIfAbsent`（create-only，`loader.ts:297-314`）与 `enqueue_deduped` 事件既有语义不变；本批只是让被去重的记录多了 (repo,commit) 意义上的内容锚点。
- **INV-8（宽进回归）**：三 schema 保持 `"additionalProperties": true`；idea / verdict schema 零改动（verdict 回声字段靠宽进通过）。

## 3. 涉及文件与改动精确描述

### 3.1 三份 schema 正本演进（`workflows/spec-gen/contracts/`，symlink 网络不动）

三份正本统一追加 properties（`trigger.schema.json` / `spec-pr.schema.json` / `pr.schema.json`）：

```json
"repo":      { "type": "string", "minLength": 1,
               "description": "spec 所在 git repo：本地绝对路径或 URL" },
"commit":    { "type": "string", "pattern": "^[0-9a-f]{7,40}$",
               "description": "spec 内容锚定 commit（禁分支名，只认 hex hash）" },
"spec_path": { "type": "string", "minLength": 1,
               "description": "spec 文件的 repo 相对路径" },
"mr":        { "type": "object",
               "description": "可选 MR/PR 元数据，宽形状" }
```

required 变更：

| schema | required（改后全集） |
|---|---|
| trigger | `["id","status","spec_file","feedback","repo","commit","spec_path"]` |
| spec-pr | `["id","status","spec_id","spec_file","repo","commit","spec_path"]` |
| pr | **不变** `["id","status","spec_id","spec_file","branch","base_commit"]`（INV-2） |

三份正本的既有 `spec_file` property 追加 description（INV-3 语义注释，逐字）：

```json
"spec_file": { "type": "string", "minLength": 1,
  "description": "派生物化字段：指针 (repo,commit,spec_path) 是 SSoT（B3）；本字段为 dd-plugin 豁免区消费保留的物化缓存路径，B4 收编候选" }
```

symlink（13 个，B2 INV-5 网络）指向正本，演进自动透传，零新增文件。

### 3.2 drafter 出口带 triplet（`workflows/spec-gen/draft/templates/draft.md`）

- Step 3 Final Commit（:54-59）之后追加一步：final commit 后执行 `git -C {{workspace_repo}} rev-parse HEAD` 取 **spec commit**（真实 hash，禁占位串——纪律语句对齐 `dd work.md:38` 的 base_commit 措辞）。
- Step 5 信封（:69-88）的每条 spec-pr task（:79-84）追加三字段：

```json
"repo": "{{workspace_repo}}",
"commit": "<Step 4.5 的真实 rev-parse HEAD hash>",
"spec_path": "docs/specs/SPEC-XXX.md"
```

（`spec_file` 行 :83 原样保留——INV-3 值不变；spec_path 为 repo 相对路径，与 spec_file 绝对路径并存。）

### 3.3 spec-reviewer persona 回声（`workflows/spec-gen/review/personas/spec-reviewer.md`）

verdict 信封 task（:18-27）追加三行回声（必填占位符——spec-pr 契约 required + io.in 入站校验后保证在场，fail-fast 合法）：

```json
"repo": "{{repo}}",
"commit": "{{commit}}",
"spec_path": "{{spec_path}}",
```

> 为什么需要回声：spec-rework 认领的是 spec-verdict 记录，verdict schema 不动（INV-8），triplet 只能靠信封值透传。这是生产链 draft→review→rework 闭合（INV-5）的必要一环——**plan-b3 导航生产侧清单未列 persona，起草时亲核补入**（见文末与导航不符备案）。

### 3.4 spec-rework 透传（`workflows/spec-gen/rework/templates/spec-rework.md`）

- 头部 heredoc 区（:1-25）追加三个变量（可选占位符——verdict 回声是 LLM 产物非契约保证，INV-5）：

```bash
repo="$(cat <<'EOF'
{{repo?}}
EOF
)"
commit="$(cat <<'EOF'
{{commit?}}
EOF
)"
spec_path="$(cat <<'EOF'
{{spec_path?}}
EOF
)"
```

- APPROVE 路径 trigger task（:30-43）追加 `repo/commit/spec_path` 三字段（env 透传，与 :37 `spec_file` 同模式）。
- REJECT 路径 idea task（:49-63）同样追加三字段（可选回声——idea schema 不动，宽进通过；保 provenance，drafter 重写 spec 后自会产新指针）。

### 3.5 三处 re-seed 继承（spec-check / deploy-verify / merger 模板）

三个模板（`spec-check.md` / `deploy-verify.md` / `merger.md`）统一插入**同一段** triplet 解析 helper（放在 heredoc 变量区之后、主逻辑之前；三处逐字一致，便于 grep 锚）：

```bash
# --- B3 pointer triplet resolution (SPEC-005): bind 继承优先，origin trigger 兜底 ---
repo_v="$(cat <<'EOF'
{{repo?}}
EOF
)"
commit_v="$(cat <<'EOF'
{{commit?}}
EOF
)"
spec_path_v="$(cat <<'EOF'
{{spec_path?}}
EOF
)"
if [ -z "$commit_v" ]; then
  base_spec_id="${spec_id%%-r[0-9]*}"
  origin_rec="$trigger_store_dir/$base_spec_id.json"
  if [ -f "$origin_rec" ]; then
    repo_v="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).repo??""' "$origin_rec")"
    commit_v="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).commit??""' "$origin_rec")"
    spec_path_v="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).spec_path??""' "$origin_rec")"
  fi
fi
```

前置：三模板均已有 `trigger_store_dir`… **亲核**：spec-check / deploy-verify / merger 的 fleet input 均含 `trigger_store_dir`（`fleet-impl.yaml.tpl:150,172`、`fleet-merge.yaml.tpl:10`），但 **spec-check / deploy-verify / merger 模板内目前未声明该变量**——workflow.yaml seed payload 已传（`spec-check/workflow.yaml` payload `trigger_store_dir` 行），模板 heredoc 区需补 `trigger_store_dir="{{trigger_store_dir}}"`（spec-check / deploy-verify / merger 三处；deploy-verify / merger 的 payload 同名键亦已在——见 §3.7 亲核表）。

> 继承源为什么是 origin trigger 而非 pr 记录：pr 本批无 triplet（INV-2），"继承原 record 原值"的原 record 落定为 **origin trigger 记录**——它是该 spec 指针的权威载体（spec-rework APPROVE / 人工注入产出），且 redo 链 base id 天然指回它。直读 `<store>/<id>.json` 是**只读**文件访问，不触 B0 正门纪律（acceptance.sh:645/654 的恰 0 锚只拦 store-cli `put`/`update` 写路径，本 helper 不用 store-cli）。

三处 re-seed 的 trigger task 各追加三字段（env 透传，与 `SPEC_FILE` 同模式）：

- `spec-check.md`：REJECT 分支 task（:42-47）加 `repo: process.env.REPO_V, commit: process.env.COMMIT_V, spec_path: process.env.SPEC_PATH_V`（env 前缀行 :38 同步加 `REPO_V="$repo_v" COMMIT_V="$commit_v" SPEC_PATH_V="$spec_path_v"`）。
- `deploy-verify.md`：失败分支 task（:50-55）同上（env 行 :45）。
- `merger.md`：失败分支 task（:71-76）同上（env 行 :66）。

解析全空时不做特判：task 携带空串字段照常 enqueue，出站闸门以 `minLength/pattern` 拒绝并留哨兵（INV-5 ③，机器留痕召唤人工）。

### 3.6 fleet 两 tpl 的 8 处 bind

`fleet-impl.yaml.tpl` 7 处（:45 spec-review、:63 spec-rework、:88 work、:110 review、:137 rework、:159 spec-check、:182 deploy-verify）+ `fleet-merge.yaml.tpl` 1 处（:20 merger）——每处 `spec_file: spec_file` 行后追加三行（缩进对齐）：

```yaml
        repo: repo
        commit: commit
        spec_path: spec_path
```

> dd 三柱（work/review/rework）的 bind 也加：bind 是纯字段复制（`fleet.ts:149-151`），上游 record 缺字段时得 undefined、payload 落 null/缺失，dd 模板不引用这些键故**零影响**（fill 只对模板里出现的占位符求值）；加上是为 B4 收编后 dd 侧模板可直接取用（前向兼容），且与 8 处计数锚一致。**不动 dd-plugin repo 任何文件。**

### 3.7 五个 workflow.yaml seed payload 通道（导航未列层，亲核补入）

bind 只把字段送进 fleet input；模板 context 还要过各 workflow.yaml `seed[].payload` 一层（§1.5）。追加：

| workflow.yaml | payload 追加 | 占位符形态 | 理由 |
|---|---|---|---|
| `review/workflow.yaml`（payload 现有 `spec_file` 行后） | `repo: "{{repo}}"` `commit: "{{commit}}"` `spec_path: "{{spec_path}}"` | 必填 | spec-pr 契约 required + io.in 校验后保证在场，fail-fast |
| `rework/workflow.yaml` | 同上三行 | **可选 `{{repo?}}` 等** | verdict 回声无契约保证（INV-5） |
| `spec-check/workflow.yaml` | 同上三行 | 可选 | pr 本批无 triplet（INV-2） |
| `deploy-verify/workflow.yaml` | 同上三行 | 可选 | 同上 |
| `merger/workflow.yaml` | 同上三行 | 可选 | 同上 |

`draft/workflow.yaml` 零改动（drafter 自产 triplet，无入站需求）。亲核：spec-check / deploy-verify / merger 三个 workflow.yaml 的 payload 均已含 `trigger_store_dir` 行（§3.5 依赖成立）；rework payload 已含 `trigger_store_dir`、`idea_store_dir`。

### 3.8 存量测试 fixture 更新（`tests/pipeline-contracts.test.sh`）

schema 演进破坏两条既有 fixture，必须同步修（否则 acceptance 假红）：

- **:98-100 good-trigger**：现 record 无 triplet，trigger required 后必被拒——追加 `"repo":"/data/code/self/loop-engine","commit":"a1b2c3d4e5f60718293a4b5c6d7e8f9012345678","spec_path":"docs/specs/SPEC-170.md"`。
- **:131-134 wide-pr（TC-6 宽进探针）**：现探针键恰为 `"repo":"loop-engine","commit":"def456"`——`commit` 演进为已声明 property 后 `"def456"`（6 位）被 pattern 拒，TC-6 假红。探针键改为与 schema 无关的未来键（如 `"zzz_b4_future":"x"`），保持宽进断言语义纯净。
- **:126-127 good-spec-pr**（:112-114 行 cat 块）：spec-pr required 后同样要补 triplet；good-idea / good-verdict 两变体 / bad-* 各条不动（idea、verdict schema 零改动；bad-trigger 缺 spec_file 时同时也缺 triplet，仍拒，断言不变）。

### 3.9 新建 `tests/pointer-records.test.sh` + `tests/acceptance.sh` 接线

- 头部纪律镜像 `pipeline-contracts.test.sh:1-30`：`set -euo pipefail`、`ROOT`、`ENGINE_ROOT` guard（无 ajv 则 SKIP）、`DD_PLUGIN_ROOT` 缺省 `/data/code/self/loop-engine-dev-dispatch-plugin`。TC 见 §4。
- `tests/acceptance.sh`：
  - `check` 清单（:14-38 段末）追加 `check "tests/pointer-records.test.sh"`；
  - 在 pipeline-contracts 块（:626-633）之后追加同构调用块：

```bash
# --- pointer-records static tests (SPEC-005-b3-pointer-records) ---
echo "running pointer-records static tests"
if bash "$ROOT/tests/pointer-records.test.sh"; then
  echo "ok: pointer-records tests passed"
else
  echo "FAIL: pointer-records tests failed" >&2
  fail=1
fi
```

### 3.10 亲核落定：`bin/bootstrap-loop.sh` 零改动

导航条件项「seed 若含 spec 类 record 则同改」亲核结论：seed（:84-94）构造的是**纯 idea 记录** `{id, status, feedback, feedback_file}`，无任何 spec 字段，idea schema 亦不演进——**bootstrap-loop.sh 本 spec 零触碰**。

## 4. 测试要求

### RED 场景列表（tests/pointer-records.test.sh，落地前全红）

1. **TC-1（三 schema triplet 声明形状）**：node 断言三正本 `properties` 含 `repo/commit/spec_path/mr` 四键；`commit.pattern === "^[0-9a-f]{7,40}$"` 三处逐字相等；trigger/spec-pr 的 `required` 含 triplet 三键、**pr 的 `required` 不含**（INV-2 锚——升 required 是显式决策不是手滑）；三处 `spec_file.description` 非空（INV-3 注记在场）。
2. **TC-2（ajv 正反例，坏 commit="main" 被拒）**：ajv（engine 依赖树 `createRequire` 方式，镜像 pipeline-contracts.test.sh:13 纪律）编译三演进 schema 后：
   - 正例：带 hex40 triplet 的 trigger / spec-pr 记录通过；带 `-r<epoch>` 后缀 id + 同 commit 的 trigger 记录通过（INV-4：impl 重试同 commit 合法）；**无 triplet 的 pr 记录通过**（INV-2 钉死可选）；带 hex7（短 hash 下界）triplet 的 pr 记录通过。
   - 反例（≥6）：trigger `commit:"main"` 拒（pattern，拍板指定反例）；trigger `commit:"feature/x"` 拒；trigger 缺 `repo` 拒；spec-pr 缺 `commit` 拒；pr `commit:"main"`（字段在场即执法）拒；trigger `commit` 为 6 位 hex `"def456"`（低于下界）拒。
3. **TC-3（8 处 bind 计数锚，恰 N）**：`grep -Ec '^[[:space:]]+spec_path: spec_path$' workflows/fleet-impl.yaml.tpl` 恰 7、`fleet-merge.yaml.tpl` 恰 1；`'^[[:space:]]+commit: commit$'` 同（锚定行首缩进，规避 `base_commit: base_commit` 子串误伤）；`'^[[:space:]]+repo: repo$'` 同。
4. **TC-4（drafter 出口在场）**：`draft.md` grep 含 `"repo"`、`"commit"`、`"spec_path"` 三字段与 `rev-parse HEAD` 指令、且含"真实 hash 禁占位串"纪律语句。
5. **TC-5（生产链透传在场）**：`spec-reviewer.md` 含 `"repo": "{{repo}}"` 等三回声行；`spec-rework.md` 的 trigger task 含 `repo: process.env` 型三字段；三 re-seed 模板各含 helper 段哨兵注释 `B3 pointer triplet resolution (SPEC-005)`（恰 3 处）与 task 三字段。
6. **TC-6（seed payload 通道，恰 5）**：`grep -lE '^\s+spec_path: "\{\{spec_path\??\}\}"' workflows/spec-gen/*/workflow.yaml | wc -l` 恰 5（draft 无）；review 用必填形态、其余四个用可选形态（逐文件断言）。
7. **TC-7（seed 零改动锚）**：`bin/bootstrap-loop.sh` 的 idea_payload 构造段（:84-94）grep 零 `spec_path`（亲核落定 §3.10 的回归锚）。
8. **TC-8（fixture 迁移完整性）**：`bash tests/pipeline-contracts.test.sh` 全绿（TC-4/TC-6 fixture 更新后既有九 TC 零回归——含宽进探针不再借用 repo/commit 键名）。

### 组合场景断言

- 组合场景 TC-C 组（指针×契约 / 指针×redo 链 / 注入×同管道 / 幂等键）按 plan-b3 定案**由 SPEC-006 承担**（plugin acceptance 单一确定性套件，独立 composition spec 为空壳的形式偏离已在 plan-b3 备案）。
- 本 spec 落地后 fleet 渲染件带 8 处新 bind：acceptance.sh 既有 fleet-impl/fleet-merge `loadFleetManifest` 校验必须依旧全绿（bind 键为自由映射表 `z.record(z.string())`，`fleet.ts:64`，零 schema 阻力）。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（新增 pointer-records 块 + 既有全部 TC 含更新后 fixture 零回归）。
- grep 计数锚（plugin repo 根执行）：
  ```bash
  grep -Ec '^[[:space:]]+spec_path: spec_path$' workflows/fleet-impl.yaml.tpl        # 预期 7
  grep -Ec '^[[:space:]]+spec_path: spec_path$' workflows/fleet-merge.yaml.tpl       # 预期 1
  grep -c '"pattern": "^\[0-9a-f\]{7,40}\$"' workflows/spec-gen/contracts/*.schema.json | grep -c ':1$'  # trigger/spec-pr/pr 恰 3 份各 1 处
  grep -c 'B3 pointer triplet resolution (SPEC-005)' workflows/spec-gen/{spec-check,deploy-verify,merger}/templates/*.md   # 各恰 1
  grep -REc '\{\{ *(repo|commit|spec_path)\??' /data/code/self/loop-engine-dev-dispatch-plugin/workflows/spec/*/templates/*.md   # 预期全 0（豁免锚，SPEC-006 正式接管）
  git diff --name-only master -- 'workflows/spec-gen/*/contracts/*'  | wc -l          # 预期 0（symlink 网络零触碰）
  ```
- 本 spec 零改动清单自检：`bin/bootstrap-loop.sh`、`workflows/spec-gen/draft/workflow.yaml`、`contracts/{idea,verdict}.schema.json`、13 个 symlink、dd-plugin repo 任何文件。

## 6. 豁免清单

| 豁免项 | 范围 | 依据 | 锚 |
|---|---|---|---|
| dd work 产 pr 无 triplet | `dd work.md:40-58` 信封 task | dd-plugin 豁免区零改动（plan-b3 定案）；由 INV-2（pr triplet 可选）承接，B4 收编候选 | TC-2 的"无 triplet pr 通过"正例 + TC-1 的"pr required 不含 triplet"锚（**豁免必配保留断言**，B1 PR #6 教训） |
| dd review 产 verdict 无 triplet | `dd review.md:27-45` | verdict schema 零改动（INV-8 宽进），spec-rework 侧以可选占位符容忍 | TC-2 不含 verdict 反例；rework payload 可选形态锚（TC-6） |
| dd rework REJECT 直投 trigger 无 triplet | `dd rework.md:36-48`（store-cli put 直调，B0 豁免项延续） | 该路径不经 routes/io 闸门，trigger required 对其无执法面；其 redo 链 base id 指回的 origin trigger 仍带 triplet（INV-5 ②可解析） | 本 spec TC 不断言 trigger 店全量带 triplet（INV-6）；洞记录在案，B4 收编候选 |
| 人工/机械交接手投 pr 记录无 triplet | 操作员 runbook 路径 | 与 dd work 产出同闸门（生产者无关）：pr triplet 可选即合法 | 同 INV-2 锚 |

# References
- 设计 SSoT：`../../design.md` §2 B3 行 + §3.3 指针消息（用户 2026-07-04 拍板）；PROP-3 原文 `../../../loop-engine-概念梳理-问题清单/issues.md`
- 批次定案：`../../plan-b3.md` 定案段（2026-07-05 21:40）——engine/store 零改动、triplet=SSoT、spec_file=派生物化、幂等键落注入口、redo 链保持 `-r<epoch>`
- 动机活体：`../../progress.md` 2026-07-04 23:31/23:35（SPEC-168 机械交接）、`../../acceptance-b1.md`（SPEC-169 parse_failed）
- engine 签名核对（main=7be3aa0，本批零改动）：`src/fleet.ts:64,113-116,133-146,149-151`（bind 自由映射 / 契约装配 / 入站执法 / 纯字段复制）、`src/template.ts` fill（`{{key}}` 必填 throw / `{{key?}}` 可选空串）、`src/loader.ts:297-314`（enqueue→putIfAbsent create-only）、`src/engine.ts:329-334`（出站执法 per-effect 归因）、`src/lib/store.ts:94-112`（putIfAbsent O_EXCL）
- plugin 实况核对（master=b087fd0）：`draft.md:54-59,69-88`、`spec-reviewer.md:12-30`、`spec-rework.md:30-43,49-63`、`spec-check.md:36-52`、`deploy-verify.md:45-59`、`merger.md:66-80`、`fleet-impl.yaml.tpl:45,63,88,110,137,159,182`、`fleet-merge.yaml.tpl:20`、`bootstrap-loop.sh:84-94`、`tests/pipeline-contracts.test.sh:98-134`、`tests/acceptance.sh:14-38,626-633`
- record 实况样本：`~/.loop-engine/bootstrap/b1-20260705-135500/stores/trigger/*.json`（操作员投喂形状：feedback_file 承载 impl-plan 路径）
- 豁免锚教训：plugin PR #6（`edb1a85`，清零断言误伤豁免项）
