# loop-engine-bootstrap-plugin

自举双 Loop plugin：一个 `fleet.yaml` 串联 Spec Loop（起草↔审）与 Impl Loop（实现↔审，复用 dev-dispatch spec mode）。

- 设计文档：`/data/code/self/loop-engine-dev-dispatch-plugin/.runtime/spec/bootstrap-kimi-v2-20260704-010326/spec.md`
- 形态硬约束：一个 plugin、一个 fleet 定义、loop 间靠 store 一跳 route，无胶水脚本；先串行。

## 结构

```
workflows/
  fleet.yaml.tpl              # 单一 fleet：Spec Loop + Impl Loop 共 7 条 pipeline
  spec-gen/
    draft/                    # 原创 spec 起草者
    review/                   # spec 质量审查 + 参考库查重
    rework/                   # APPROVE→Impl trigger / REJECT→idea store
bin/
  bootstrap-loop.sh           # 环境准备 + 播种 idea + `loop-engine drain`
scripts/
  render-template.mjs         # fleet 模板渲染
tests/
  acceptance.sh               # 确定性结构/schema 验收（不计费）
```

Store 目录拓扑（`$RUN_ROOT/stores/`）：

```
idea/          # Spec Loop 入口
spec-pr/       # draft → spec-review
spec-verdict/  # spec-review → spec-rework
trigger/       # ★接缝：spec-rework(APPROVE) → Impl work
pr/            # work → review
verdict/       # review → rework → deploy
```

## 使用

```bash
export BOOT_TARGET_REPO=/path/to/target-repo
bash bin/bootstrap-loop.sh
```

可选覆盖：

```bash
BOOT_RUN_ROOT=/tmp/bootstrap-run \
BOOT_MAX_PASSES=12 \
BOOT_DRAFT_MODEL=set_claude_ccswitch_glm \
BOOT_REVIEW_MODEL=set_claude_ccswitch_glm \
DD_WORK_MODEL=set_claude_ccswitch_glm \
DD_REVIEW_MODEL=set_claude_ccswitch_glm \
DD_ACCEPT_CMD="npm test" \
bash bin/bootstrap-loop.sh
```

## 验收

```bash
npm test
```

验收脚本不调用 LLM；它验证关键文件存在、fleet 模板可被渲染、渲染后的 manifest 可通过 loop-engine schema 校验，并断言 Impl Loop 四个 pipeline 的 `config_dir` 指向 dev-dispatch 而非本地拷贝。
