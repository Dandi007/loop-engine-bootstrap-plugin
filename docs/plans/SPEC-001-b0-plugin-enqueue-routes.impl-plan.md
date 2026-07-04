# SPEC-001-b0-plugin-enqueue-routes — impl-plan

> 给 dev-loop work 柱（KIMI 级）：零背景可执行。每步先写失败测试，确认红，最小改动使其绿，回归，commit。
> target repo：`/data/code/self/loop-engine-bootstrap-plugin`
> 验收命令：`bash tests/acceptance.sh`

## Files

**Modify（精确路径）：**
- `workflows/spec-gen/rework/workflow.yaml`
- `workflows/spec-gen/rework/templates/spec-rework.md`
- `workflows/spec-gen/spec-check/workflow.yaml`
- `workflows/spec-gen/spec-check/templates/spec-check.md`
- `workflows/spec-gen/deploy-verify/workflow.yaml`
- `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`
- `workflows/spec-gen/merger/workflow.yaml`
- `workflows/spec-gen/merger/templates/merger.md`
- `workflows/fleet-impl.yaml.tpl`（仅 spec-rework input 段）

**Create：**
- `tests/enqueue-routes.test.sh`（新增 bash integration test）

## Interfaces

**Consumes：**
- `../../b0-inventory.md` §二.2.1 P-a1~P-a5（改动点列表 + 行号）
- 现有 `tests/acceptance.sh`（扩充不破坏现有测试）

**Produces：**
- 5 个 workflow 模板：直投 put 全替换为 enqueue effect
- 4 个 workflow.yaml：新增 routes 字段
- fleet-impl.yaml.tpl：spec-rework input 段移除 loop_store_cli
- tests/enqueue-routes.test.sh：7 RED 场景 + 2 组合断言

## TDD 步骤（bite-sized，每步 commit）

### Step 1：写失败测试 + 确认红（spec-rework APPROVE path）

```bash
# tests/enqueue-routes.test.sh 新增：
# TC-01: spec-rework APPROVE 应输出 enqueue trigger effect，不写 trigger store
trigger_dir=$(mktemp -d); idea_dir=$(mktemp -d)
before=$(ls "$trigger_dir" | wc -l)
output=$(VERDICT=APPROVE SPEC_ID=test-spec-001 SPEC_FILE=/tmp/spec.md \
  TRIGGER_STORE_DIR="$trigger_dir" IDEA_STORE_DIR="$idea_dir" \
  bash workflows/spec-gen/rework/templates/spec-rework.md 2>/dev/null || \
  node workflows/spec-gen/rework/templates/spec-rework.md)
# assert: output JSON contains effects[0].op == "enqueue" && effects[0].queue == "trigger"
echo "$output" | node -e 'const e=JSON.parse(require("fs").readFileSync(0,"utf8")); process.exit(e.effects[0].op==="enqueue"&&e.effects[0].queue==="trigger"?0:1)'
after=$(ls "$trigger_dir" | wc -l)
[ "$before" -eq "$after" ]   # store dir 文件数不变
```

确认红（模板当前仍调 put，会往 trigger_dir 写文件 or 脚本出错因 loop_store_cli 不存在）。

### Step 2：最小实现——spec-rework workflow.yaml + 模板

1. 编辑 `workflows/spec-gen/rework/workflow.yaml`：在 `seed:` 之前插入：
   ```yaml
   routes:
     trigger:
       store: "{{trigger_store_dir}}"
     idea:
       store: "{{idea_store_dir}}"
   ```
2. 从 payload 中删除 `loop_store_cli: "{{loop_store_cli}}"` 行。
3. 编辑 `workflows/spec-gen/rework/templates/spec-rework.md`：
   - 删除头部三行（loop_store_cli / idea_store_dir / trigger_store_dir 赋值）。
   - 替换 APPROVE 路径（参见 spec §3.2）：删除 `trigger_payload=...` 构造和 `node ... put` 调用，改为 emit JSON envelope（含 enqueue trigger + halt）后 `exit 0`。
   - 替换 REJECT 路径（参见 spec §3.2）：同理 emit（enqueue idea + halt）后 `exit 0`。
   - 删除文件末尾的 trailing halt emit。
4. `bash tests/enqueue-routes.test.sh` — TC-01 绿。

### Step 3：P-a2（REJECT）测试 + 确认绿

新增 TC-02（spec-rework REJECT 输出 enqueue idea），确认绿。commit：
```
feat: P-a1/P-a2 spec-rework template → enqueue effect + routes
```

### Step 4：spec-check workflow.yaml + 模板（P-a3）

1. `workflows/spec-gen/spec-check/workflow.yaml`：加 routes（trigger store）。
2. `workflows/spec-gen/spec-check/templates/spec-check.md`：
   - 删除 `trigger_store_dir="{{trigger_store_dir}}"` 赋值行。
   - FAIL 路径：删除 `node ... put $redo_payload` 行；把 enqueue trigger task 加入 FAIL 路径末尾 emit 的 effects 数组（参见 spec §3.4）。
   - PASS 路径 emit 不变（保留 update + `{op:"halt"}`）。
3. 新增 TC-03（spec-check FAIL → enqueue effect），确认绿；新增 PASS 路径回归测试，确认绿。

commit：`feat: P-a3 spec-check FAIL path → enqueue effect + routes`

### Step 5：deploy-verify workflow.yaml + 模板（P-a4）

1. `workflows/spec-gen/deploy-verify/workflow.yaml`：加 routes（trigger store）。
2. `workflows/spec-gen/deploy-verify/templates/deploy-verify.md`：
   - 删除 `trigger_store_dir=...` bash 变量。
   - 删除 failure if 块内 `node ... put $redo_payload` 行。
   - 重写末尾 result emit：两路分支（failure 含 enqueue、success 只 halt），参见 spec §3.6。
3. 新增 TC-04（failure → enqueue）、TC-06（success → 仅 halt），确认绿。

commit：`feat: P-a4 deploy-verify failure path → enqueue effect + routes`

### Step 6：merger workflow.yaml + 模板（P-a5）

1. `workflows/spec-gen/merger/workflow.yaml`：加 routes（trigger store）。
2. `workflows/spec-gen/merger/templates/merger.md`：
   - 删除 `trigger_store_dir=...` bash 变量。
   - 删除 failure if 块内 `node ... put $redo_payload` 行。
   - 重写末尾 result emit（同 deploy-verify 结构），参见 spec §3.8。
3. 新增 TC-05、TC-07，确认绿。

commit：`feat: P-a5 merger failure path → enqueue effect + routes`

### Step 7：fleet-impl.yaml.tpl 同步

编辑 `workflows/fleet-impl.yaml.tpl`，找到 spec-rework pipeline 的 `input:` 段，删除：
```yaml
      loop_store_cli: ${LOOP_STORE_CLI}
```
（spec-check / deploy-verify 段的 loop_store_cli **不动**）。

### Step 8：组合场景测试

新增：
- TC 验证 P-a1 输出 task 字段与旧 put payload 字段名集合逐字一致（INV-2）。
- TC 验证 spec-check FAIL 路径同时含 enqueue trigger effect 且仍执行 update 调用（INV-3 过渡期 update 不被误删）。

确认绿。

### Step 9：全量验收

```bash
bash tests/acceptance.sh
grep -rn 'node.*loop_store_cli.*put\|"$loop_store_cli".*put' workflows/spec-gen/*/templates/*.md | wc -l
# 预期：0
```

commit：`test: enqueue-routes acceptance + grep assertion`

## INV 自检清单

- [ ] INV-1：spec-check PASS 路径测试绿（路径不含 enqueue，保持原 halt）
- [ ] INV-2：P-a1 task 字段与旧 trigger_payload 字段名逐字对齐（id / status / spec_file / feedback）
- [ ] INV-3：spec-check/deploy-verify/merger 的 `loop_store_cli` 仍在 workflow.yaml payload 和 fleet template（grep 验证）
- [ ] INV-4：fleet-impl.yaml.tpl 的 spec-rework input 段已删 loop_store_cli，spec-check 段未改动
- [ ] INV-5：P-a2 task feedback 字段含 "Spec review REJECT on a previous attempt" 前缀（与旧 put payload 一致）
