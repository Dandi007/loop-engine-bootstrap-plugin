# 使用 Guide — 自举双 Loop Plugin

> 这份是**实操 guide**:怎么真跑起来、每步会发生什么、产物在哪、踩过的坑。
> 结构/设计速览看 `README.md`;完整 spec 见 work folder `spec.md`。

## 一句话

给它一个目标 git repo,它会**自己构思一个新 spec → 审核通过 → 自己实现 → 审核通过 → 部署**,全程机器审机器、机器修机器。你只需播一个空 idea 并启动。

## 它跑起来会发生什么

```mermaid
flowchart LR
    IDEA[你播一个空 idea] --> DRAFT[draft: 读参考库<br>原创一份新 spec]
    DRAFT --> SREV[spec-review: 审 spec 质量<br>+ 参考库查重]
    SREV -->|REJECT| DRAFT
    SREV -->|APPROVE| WORK[work: 实现 spec<br>spec 随代码同 commit]
    WORK --> REV[review: 审 diff]
    REV -->|REJECT| WORK
    REV -->|APPROVE| SC[spec-check: 守 INV-3<br>diff 必须含 spec]
    SC --> DEPLOY[deploy: merge + 跑验收]
```

两个 loop 串在**一个 fleet** 里,靠 store 目录一跳接一跳,没有胶水脚本。**先串行**:Spec Loop 收敛出 approved spec 后,Impl Loop 才消费。

## 前置条件

1. **loop-engine 已 build**:
   ```bash
   cd /data/code/self/loop-engine && npm run build
   ```
2. **一个目标 git repo**(`BOOT_TARGET_REPO`)——自举出来的 spec 会被实现进这里。可以是空骨架(像本 plugin 当初那样先 scaffold)。
3. **模型可用**:默认走 cc-switch 的 `set_claude_ccswitch_glm`;impl 想用 KIMI 见下。

### ⚠️ 关键坑:引擎 dist 必须带 tsx loader

当前 loop-engine 的 `dist/*.js` 在纯 node 下因 import 缺 `.js` 扩展名**无法直接运行**(`node dist/cli.js` 会 `ERR_MODULE_NOT_FOUND`)。启动前必须注入 tsx loader:

```bash
export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
```

不设这个,一启动就崩。(治本:给引擎 build 补 `.js` 扩展名,另行处理。)

## 最简启动

```bash
export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
export BOOT_TARGET_REPO=/path/to/target-repo
bash bin/bootstrap-loop.sh
```

启动脚本会自动:建 store 目录 → clone 目标 repo 到隔离 workspace → 播一个 open idea → 渲染 fleet → `loop-engine drain`。

## impl 用 KIMI(已验证配方)

让实现者走 KIMI(kimicode),reviewer 仍用 GLM——这是本 plugin **自己被造出来时用的配方**,已跑通全绿:

```bash
export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
export BOOT_TARGET_REPO=/path/to/target-repo
DD_WORK_RUNTIME=kimicode \
DD_WORK_MODEL=kimi-for-coding/k2p7 \
DD_REVIEW_MODEL=set_claude_ccswitch_glm \
DD_ACCEPT_CMD="bash tests/acceptance.sh" \
bash bin/bootstrap-loop.sh
```

- `DD_ACCEPT_CMD` 是 deploy 阶段在合并结果上跑的真实验收命令,按目标 repo 改(默认 `npm test`)。
- KIMI 别名在 `~/.kimi-code/config.toml`;`kimi-for-coding/k2p7` 是默认。

## idea 从哪来 / 参考库

- **idea store 只需播一个空种子**(启动脚本已自动做),draft 起草者不是从待办清单挑题,而是**读参考库自己原创一个新命题**。
- 参考库默认 `REF_LIBRARY_DIR=/data/vault/docs/specs`(旧 spec 池),**只读、只作灵感/风格参照**,不是待办列表。可 `export REF_LIBRARY_DIR=...` 换。

## 产物在哪 / 怎么回收

**重要:自举出来的代码落在隔离的 workspace clone,不会自动进你的目标 repo。**

- 运行产物根:`$BOOT_RUN_ROOT`(默认 `.runtime/live/<RUN_ID>/`)
- 实现代码:`$RUN_ROOT/workspace-repo`,已 merge 的成果在其默认分支的 HEAD
- 各阶段可观测:`$RUN_ROOT/stores/`(六个 store 的流转)、`$RUN_ROOT/runs/`(引擎 journal)、`$RUN_ROOT/logs/`(deploy 的 merge/accept 日志)、`$RUN_ROOT/diffs/`

回收到目标真 repo(保住成果):

```bash
cd /path/to/target-repo
git fetch "$RUN_ROOT/workspace-repo" <base-branch>:feat/bootstrap-out
# review 后合并
```

## 收敛与成本

- `BOOT_MAX_PASSES`(默认 16):drain 的排空上限,兜底防跑飞。
- 一趟真实运行会多轮调用 LLM(每轮 work/review 各一次 agent),**计费**。先用 `npm test`(见下)做零成本结构验证。

## 零成本验证(不调 LLM)

```bash
export NODE_OPTIONS="--import file:///data/code/self/loop-engine/node_modules/tsx/dist/loader.mjs"
npm test   # = bash tests/acceptance.sh
```

验证:关键文件存在、fleet 模板可渲染、渲染后 manifest 过 loop-engine schema、Impl Loop 四 pipeline 的 `config_dir` 指向 dev-dispatch(不 fork)、deploy 被 spec-check 守卫、以及 spec-rework / spec-check 的确定性全链路 store 状态流。全绿即结构健康。

## 关键 env 速查

| 变量 | 默认 | 说明 |
|---|---|---|
| `NODE_OPTIONS` | (必设) | tsx loader,绕引擎 dist ESM bug |
| `BOOT_TARGET_REPO` | (必填) | 自举实现的目标 git repo |
| `REF_LIBRARY_DIR` | `/data/vault/docs/specs` | 参考库(只读灵感) |
| `DD_WORK_RUNTIME` / `DD_WORK_MODEL` | `claude-code` / GLM | 实现者 runtime/模型(KIMI 见上) |
| `DD_REVIEW_MODEL` | GLM | Impl reviewer 模型 |
| `BOOT_DRAFT_MODEL` / `BOOT_REVIEW_MODEL` | GLM | Spec Loop 起草/审查模型 |
| `DD_ACCEPT_CMD` | `npm test` | deploy 阶段真实验收命令 |
| `BOOT_MAX_PASSES` | `16` | drain 排空上限 |
| `BOOT_RUN_ROOT` | `.runtime/live/<id>` | 运行产物根 |

## 已知限制

- 引擎 dist 不可直接 node 运行(用 tsx loader 绕过,见上)。
- reviewer 详细意见走 workspace 内 `.dd-review/` 文件通道(绕开 claude CLI 对非 claude 模型长 stdout 的截断);该目录已 git-exclude,不入候选分支。
- 目前**串行**:Spec Loop 与 Impl Loop 不并发;异步是后续演进。

## References

- 设计与根因追查:work folder `/data/vault/智元工作/工作记录/2026/07/03/loop-engine-自举双loop-plugin-设计/`(`spec.md` / `findings.md`)
- 复用源 dev-dispatch spec mode:`/data/code/self/loop-engine-dev-dispatch-plugin/workflows/spec/`(repo 类别:self)
- 引擎:`/data/code/self/loop-engine`
