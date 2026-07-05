# SPEC-007-b4-input-primitives-anchors — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先确认 RED（真红或注错自证，见 spec §4 RED 纪律），最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`
> 前置：dd-plugin master@3838d72（PR #4 已合入，**只读**，任何 dd 文件改动 = 违规）；engine 零依赖（静态 TC 不需 dist；行为 TC 需 `dist/template.js` + `dist/lib/store-cli.js`，缺则 SKIP）。
> **起步事实**：基线 master@33939fc 上 `bash tests/acceptance.sh` 已红——`pointer-consumption.test.sh` TC-D1 count=9 expected 0（dd PR #4 合入的必然后果）。第一步就是修它。

## Files

**Modify（精确路径）：**
- `tests/pointer-consumption.test.sh`（TC-D1 豁免锚迁移：glob 缩 deploy + 注释指向本 spec；`{{spec_file}}` 保留断言四模板不缩）
- `workflows/spec-gen/contracts/verdict.schema.json`（feedback_file description 逐字，spec §3.2；其余字节不动）
- `tests/acceptance.sh`（check 清单 + input-primitives 调用块，spec §3.5 逐字）

**Create：**
- `tests/input-primitives.test.sh`（TC-1~TC-10）

**禁止触碰：**
- dd-plugin repo 任何文件（`/data/code/self/loop-engine-dev-dispatch-plugin`）
- `contracts/{idea,trigger,spec-pr,pr}.schema.json` 四正本、13 个 symlink 的链接结构
- 六工序模板与 personas、五 workflow.yaml、`workflows/*.tpl`、`bin/*`
- `tests/complete-effect.test.sh`（TC-12 恰 1 锚逐字不动——spec INV-5）、`tests/pipeline-contracts.test.sh`（TC-9 不动）、`tests/pointer-records.test.sh`

## Interfaces

**Consumes：**
- spec §3.6 dd 实况锚清单（全部 grep 断言的行号依据；实现时以该表为准亲核一遍再落断言）
- spec §3.4 裸路径口径 `np_hits()`（逐字）；§3.2 description（逐字）
- `render_template` 模式：`tests/pointer-consumption.test.sh:138-157`（engine `fill`，ctx 空白切分——fixture 值一律无空格）
- `LOOP_STORE_CLI` 缺省式：`acceptance.sh:77`

**Produces：**
- TC-D1 翻转后的豁免锚（deploy 恰 0 / 四模板 spec_file 保留）
- `tests/input-primitives.test.sh` TC-1~TC-10（dd 收编锚集 / `.dd-review` 正名锚 / 裸路径北极星 / pr optional 双锚 / rework fixture 回归三连）
- verdict.schema.json 的 `.dd-review` 正名 description（校验行为零变化）

## TDD 步骤（bite-sized，每步 commit）

### Step 1：TC-D1 豁免锚迁移（修当前红）

1. 跑 `bash tests/pointer-consumption.test.sh` **确认现红**：`FAIL: TC-D1 dd-plugin triplet placeholder count=9 expected 0`。
2. 按 spec §3.1 改三处：`dd_tpls` glob（:101）`{work,review,deploy,rework}` → `{deploy}`（仅 triplet 恰 0 断言用）；`{{spec_file}}` 保留断言的文件列表**单列四模板全量不变**（如原实现共用 `dd_tpls`，拆成两个数组：`dd_zero_tpls`=deploy、`dd_sf_tpls`=四模板）；段头注释追加 B4 收编指向行（spec §3.1 第 3 点逐字）。
3. `bash tests/pointer-consumption.test.sh` 全绿；`bash tests/acceptance.sh` 全绿（回到基线绿）。

commit：`test: TC-D1 豁免锚随 dd B4 收编翻转——triplet 恰 0 缩至 deploy（SPEC-007）`

### Step 2：失败骨架——TC-5 正名锚（真红）+ 静态锚组 TC-1~TC-4/TC-6/TC-7

1. 新建 `tests/input-primitives.test.sh`：头部纪律（spec §3.3——ROOT/ENGINE_ROOT/DD_PLUGIN_ROOT/LOOP_STORE_CLI 四缺省 + SKIP 分层）；落 TC-5（description 非空含 `.dd-review` + required/enum/additionalProperties 反向零漂移 + symlink 恰 2/恰 13）与 TC-1~TC-4、TC-6、TC-7 全部静态锚（断言值以 spec §4 为准，锚依据 §3.6 表）。
2. 跑 `bash tests/input-primitives.test.sh`：**TC-5 红**（description 未加），其余绿。若 TC-1~TC-4/TC-6/TC-7 有任何红：先亲核 dd@3838d72 与本 repo 实况，**是断言写错就改断言，是实况漂移就停下上报**（spec 基线失效），禁擅自改产物凑绿。
3. 注错自证（写完即绿的静态锚抽两处）：把 TC-2 的恰 3 改恰 4、TC-4 的恰 1 改恰 0 各跑一次红，改回，确认 harness 真执行。

commit：`test: input-primitives 失败骨架——.dd-review 正名锚红 + dd 收编静态锚/裸路径北极星/pr optional 双锚`

### Step 3：verdict.schema.json 正名（TC-5 绿）

1. 按 spec §3.2 给 `feedback_file` 加 description（逐字）；文件其余字节不动。
2. `bash tests/input-primitives.test.sh` TC-5 绿；`bash tests/pipeline-contracts.test.sh` 全绿（INV-3 行为证明：ajv fixture 零迁移仍绿）；`git diff --stat` 确认只动 verdict 正本一文件。

commit：`feat: .dd-review 收编正名——verdict.feedback_file description 落 PROP-2 注入数据合规形态（SPEC-007）`

### Step 4：rework fixture 行为组 TC-8~TC-10

1. 补 `render_template` helper（逐字镜像 pointer-consumption.test.sh:138-157）与 mktemp fixture（trap 清理）。按 spec §4 TC-8/9/10 落三用例：REJECT 带 triplet（enqueue 闭环 + redo id + triplet 逐字 + trigger store 零 json + pr rejected）/ REJECT 不带（三键省略 + 键集合逐字）/ APPROVE 回归（halt + approved + trigger 零）。
2. 跑绿后**逐 TC 注错自证**：TC-8 的 id 正则、TC-9 的键集合、TC-10 的 halt 各注错一次跑红改回（spec §4 RED 纪律，防永绿断言）。
3. ENGINE dist 缺失路径：临时 `ENGINE_ROOT=/nonexistent bash tests/input-primitives.test.sh` 确认 SKIP 不 FAIL；`DD_PLUGIN_ROOT=/nonexistent` 同。

commit：`test: dd rework 收编行为固化——REJECT triplet 闭环/省略语义/APPROVE 回归三连（operator 冒烟 TC 化）`

### Step 5：acceptance 接线 + 全量回归 + INV 自检

1. `tests/acceptance.sh`：check 清单加 `tests/input-primitives.test.sh`；pointer-consumption 块后加调用块（spec §3.5 逐字）。
2. `bash tests/acceptance.sh` 全绿。
3. spec §5 grep 锚清单全跑一遍 + 零改动清单自检（`git diff --name-only` 恰 4 文件；`git -C $DD_PLUGIN_ROOT status --porcelain` 空）。

commit：`test: input-primitives 接入 acceptance + B4 豁免余量锚终检（SPEC-007）`

## INV 自检清单

- [ ] INV-1：dd repo `git status` 零改动；全部 dd 访问为 grep/render 只读
- [ ] INV-2：pr.schema.json 零改动；TC-7 与 pointer-records TC-1 双锚同绿（required 不含 triplet）
- [ ] INV-3：verdict.schema.json 仅 description 差异（`git diff` 逐行核）；pipeline-contracts 零 fixture 迁移仍全绿
- [ ] INV-4：TC-D1 翻转后 deploy 恰 0 + spec_file 保留四模板；deploy put 恰 1 / rework update 恰 2 保留锚在场
- [ ] INV-5：complete-effect.test.sh 零改动；TC-12 恰 1 仍绿（fleet tpl loop_store_cli 未被误伤）
- [ ] INV-6：北极星 `np_hits` 两文件集恰 0；口径注释逐字含亲核日期与排除规则依据
- [ ] INV-7：`git diff --name-only` 恰 4 文件，不含六工序模板/四 schema/tpl/bin
- [ ] INV-8：pipeline-contracts TC-9（dd 零 io）仍绿未动
- [ ] symlink 网络：`find workflows/spec-gen/*/contracts -name '*.schema.json' -type l | wc -l` 仍恰 13；verdict symlink 恰 2
