# SPEC-002: plugin (b) 类迁移 —— spec-check / deploy-verify / merger PR 终态更新改 complete effect

> 批次：组件模型 B0（ISSUE-2 收编：投递全走正门）
> repo：plugin（`/data/code/self/loop-engine-bootstrap-plugin`）
> 依赖序：**在 `SPEC-002-b0-plugin-enqueue-routes` 之后合入**（共改同一组模板，先合 enqueue-routes 避免文本冲突）；**前置：engine `SPEC-002-b0-complete-effect` 已合入主分支，且 plugin workspace 的 engine 依赖已更新到含该 spec 的版本**（completeRecord 注入机制必须在引擎侧先存在）。
> 定案来源：`../../b0-inventory.md` §二.2.2 (b) 类 4 条（P-b1~P-b4）+ 「Task 3 定案」方案乙覆盖表。

## 1. 背景

plugin spec-gen 工作流中有 4 处直接调用 `node "$loop_store_cli" "$pr_store_dir" update "$pr_id" '{"status":"..."}' <from_status>` 更新既有 PR 记录终态，绕过引擎：

| 盘点 ID | 文件 | 原操作 | complete effect status |
|---------|------|--------|------------------------|
| P-b1 | `spec-check/templates/spec-check.md:28` | PR `checking→ready-to-deploy` | `"ready-to-deploy"` |
| P-b2 | `spec-check/templates/spec-check.md:50` | PR `checking→rejected` | `"rejected"` |
| P-b3 | `deploy-verify/templates/deploy-verify.md:45` | PR `verifying→ready-to-merge` 或 `verify_failed` | `"ready-to-merge"` / `"verify_failed"` |
| P-b4 | `merger/templates/merger.md:65` | PR `merging→merged` / `merge_failed` / `merge_conflict` | `"merged"` / `"merge_failed"` / `"merge_conflict"` |

P-b3 / P-b4 为多终态（运行时决定），须用方案乙（complete effect）而非方案甲（fleet auto-complete 单一 success_status）。P-b1 / P-b2 虽然每路径终态固定，但与 P-b3/P-b4 在同一模板组且同属 `complete effect` 语义，统一迁移。

迁移方案：模板删除直调 `update` 行，改在 result envelope 的 effects 数组里吐 `{op:"complete", status:"<终态>"}` effect；引擎通过 fleet claim 注入的 `completeRecord` 回调施加（`ifStatus: claim.to` 守卫保证幂等）。同步清理 workflow.yaml payload 和 fleet template 中的 `loop_store_cli` / `pr_store_dir`（本 spec 合入后这两字段在 spec-check/deploy-verify/merger 中已无用）。

## 2. 不变量（INV）

- **INV-1（前置引擎版本）**：plugin workspace 的 engine 依赖版本必须 ≥ 含 `SPEC-002-b0-complete-effect` 的版本；否则 `{op:"complete"}` 被引擎忽略（因 Effect schema 无此 op），PR 记录永远不会被推进终态，形成静默错误。投喂前人工确认依赖版本。
- **INV-2（completeRecord 由 fleet claim 注入）**：spec-check / deploy-verify / merger 在 `fleet-impl.yaml.tpl` / `fleet-merge.yaml.tpl` 中均有 `claim:` 块（`from:approved/to:checking` / `from:ready-to-deploy/to:verifying` / `from:ready-to-merge/to:merging`）。引擎收到 complete effect 后通过注入的 `completeRecord(status)` 调用 `store.update(claimed_id, {status}, {ifStatus: claim.to})`，`claim.to` 即当前已认领状态。无需改动 claim 块本身。
- **INV-3（ifStatus 守卫幂等，INV-4 from engine spec）**：complete effect 施加带 `ifStatus: claim.to` 守卫（engine 侧实现）；若 PR 已被推离 `claim.to`（重试或其他 worker 抢先），complete 是 no-op（`ev:"complete_noop"`），不覆盖已推进状态。
- **INV-4（多终态正确性）**：P-b3（`verify_status`）、P-b4（`merge_status`）的终态字符串在 bash 变量中运行时确定，template 把变量值填进 `{op:"complete", status:"$verify_status"}` JSON 字符串——注意 bash 变量替换在 node -e 的 shell 层完成，status 值与原 update 调用的终态字串逐字一致。
- **INV-5（loop_store_cli / pr_store_dir 全清）**：spec-check / deploy-verify / merger 的 workflow.yaml payload 和 fleet template input 中，`loop_store_cli` 和 `pr_store_dir`（模板体用途）合入后均可移除；此为**本 spec 的强制交付项**，确保过渡期遗留变量清零。
- **INV-6（trigger_store_dir 保留）**：`trigger_store_dir` 字段在三个 workflow.yaml payload 中保留（供 enqueue-routes 的 `routes:` 引用）；fleet template 对应 input 字段保留。

## 3. 涉及文件与改动精确描述

### 3.1 `workflows/spec-gen/spec-check/templates/spec-check.md`

**移除** bash 变量赋值行：
```bash
loop_store_cli="{{loop_store_cli}}"
pr_store_dir="{{pr_store_dir}}"
```

**PASS 路径（P-b1）改动**（原 lines 28-34）：

旧：
```bash
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" '{"status":"ready-to-deploy"}' checking >/dev/null
RESULT="spec-check passed $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [{ op: "halt" }],
}));
'
```

新：
```bash
RESULT="spec-check passed $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: "ready-to-deploy" },
    { op: "halt" },
  ],
}));
'
```

**FAIL 路径（P-b2）改动**（原 lines 49-56）：

旧：
```bash
node "$loop_store_cli" "$trigger_store_dir" put "$redo_payload" >/dev/null  ← 已由 enqueue-routes spec 迁移
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" '{"status":"rejected"}' checking >/dev/null
RESULT="spec-check rejected $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [{ op: "halt" }],
}));
'
```

新（enqueue-routes 已移除 put；此处仅删 update，complete 进 envelope）：
```bash
REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" RESULT="spec-check rejected $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "REJECT: the approved spec file is missing from the implementation branch. Ensure the spec file is committed to the branch and try again.",
    }},
    { op: "complete", status: "rejected" },
    { op: "halt" },
  ],
}));
'
```

> 注：FAIL 路径同时含 enqueue（P-a3，enqueue-routes spec 已处理）与 complete（P-b2，本 spec 处理）两个 effect。两 spec 分别合入后，FAIL 路径 envelope 最终含 enqueue + complete + halt 三个 effects——本 spec 交付时 enqueue-routes 已合入，可直接在此基础上叠加 complete。

### 3.2 `workflows/spec-gen/spec-check/workflow.yaml`

**移除** payload 字段：
```yaml
      loop_store_cli: "{{loop_store_cli}}"
      pr_store_dir: "{{pr_store_dir}}"
```

（`trigger_store_dir` 保留，`pr_id`/`spec_id`/`spec_file`/`branch`/`base_commit` 保留。）

### 3.3 `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`

**移除** bash 变量赋值行：
```bash
loop_store_cli="{{loop_store_cli}}"
pr_store_dir="{{pr_store_dir}}"
```

**P-b3 改动**：

旧（line 45，在 acceptance 判断之后，所有路径均执行）：
```bash
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" "{\"status\":\"$verify_status\"}" verifying >/dev/null
```

新（删除该行；complete effect 进入 result emit 的 effects 数组，与 enqueue-routes spec 产生的分支结构结合）：

合入 enqueue-routes 后，末尾 result emit 结构已是两分支（failure 含 enqueue / success 只 halt）。本 spec 在两个分支中均加入 `{op:"complete", status:"$verify_status"}`：

```bash
if [ "$verify_status" != "ready-to-merge" ]; then
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" FAILURE_REASON="$failure_reason" VERIFY_STATUS="$verify_status" RESULT="deploy-verify $verify_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: process.env.VERIFY_STATUS },
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
  VERIFY_STATUS="$verify_status" RESULT="deploy-verify $verify_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: process.env.VERIFY_STATUS },
    { op: "halt" },
  ],
}));
'
fi
```

> complete effect 置于 enqueue 之前（语义上先声明本节点完成状态，再路由重试），与 engine spec §4 组合场景断言一致。

### 3.4 `workflows/spec-gen/deploy-verify/workflow.yaml`

**移除** payload 字段：
```yaml
      loop_store_cli: "{{loop_store_cli}}"
      pr_store_dir: "{{pr_store_dir}}"
```

### 3.5 `workflows/spec-gen/merger/templates/merger.md`

**移除** bash 变量赋值行：
```bash
loop_store_cli="{{loop_store_cli}}"
pr_store_dir="{{pr_store_dir}}"
```

**P-b4 改动**（line 65 update 删除；complete 进 envelope）：

旧（line 65，所有路径均执行）：
```bash
node "$loop_store_cli" "$pr_store_dir" update "$pr_id" "{\"status\":\"$merge_status\"}" merging >/dev/null
```

新（合入 enqueue-routes 后，末尾已是两分支；加 complete effect，`merge_status` 运行时值填入）：

```bash
if [ "$merge_status" != "merged" ]; then
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" FAILURE_REASON="$failure_reason" MERGE_STATUS="$merge_status" RESULT="merge $merge_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: process.env.MERGE_STATUS },
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
  MERGE_STATUS="$merge_status" RESULT="merge $merge_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: process.env.MERGE_STATUS },
    { op: "halt" },
  ],
}));
'
fi
```

### 3.6 `workflows/spec-gen/merger/workflow.yaml`

**移除** payload 字段：
```yaml
      loop_store_cli: "{{loop_store_cli}}"
      pr_store_dir: "{{pr_store_dir}}"
```

### 3.7 `workflows/fleet-impl.yaml.tpl`

spec-check pipeline 的 `input:` 段移除：
```yaml
      loop_store_cli: ${LOOP_STORE_CLI}
```

deploy-verify pipeline 的 `input:` 段移除：
```yaml
      loop_store_cli: ${LOOP_STORE_CLI}
```

（`pr_store_dir` 已从 workflow.yaml payload 移除，fleet input 无需再传；但 `claim.store_dir: ${PR_STORE_DIR}` 和 `bind.pr_id: id` 在 claim 块中独立存在，**不受影响**。）

### 3.8 `workflows/fleet-merge.yaml.tpl`

merger pipeline 的 `input:` 段移除：
```yaml
      loop_store_cli: ${LOOP_STORE_CLI}
```

（`claim.store_dir` 独立于 input，不受影响。）

## 4. 测试要求

扩充 `tests/complete-effect.test.sh`（新建）。

### RED 场景列表

1. **P-b1（spec-check PASS → ready-to-deploy）**：spec-check 模板 PASS 路径输出 effects 含 `{op:"complete", status:"ready-to-deploy"}`；pr_store_dir 文件数不变（无直接 update）。
2. **P-b2（spec-check FAIL → rejected）**：FAIL 路径输出含 `{op:"complete", status:"rejected"}` 和 `{op:"enqueue", queue:"trigger", ...}`；pr_store_dir 文件数不变。
3. **P-b3 两态（deploy-verify ready-to-merge）**：`verify_status=ready-to-merge`，输出 `{op:"complete", status:"ready-to-merge"}, {op:"halt"}`，无 enqueue。
4. **P-b3 两态（deploy-verify verify_failed）**：`verify_status=verify_failed`，输出 `{op:"complete", status:"verify_failed"}, {op:"enqueue",...}, {op:"halt"}`。
5. **P-b4 三态（merger merged）**：`merge_status=merged`，输出 `{op:"complete", status:"merged"}, {op:"halt"}`。
6. **P-b4 三态（merger merge_failed）**：`merge_status=merge_failed`，输出 `{op:"complete", status:"merge_failed"}, {op:"enqueue",...}, {op:"halt"}`。
7. **P-b4 三态（merger merge_conflict）**：`merge_status=merge_conflict`，输出含 `status:"merge_conflict"`。

### 组合场景断言

- **complete 在 enqueue 之前（P-b3 / P-b4 失败路径）**：effects 数组 `complete` 的 index < `enqueue` 的 index（验证排序语义正确）。
- **INV-5 全清断言**：模板文件不含 `loop_store_cli` 字符串（grep 验证）；workflow.yaml 不含 `loop_store_cli` 字段（grep 验证）。

## 5. 验收

- `bash tests/acceptance.sh` 全绿。
- 全清 grep 断言（plugin repo 根）：
  ```bash
  grep -rn 'node.*loop_store_cli' workflows/spec-gen/*/templates/*.md | wc -l
  # 预期：0（P-a1~P-a5 + P-b1~P-b4 全部迁移完成）
  ```
- fleet template 清理确认：
  ```bash
  grep -n 'loop_store_cli' workflows/fleet-impl.yaml.tpl workflows/fleet-merge.yaml.tpl | grep -v '^Binary'
  # 预期：0 行（spec-rework/spec-check/deploy-verify/merger 的 input 段均已清除）
  ```

## 6. 豁免清单（plugin 无豁免）

Plugin (b) 类 4 条 P-b1~P-b4 全部迁移，无豁免。

# References
- 盘点条目：`../../b0-inventory.md` §二.2.2 P-b1~P-b4
- complete effect 机制：engine `SPEC-002-b0-complete-effect`（INV-2~INV-7，completeRecord 注入与 ifStatus 守卫）
- fleet claim 上下文：`workflows/fleet-impl.yaml.tpl`（spec-check / deploy-verify claim 块）、`workflows/fleet-merge.yaml.tpl`（merger claim 块）
