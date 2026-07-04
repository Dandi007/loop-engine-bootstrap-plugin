# SPEC-002-b0-plugin-complete-effect — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 前置：`SPEC-002-b0-plugin-enqueue-routes` 已合入；engine `SPEC-002-b0-complete-effect` 已合入且 engine 依赖已更新。
> 验收命令：`bash tests/acceptance.sh`

## Files

**Modify：**
- `workflows/spec-gen/spec-check/templates/spec-check.md`
- `workflows/spec-gen/spec-check/workflow.yaml`
- `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`
- `workflows/spec-gen/deploy-verify/workflow.yaml`
- `workflows/spec-gen/merger/templates/merger.md`
- `workflows/spec-gen/merger/workflow.yaml`
- `workflows/fleet-impl.yaml.tpl`（spec-check / deploy-verify input 段）
- `workflows/fleet-merge.yaml.tpl`（merger input 段）

**Create：**
- `tests/complete-effect.test.sh`

## Interfaces

**Consumes：**
- `../../b0-inventory.md` §二.2.2 P-b1~P-b4
- enqueue-routes spec（已合入，模板 FAIL 路径已有 enqueue effect；本 spec 在此基础上叠加 complete）
- engine complete effect 机制（`{op:"complete", status}` schema + fleet completeRecord 注入）

**Produces：**
- 3 个模板：update 直调全替换为 complete effect
- 3 个 workflow.yaml：loop_store_cli / pr_store_dir payload 字段清除
- 2 个 fleet template：loop_store_cli input 字段清除
- tests/complete-effect.test.sh：7 RED 场景 + 2 组合断言

## TDD 步骤

### Step 1：写失败测试（P-b1 spec-check PASS → ready-to-deploy）

```bash
# tests/complete-effect.test.sh TC-01
output=$(... run spec-check template with PASS condition ...)
echo "$output" | node -e '
const e = JSON.parse(require("fs").readFileSync(0,"utf8"));
const hasComplete = e.effects.some(ef => ef.op === "complete" && ef.status === "ready-to-deploy");
process.exit(hasComplete ? 0 : 1);
'
```

确认红（当前 effects 只含 halt）。

### Step 2：spec-check 模板 PASS 路径改 complete（P-b1）

编辑 `spec-check.md`：
1. 删除 `loop_store_cli="{{loop_store_cli}}"` 和 `pr_store_dir="{{pr_store_dir}}"` 行。
2. 删除 PASS 路径的 `node ... update ... ready-to-deploy` 行。
3. 把 `{op:"complete", status:"ready-to-deploy"}` 加进 PASS 路径 emit 的 effects（参见 spec §3.1）。

TC-01 绿。

### Step 3：spec-check 模板 FAIL 路径改 complete（P-b2）

编辑 spec-check.md FAIL 路径：
1. 删除 `node ... update ... rejected` 行。
2. FAIL 路径 emit 的 effects：在已有 `{op:"enqueue",...}` 之前插入 `{op:"complete", status:"rejected"}`（参见 spec §3.1 FAIL 路径新代码）。

新增 TC-02（FAIL → complete rejected），确认绿。

commit：`feat: P-b1/P-b2 spec-check → complete effect`

### Step 4：spec-check workflow.yaml 清理

从 payload 删除 `loop_store_cli` 和 `pr_store_dir` 字段。从 fleet-impl.yaml.tpl 的 spec-check input 段删除 `loop_store_cli` 行。确认 `bash tests/acceptance.sh` 通过。

commit：`chore: spec-check workflow.yaml + fleet template cleanup (INV-5)`

### Step 5：deploy-verify 模板改 complete（P-b3）

编辑 `deploy-verify.md`：
1. 删除 `loop_store_cli` / `pr_store_dir` bash 变量行。
2. 删除 `node ... update ... "$verify_status"` 行。
3. 两分支末尾 emit 均加 `{op:"complete", status: process.env.VERIFY_STATUS}` 在最前（参见 spec §3.3）。

新增 TC-03（ready-to-merge）、TC-04（verify_failed），确认绿。

编辑 `deploy-verify/workflow.yaml`：删除 `loop_store_cli` / `pr_store_dir` payload 字段。
编辑 `fleet-impl.yaml.tpl` deploy-verify input 段：删除 `loop_store_cli` 行。

commit：`feat: P-b3 deploy-verify → complete effect`

### Step 6：merger 模板改 complete（P-b4）

编辑 `merger.md`：
1. 删除 `loop_store_cli` / `pr_store_dir` bash 变量行。
2. 删除 `node ... update ... "$merge_status"` 行（原 line 65）。
3. 两分支末尾 emit 均加 `{op:"complete", status: process.env.MERGE_STATUS}`（参见 spec §3.5）。

新增 TC-05（merged）、TC-06（merge_failed）、TC-07（merge_conflict），确认绿。

编辑 `merger/workflow.yaml` 和 `fleet-merge.yaml.tpl`：同上清理。

commit：`feat: P-b4 merger → complete effect`

### Step 7：组合断言 + 全量验收

新增 TC-verify：P-b3 失败路径 effects 顺序（complete index < enqueue index）。

```bash
bash tests/acceptance.sh

# INV-5 全清
grep -rn 'node.*loop_store_cli' workflows/spec-gen/*/templates/*.md | wc -l  # 预期 0
grep -n 'loop_store_cli' workflows/fleet-impl.yaml.tpl workflows/fleet-merge.yaml.tpl  # 预期 0 行
```

commit：`test: complete-effect acceptance + INV-5 grep assertions`

## INV 自检清单

- [ ] INV-1：检查 package.json / engine 依赖版本号 ≥ complete-effect spec 合入的 engine 版本
- [ ] INV-2：fleet-impl.yaml.tpl 的 spec-check / deploy-verify claim 块未被修改（claim.store_dir / claim.bind 字段原样保留）
- [ ] INV-3：deploy-verify / merger PASS 路径 TC 中 `status` 字段值与原 `update` 调用的状态字符串逐字一致
- [ ] INV-4：P-b3 / P-b4 多终态 TC 覆盖全部可能 status 值（ready-to-merge / verify_failed / merged / merge_failed / merge_conflict）
- [ ] INV-5：grep 断言两条均为 0（templates + fleet templates）
- [ ] INV-6：trigger_store_dir 字段仍在三个 workflow.yaml payload 中（grep 确认）
