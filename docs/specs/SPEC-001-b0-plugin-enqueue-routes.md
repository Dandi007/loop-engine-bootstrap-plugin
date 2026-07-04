# SPEC-001: plugin (a) 类迁移 —— spec-rework / spec-check / deploy-verify / merger 直投路径改 enqueue effect + routes

> 批次：组件模型 B0（ISSUE-2 收编：投递全走正门）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`）
> 依赖序：本 spec 无前置依赖，plugin B0 最先投喂；与 `SPEC-001-b0-plugin-complete-effect` 共改同一组模板，**本 spec 先合入**（避免文本冲突，各自独立可验收）。
> 定案来源：`../../b0-inventory.md` §二.2.1 (a) 类 5 条（P-a1~P-a5）。

## 1. 背景

plugin spec-gen 工作流中有 5 处直接调用 `node "$loop_store_cli" "$store_dir" put "$payload"` 往外部 store 投新记录，绕过引擎路由表：

| 盘点 ID | 文件 | 路径 | 用途 |
|---------|------|------|------|
| P-a1 | `workflows/spec-gen/rework/templates/spec-rework.md:42` | `trigger_store_dir` | APPROVE：往 Impl Loop trigger store 投新 spec |
| P-a2 | `workflows/spec-gen/rework/templates/spec-rework.md:58` | `idea_store_dir` | REJECT：往 idea store 投 draft 任务 |
| P-a3 | `workflows/spec-gen/spec-check/templates/spec-check.md:49` | `trigger_store_dir` | spec 缺失：投 redo trigger |
| P-a4 | `workflows/spec-gen/deploy-verify/templates/deploy-verify.md:60` | `trigger_store_dir` | acceptance 失败：投 redo trigger |
| P-a5 | `workflows/spec-gen/merger/templates/merger.md:82` | `trigger_store_dir` | merge 失败：投 redo trigger |

迁移方案：在各 `workflow.yaml` 加 `routes:` 声明，模板把 put 调用换为在 JSON 结果 envelope 的 `effects` 数组里吐 `{op:"enqueue", queue:"...", task:{...}}`，引擎按路由表施加。

## 2. 不变量（INV）

- **INV-1（缺省行为逐字不变）**：`routes` 在各 workflow.yaml 内已声明，对不涉及本次改动路径（如 spec-check 的 PASS 路径）行为完全不变。已有 `{op:"halt"}` 结构保持原位。
- **INV-2（enqueue 语义等价于 put）**：5 处原始调用均是非幂等 `put`（非 `put-if-absent`），enqueue effect 的语义与 put 一致；task payload 字段与原 JSON 逐字对齐（id / status / spec_file / feedback 等字段名不变）。
- **INV-3（过渡期 loop_store_cli 保留在 spec-check / deploy-verify / merger）**：P-b1~P-b4（update 直调）直至 `SPEC-001-b0-plugin-complete-effect` 合入才能清除。本 spec **仅**移除 spec-rework 模板和 workflow.yaml 里的 `loop_store_cli`；spec-check / deploy-verify / merger 的 `loop_store_cli` 在 workflow.yaml 和 fleet template 里暂时保留。
- **INV-4（fleet template 同步）**：`fleet-impl.yaml.tpl` 中 spec-rework pipeline 的 `input:` 段移除 `loop_store_cli: ${LOOP_STORE_CLI}` 注入（不再需要）；spec-check / deploy-verify 段以及 `fleet-merge.yaml.tpl` 的 merger 段暂不动。
- **INV-5（trigger/idea store dir 保留在 payload）**：`trigger_store_dir` / `idea_store_dir` 从模板 bash 体移除（不再作为 bash 变量使用），但仍作为 workflow.yaml `payload:` 字段存在，供 `routes:` 引用（引擎渲染路由时需要其值）。

## 3. 涉及文件与改动精确描述

### 3.1 `workflows/spec-gen/rework/workflow.yaml`

**新增** `routes:` 顶级字段（在 `seed:` 之前）：

```yaml
routes:
  trigger:
    store: "{{trigger_store_dir}}"
  idea:
    store: "{{idea_store_dir}}"
```

**移除** `seed[0].payload` 中的 `loop_store_cli: "{{loop_store_cli}}"` 行。  
（`idea_store_dir` / `trigger_store_dir` 保留在 payload，供 routes 引用。）

### 3.2 `workflows/spec-gen/rework/templates/spec-rework.md`

**移除** 模板头部三行 bash 变量赋值：
```bash
loop_store_cli="{{loop_store_cli}}"
idea_store_dir="{{idea_store_dir}}"
trigger_store_dir="{{trigger_store_dir}}"
```

**APPROVE 路径重构**（原 lines 30-42）：

旧（construct payload → put → fall through to trailing halt）：
```bash
trigger_payload="$(... JSON.stringify({id, status:"open", spec_file, feedback:"(none)"}); ...)"
node "$loop_store_cli" "$trigger_store_dir" put "$trigger_payload" >/dev/null
```

新（在 APPROVE 分支末直接 emit 含 enqueue 的完整 result envelope，**不再走到文件末尾的 trailing halt emit**）：
```bash
SPEC_ID="$spec_id" SPEC_FILE="$spec_file" node -e '
process.stdout.write(JSON.stringify({
  result: "spec-rework APPROVE: enqueued trigger for " + process.env.SPEC_ID,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "(none)",
    }},
    { op: "halt" },
  ],
}));
'
exit 0
```

**REJECT 路径重构**（原 lines 43-62）：

旧：
```bash
idea_payload="$(... JSON.stringify({id: rework_idea_id, status:"open", spec_file, feedback_file, feedback:...}); ...)"
node "$loop_store_cli" "$idea_store_dir" put "$idea_payload" >/dev/null
```

新（在 REJECT 分支末 emit，加 `exit 0`）：
```bash
IDEA_ID="$rework_idea_id" SPEC_FILE="$spec_file" FEEDBACK_FILE="$feedback_file" FEEDBACK="$feedback" node -e '
process.stdout.write(JSON.stringify({
  result: "spec-rework REJECT: enqueued idea " + process.env.IDEA_ID,
  effects: [
    { op: "enqueue", queue: "idea", task: {
        id: process.env.IDEA_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback_file: process.env.FEEDBACK_FILE,
        feedback: "Spec review REJECT on a previous attempt. Read the full review and address every point. Summary: " + process.env.FEEDBACK,
    }},
    { op: "halt" },
  ],
}));
'
exit 0
```

**移除** 文件末尾的 trailing halt emit（原 line 64），因为 APPROVE/REJECT 分支各自 emit 后 `exit 0`，else 分支 `exit 1` 不变。

### 3.3 `workflows/spec-gen/spec-check/workflow.yaml`

**新增** `routes:` 字段：

```yaml
routes:
  trigger:
    store: "{{trigger_store_dir}}"
```

（`loop_store_cli` 保留在 payload 直至 Spec 2 合入，见 INV-3。）

### 3.4 `workflows/spec-gen/spec-check/templates/spec-check.md`

**移除** 模板中 `trigger_store_dir="{{trigger_store_dir}}"` bash 变量赋值行（bash 体不再直接用此变量；routes 配置由 workflow.yaml 提供）。

**FAIL 路径改动**（原 lines 36-56）——仅改 put 调用（P-a3），保留 update 调用（P-b2，Spec 2 处理）：

旧（在 if 块内单独 put，再后续 emit）：
```bash
node "$loop_store_cli" "$trigger_store_dir" put "$redo_payload" >/dev/null
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" '{"status":"rejected"}' checking >/dev/null
RESULT="spec-check rejected $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [{ op: "halt" }],
}));
'
```

新（update 保留，put 移入 envelope effects）：
```bash
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" '{"status":"rejected"}' checking >/dev/null
REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" FEEDBACK="$feedback_msg" RESULT="spec-check rejected $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "REJECT: the approved spec file is missing from the implementation branch. Ensure the spec file is committed to the branch and try again.",
    }},
    { op: "halt" },
  ],
}));
'
```

> 注：`feedback_msg` 变量为 redo payload 的 feedback 字段值，在旧模板里拼在 `redo_payload` 里。新模板直接作为常量字符串写进 task 里（与旧 JSON 字段逐字一致）。

### 3.5 `workflows/spec-gen/deploy-verify/workflow.yaml`

```yaml
routes:
  trigger:
    store: "{{trigger_store_dir}}"
```

（`loop_store_cli` 保留在 payload。）

### 3.6 `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`

**移除** `trigger_store_dir="{{trigger_store_dir}}"` bash 变量赋值行。

**失败路径改动**（原 lines 47-61）——仅改 put（P-a4），update 行（P-b3）在其他位置处理（Spec 2）：

旧（if 块内单独 put）：
```bash
node "$loop_store_cli" "$trigger_store_dir" put "$redo_payload" >/dev/null
```

新（删除该行；把 enqueue task 注入到末尾 result emit 的 effects 里，根据 `verify_status` 条件决定是否含 enqueue）：

修改末尾 result emit（原 lines 63-67）：
```bash
if [ "$verify_status" != "ready-to-merge" ]; then
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" FAILURE_REASON="$failure_reason" RESULT="deploy-verify $verify_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "Deploy-verify acceptance FAILED on branch. Fix the cause:\n" + process.env.FAILURE_REASON,
    }},
    { op: "halt" },
  ],
}));
'
else
  RESULT="deploy-verify $verify_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [{ op: "halt" }],
}));
'
fi
```

### 3.7 `workflows/spec-gen/merger/workflow.yaml`

```yaml
routes:
  trigger:
    store: "{{trigger_store_dir}}"
```

（`loop_store_cli` 保留在 payload。）

### 3.8 `workflows/spec-gen/merger/templates/merger.md`

**移除** `trigger_store_dir="{{trigger_store_dir}}"` bash 变量赋值行。

**失败路径改动**（原 lines 69-83）——仅改 put（P-a5），update 行（P-b4）另处处理（Spec 2）：

旧：
```bash
node "$loop_store_cli" "$trigger_store_dir" put "$redo_payload" >/dev/null
```

修改末尾 result emit，与 deploy-verify 同形：
```bash
if [ "$merge_status" != "merged" ]; then
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" FAILURE_REASON="$failure_reason" RESULT="merge $merge_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "Merge phase FAILED. Fix the issue and re-submit:\n" + process.env.FAILURE_REASON,
    }},
    { op: "halt" },
  ],
}));
'
else
  RESULT="merge $merge_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [{ op: "halt" }],
}));
'
fi
```

### 3.9 `workflows/fleet-impl.yaml.tpl` — spec-rework input 段

**移除** spec-rework pipeline 的 `input:` 段中的：
```yaml
      loop_store_cli: ${LOOP_STORE_CLI}
```
（spec-rework 模板不再使用 loop_store_cli。`idea_store_dir`、`trigger_store_dir` 保留，供 routes 渲染用。）

spec-check / deploy-verify pipeline 的 `input:` 段**保持不变**（过渡期保留 loop_store_cli）。

## 4. 测试要求

新建 `tests/enqueue-routes.test.sh`（bash integration test）。验收范式：用真实 node 跑各 workflow template，传入 fixture store dirs 和 mock payloads，断言输出 envelope 含正确 enqueue effects 且 store dir 文件计数不变（即不发生直接 put）。

### RED 场景列表

1. **P-a1（APPROVE）**：spec-rework 模板收 `verdict=APPROVE`，输出 envelope 的 `effects[0]` 为 `{op:"enqueue", queue:"trigger", task:{id, status:"open", spec_file, feedback:"(none)"}}`，且 trigger store dir 文件数量不变（未被直接写入）。
2. **P-a2（REJECT）**：spec-rework 模板收 `verdict=REJECT`，输出 envelope 的 `effects[0]` 为 `{op:"enqueue", queue:"idea", task:{id:rework_idea_id, status:"open", spec_file, feedback:<含"Spec review REJECT">}}`，idea store 文件数不变。
3. **P-a3（spec-check FAIL）**：spec-check 模板在 spec 缺失路径，输出 envelope 含 `{op:"enqueue", queue:"trigger", task:{...}}` effect；trigger store 文件数不变（put 已被移除）。
4. **P-a4（deploy-verify 失败）**：deploy-verify 模板 `verify_status=verify_failed`，输出含 enqueue trigger effect；trigger store 文件数不变。
5. **P-a5（merger 失败）**：merger 模板 `merge_status=merge_failed`，输出含 enqueue trigger effect；trigger store 文件数不变。
6. **deploy-verify 成功路径（回归 INV-1）**：`verify_status=ready-to-merge`，输出 effects 只含 `{op:"halt"}`，无 enqueue。
7. **merger 成功路径（回归 INV-1）**：`merge_status=merged`，输出 effects 只含 `{op:"halt"}`，无 enqueue。

### 组合场景断言

- **enqueue task 字段与原 put payload 逐字一致（INV-2）**：取 P-a1 输出的 task，与旧 `trigger_payload` JSON 字段名集合比对——`id` / `status` / `spec_file` / `feedback` 全部命中，无多余字段。
- **过渡期 spec-check update 仍执行（INV-3）**：spec-check FAIL 路径的模板，既含 enqueue trigger effect，又执行了 `update pr_id {status:"rejected"} checking`（验证 update 调用未被误删）。

## 5. 验收

- `bash tests/acceptance.sh` 全绿（含上述新增测试场景）。
- grep 断言（在 plugin repo 根执行）：
  ```bash
  grep -rn 'node.*loop_store_cli.*put\|"$loop_store_cli".*put' workflows/spec-gen/*/templates/*.md | wc -l
  # 预期：0（P-a1~P-a5 全部迁移完成）
  ```
- `bash tests/acceptance.sh` 中 spec-check PASS 路径、deploy-verify 成功路径、merger 成功路径均全绿（回归 INV-1）。

## 6. 豁免清单（本 spec 无新豁免）

本 spec 覆盖全部 P-a 类 5 条，无豁免。

# References
- 盘点条目：`../../b0-inventory.md` §二.2.1 (a) 类 P-a1~P-a5
- 路由机制：engine `src/engine.ts` routes 处理段（enqueue effect 施加）
- 模板原文：`/data/code/self/loop-engine-bootstrap-plugin/workflows/spec-gen/rework/templates/spec-rework.md`、`spec-check/templates/spec-check.md`、`deploy-verify/templates/deploy-verify.md`、`merger/templates/merger.md`
