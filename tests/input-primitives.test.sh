#!/usr/bin/env bash
# Static + behavior tests for SPEC-007-b4-input-primitives-anchors.
#
# 收账锚集：把 B4 的收编事实固化成机器可查的回归断言。
#   - TC-1~TC-4：dd 收编静态锚（Pointer passthrough 指令 / triplet 通道形态 /
#     rework 正门+update 豁免 / deploy 残留豁免）
#   - TC-5：.dd-review 正名锚（verdict.feedback_file description + 反向零漂移 + symlink 网络）
#   - TC-6：裸路径北极星（design §2 B4 行：grep template/persona 无裸路径）
#   - TC-7：pr optional 防手滑锚（与 pointer-records TC-1 双锚）
#   - TC-8~TC-10：rework fixture 行为组（REJECT 带 triplet 闭环 / 省略语义 / APPROVE 回归）
#
# 头部纪律镜像 pointer-consumption.test.sh:15-24（set -euo pipefail / ROOT /
# ENGINE_ROOT guard SKIP / DD_PLUGIN_ROOT 缺省）+ LOOP_STORE_CLI 自带缺省
# （对齐 acceptance.sh:77；修正 pointer-consumption:185 裸用环境变量的纪律缺口）。
# 静态 TC（TC-1~TC-7）不需 ajv；行为 TC（TC-8~TC-10）需 $ENGINE_ROOT/dist/template.js
# 与 store-cli，缺则 SKIP。dd 侧 $DD_PLUGIN_ROOT/workflows/spec 缺则相关 dd 半边 SKIP（INV-1）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
LOOP_STORE_CLI="${LOOP_STORE_CLI:-$ENGINE_ROOT/dist/lib/store-cli.js}"
fail=0

# ajv 借自 engine 依赖树（本 repo zero-npm-dependency）；TC-5 的 node 断言不需 ajv，
# 仅在读 schema 时用 node fs。行为 TC 用 engine fill + store-cli。
if [ ! -d "$ENGINE_ROOT/node_modules/ajv" ]; then
  echo "SKIP: engine node_modules/ajv missing; npm install in $ENGINE_ROOT" >&2
  exit 0
fi

CONTRACTS_DIR="$ROOT/workflows/spec-gen/contracts"
DD_SPEC_DIR="$DD_PLUGIN_ROOT/workflows/spec"

# dd 半边可用性：缺则 TC-1~TC-4/TC-6 的 dd 半边与 TC-8~TC-10 全部 SKIP（INV-1）。
dd_available=1
if [ ! -d "$DD_SPEC_DIR" ]; then
  echo "SKIP: dd-plugin workflows/spec unavailable at $DD_SPEC_DIR (dd 半边 TC 全 SKIP)" >&2
  dd_available=0
fi

# ---------------------------------------------------------------------------
# TC-1（dd 收编指令锚）：Pointer passthrough rule 恰 2 文件、work/review 各 1、
# rework/deploy 各 0（rework 是 bash 模板，空则省略逻辑在 node 代码里不在指令文案里）。
# ---------------------------------------------------------------------------
tc1_fail=0
if [ "$dd_available" -eq 0 ]; then
  echo "SKIP: TC-1 dd 半边不可用" >&2
else
  pp_count="$(grep -rlF 'Pointer passthrough rule' "$DD_SPEC_DIR"/*/templates/*.md 2>/dev/null | wc -l | tr -d ' ' || true)"
  [ "$pp_count" -eq 2 ] \
    || { echo "FAIL: TC-1 Pointer passthrough rule file count=$pp_count expected 2" >&2; tc1_fail=1; }
  for f in work review; do
    c="$(grep -cF 'Pointer passthrough rule' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    [ "$c" -eq 1 ] \
      || { echo "FAIL: TC-1 $f.md Pointer passthrough rule count=$c expected 1" >&2; tc1_fail=1; }
  done
  for f in rework deploy; do
    c="$(grep -cF 'Pointer passthrough rule' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    [ "$c" -eq 0 ] \
      || { echo "FAIL: TC-1 $f.md Pointer passthrough rule count=$c expected 0" >&2; tc1_fail=1; }
  done
  if [ "$tc1_fail" -eq 0 ]; then
    echo "ok: TC-1 dd 收编指令锚（Pointer passthrough rule 恰 2 文件，work/review 各 1，rework/deploy 各 0）"
  else
    fail=1
  fi
fi

# ---------------------------------------------------------------------------
# TC-2（dd triplet 通道形态锚）：work/review/rework 三模板可选形态各恰 3、必填各恰 0；
# deploy 两形态各恰 0；三 workflow.yaml payload 可选形态各恰 3（双层通道齐备）。
# ---------------------------------------------------------------------------
tc2_fail=0
if [ "$dd_available" -eq 0 ]; then
  echo "SKIP: TC-2 dd 半边不可用" >&2
else
  for f in work review rework; do
    opt="$(grep -Ec '\{\{(repo|commit|spec_path)\?\}\}' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    req="$(grep -Ec '\{\{(repo|commit|spec_path)\}\}' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    [ "$opt" -eq 3 ] \
      || { echo "FAIL: TC-2 $f.md optional triplet count=$opt expected 3" >&2; tc2_fail=1; }
    [ "$req" -eq 0 ] \
      || { echo "FAIL: TC-2 $f.md required triplet count=$req expected 0" >&2; tc2_fail=1; }
    yopt="$(grep -Ec '\{\{(repo|commit|spec_path)\?\}\}' "$DD_SPEC_DIR/$f/workflow.yaml" 2>/dev/null || true)"
    [ "$yopt" -eq 3 ] \
      || { echo "FAIL: TC-2 $f/workflow.yaml optional triplet count=$yopt expected 3" >&2; tc2_fail=1; }
  done
  for f in deploy; do
    opt="$(grep -Ec '\{\{(repo|commit|spec_path)\?\}\}' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    req="$(grep -Ec '\{\{(repo|commit|spec_path)\}\}' "$DD_SPEC_DIR/$f/templates/"*.md 2>/dev/null || true)"
    [ "$opt" -eq 0 ] \
      || { echo "FAIL: TC-2 deploy.md optional triplet count=$opt expected 0" >&2; tc2_fail=1; }
    [ "$req" -eq 0 ] \
      || { echo "FAIL: TC-2 deploy.md required triplet count=$req expected 0" >&2; tc2_fail=1; }
  done
  if [ "$tc2_fail" -eq 0 ]; then
    echo "ok: TC-2 dd triplet 通道形态锚（work/review/rework 各恰 3 可选 + 0 必填 + workflow.yaml 双层齐备）"
  else
    fail=1
  fi
fi

# ---------------------------------------------------------------------------
# TC-3（dd rework 正门 + update 豁免保留锚）：routes.trigger 在场 + 注释锚 +
# rework.md 去注释后零 put + enqueue 出口恰 1 + update 恰 2（approved/rejected 各 1）。
# ---------------------------------------------------------------------------
tc3_fail=0
if [ "$dd_available" -eq 0 ]; then
  echo "SKIP: TC-3 dd 半边不可用" >&2
else
  rework_wf="$DD_SPEC_DIR/rework/workflow.yaml"
  rework_tpl="$DD_SPEC_DIR/rework/templates/rework.md"
  grep -qE '^routes:' "$rework_wf" \
    || { echo "FAIL: TC-3 rework/workflow.yaml missing routes: section" >&2; tc3_fail=1; }
  grep -qE '^\s+trigger: "\{\{trigger_store_dir\}\}"' "$rework_wf" \
    || { echo "FAIL: TC-3 rework/workflow.yaml missing trigger: \"{{trigger_store_dir}}\"" >&2; tc3_fail=1; }
  grep -q '引擎无对应 effect' "$rework_wf" \
    || { echo "FAIL: TC-3 rework/workflow.yaml missing update exemption comment" >&2; tc3_fail=1; }
  put_count="$(grep -vE '^[[:space:]]*#' "$rework_tpl" | grep -cE '(store-cli|store_cli).*[[:space:]]put[[:space:]]' || true)"
  [ "$put_count" -eq 0 ] \
    || { echo "FAIL: TC-3 rework.md non-comment put count=$put_count expected 0" >&2; tc3_fail=1; }
  enq_count="$(grep -cF 'op: "enqueue", queue: "trigger"' "$rework_tpl" || true)"
  [ "$enq_count" -eq 1 ] \
    || { echo "FAIL: TC-3 rework.md enqueue exit count=$enq_count expected 1" >&2; tc3_fail=1; }
  upd_count="$(grep -cE '"\$loop_store_cli" "\$pr_store_dir" update' "$rework_tpl" || true)"
  [ "$upd_count" -eq 2 ] \
    || { echo "FAIL: TC-3 rework.md update count=$upd_count expected 2" >&2; tc3_fail=1; }
  upd_app="$(grep -cE '"\$loop_store_cli" "\$pr_store_dir" update.*"approved"' "$rework_tpl" || true)"
  upd_rej="$(grep -cE '"\$loop_store_cli" "\$pr_store_dir" update.*"rejected"' "$rework_tpl" || true)"
  [ "$upd_app" -eq 1 ] \
    || { echo "FAIL: TC-3 rework.md approved update count=$upd_app expected 1" >&2; tc3_fail=1; }
  [ "$upd_rej" -eq 1 ] \
    || { echo "FAIL: TC-3 rework.md rejected update count=$upd_rej expected 1" >&2; tc3_fail=1; }
  if [ "$tc3_fail" -eq 0 ]; then
    echo "ok: TC-3 dd rework 正门+update 豁免保留锚（routes.trigger + 注释 + 零 put + enqueue 恰 1 + update 恰 2）"
  else
    fail=1
  fi
fi

# ---------------------------------------------------------------------------
# TC-4（dd deploy 残留豁免保留锚）：deploy.md put 恰 1 + triplet 占位符恰 0。
# ---------------------------------------------------------------------------
tc4_fail=0
if [ "$dd_available" -eq 0 ]; then
  echo "SKIP: TC-4 dd 半边不可用" >&2
else
  deploy_tpl="$DD_SPEC_DIR/deploy/templates/deploy.md"
  deploy_put="$(grep -cE '"\$loop_store_cli" "\$trigger_store_dir" put' "$deploy_tpl" || true)"
  [ "$deploy_put" -eq 1 ] \
    || { echo "FAIL: TC-4 deploy.md put count=$deploy_put expected 1" >&2; tc4_fail=1; }
  deploy_tri="$(grep -Ec '\{\{(repo|commit|spec_path)\??\}\}' "$deploy_tpl" 2>/dev/null || true)"
  [ "$deploy_tri" -eq 0 ] \
    || { echo "FAIL: TC-4 deploy.md triplet placeholder count=$deploy_tri expected 0" >&2; tc4_fail=1; }
  if [ "$tc4_fail" -eq 0 ]; then
    echo "ok: TC-4 dd deploy 残留豁免保留锚（put 恰 1 + triplet 恰 0）"
  else
    fail=1
  fi
fi

# ---------------------------------------------------------------------------
# TC-5（.dd-review 正名锚）：verdict.feedback_file.description 非空含 .dd-review +
# 反向零漂移（required/enum/additionalProperties 逐字不变）+ symlink 恰 2/13。
# INV-3：description-only，ajv 校验行为零变化，全仓 fixture 零迁移。
# ---------------------------------------------------------------------------
tc5_fail=0
ROOT_ENV="$ROOT" node -e '
  const fs = require("node:fs");
  const path = require("node:path");
  const s = JSON.parse(fs.readFileSync(path.join(process.env.ROOT_ENV, "workflows/spec-gen/contracts/verdict.schema.json"), "utf8"));
  const desc = s.properties && s.properties.feedback_file && s.properties.feedback_file.description;
  if (!desc || desc.length === 0) { console.error("FAIL: TC-5 feedback_file.description empty"); process.exit(1); }
  if (!desc.includes(".dd-review")) { console.error("FAIL: TC-5 feedback_file.description missing .dd-review substring"); process.exit(1); }
  const req = JSON.stringify(s.required);
  if (req !== JSON.stringify(["id","status","spec_id","verdict","feedback"])) { console.error("FAIL: TC-5 required drift: " + req); process.exit(1); }
  if (s.additionalProperties !== true) { console.error("FAIL: TC-5 additionalProperties drift: " + s.additionalProperties); process.exit(1); }
  const ve = JSON.stringify(s.properties.verdict.enum);
  if (ve !== JSON.stringify(["APPROVE","REJECT"])) { console.error("FAIL: TC-5 verdict.enum drift: " + ve); process.exit(1); }
  const se = JSON.stringify(s.properties.status.enum);
  if (se !== JSON.stringify(["decided","reworked","contract_rejected"])) { console.error("FAIL: TC-5 status.enum drift: " + se); process.exit(1); }
' || tc5_fail=1
verdict_sym="$(find "$ROOT"/workflows/spec-gen/*/contracts -name 'verdict.schema.json' -type l 2>/dev/null | wc -l | tr -d ' ' || true)"
[ "$verdict_sym" -eq 2 ] \
  || { echo "FAIL: TC-5 verdict symlink count=$verdict_sym expected 2" >&2; tc5_fail=1; }
all_sym="$(find "$ROOT"/workflows/spec-gen/*/contracts -name '*.schema.json' -type l 2>/dev/null | wc -l | tr -d ' ' || true)"
[ "$all_sym" -eq 13 ] \
  || { echo "FAIL: TC-5 schema symlink count=$all_sym expected 13" >&2; tc5_fail=1; }
if [ "$tc5_fail" -eq 0 ]; then
  echo "ok: TC-5 .dd-review 正名锚（description 含 .dd-review + required/enum/additionalProperties 零漂移 + symlink 2/13）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-6（裸路径北极星，恰 0）：design §2 B4 行——grep template/persona 无裸路径。
# 口径两段：raw 段抓系统绝对路径前缀；-oE token 化后排除段滤掉变量根
# （}} 或 $ 前缀：{{workspace_repo}}/.dd-review/、"$repo"/tmp/x 合法）。
# 亲核 2026-07-05（master@33939fc / dd@3838d72）：raw 段即恰 0，排除段为前向防御。
# ---------------------------------------------------------------------------
np_hits() {
  grep -roE '[^[:space:]]*/(data|home|tmp|usr|var)/[^[:space:]]*' "$@" 2>/dev/null \
    | grep -vE '(\}\}|\$)' | wc -l | tr -d ' ' || true
}
tc6_fail=0
# bootstrap 文件集：六工序 templates + draft/review personas + 3 个 fleet tpl。
bs_np="$(np_hits "$ROOT"/workflows/spec-gen/*/templates/*.md "$ROOT"/workflows/spec-gen/*/personas/*.md "$ROOT"/workflows/fleet-impl.yaml.tpl "$ROOT"/workflows/fleet-merge.yaml.tpl "$ROOT"/workflows/fleet.yaml.tpl)"
[ "$bs_np" -eq 0 ] \
  || { echo "FAIL: TC-6 bootstrap bare-path hits=$bs_np expected 0" >&2; tc6_fail=1; }
if [ "$dd_available" -eq 0 ]; then
  echo "SKIP: TC-6 dd 半边不可用" >&2
else
  # dd spec 模式：templates + work/review personas（rework/deploy 无 personas 目录，
  # glob 必须显式列存在路径，防 nullglob 缺省下字面展开报错）。
  dd_np="$(np_hits "$DD_SPEC_DIR"/*/templates/*.md "$DD_SPEC_DIR"/work/personas/*.md "$DD_SPEC_DIR"/review/personas/*.md)"
  [ "$dd_np" -eq 0 ] \
    || { echo "FAIL: TC-6 dd bare-path hits=$dd_np expected 0" >&2; tc6_fail=1; }
fi
if [ "$tc6_fail" -eq 0 ]; then
  echo "ok: TC-6 裸路径北极星（bootstrap + dd spec 两文件集各恰 0）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-7（pr optional 防手滑锚）：pr.schema.json required 逐字不含 triplet 三键
# ——与 pointer-records TC-1 互为双锚（INV-2：B5/B6 升 required 时两 TC + schema 三处同批改）。
# ---------------------------------------------------------------------------
tc7_fail=0
ROOT_ENV="$ROOT" node -e '
  const fs = require("node:fs");
  const path = require("node:path");
  const s = JSON.parse(fs.readFileSync(path.join(process.env.ROOT_ENV, "workflows/spec-gen/contracts/pr.schema.json"), "utf8"));
  const req = JSON.stringify(s.required);
  if (req !== JSON.stringify(["id","status","spec_id","spec_file","branch","base_commit"])) { console.error("FAIL: TC-7 pr required drift: " + req); process.exit(1); }
  for (const k of ["repo","commit","spec_path"]) {
    if (s.required.includes(k)) { console.error("FAIL: TC-7 pr required MUST NOT include " + k + " (INV-2 钉死可选)"); process.exit(1); }
  }
' || tc7_fail=1
if [ "$tc7_fail" -eq 0 ]; then
  echo "ok: TC-7 pr optional 防手滑锚（required 不含 triplet 三键，与 pointer-records TC-1 双锚）"
else
  fail=1
fi

# 静态组收尾：任一红即不进入行为组（行为组依赖 dd，静态红说明锚漂移，先修锚）。
if [ "$fail" -ne 0 ]; then
  echo "input-primitives FAILED (static group TC-1~TC-7)"
  exit 1
fi

# ---------------------------------------------------------------------------
# TC-8~TC-10：rework fixture 行为组（可执行测试，自建 fixture store + repo）
# 需要 engine dist/template.js + store-cli；dd 半边可用。缺则 SKIP（INV-1）。
# ---------------------------------------------------------------------------
ENGINE_DIST_TEMPLATE="$ENGINE_ROOT/dist/template.js"
if [ "$dd_available" -eq 0 ] || [ ! -f "$ENGINE_DIST_TEMPLATE" ] || [ ! -f "$LOOP_STORE_CLI" ]; then
  echo "SKIP: TC-8~TC-10 behavior group — dd unavailable or engine dist/store-cli missing" >&2
  if [ "$fail" -ne 0 ]; then
    echo "input-primitives FAILED"
    exit 1
  fi
  echo "input-primitives PASSED (static only; behavior SKIPPED)"
  exit 0
fi

BC_ROOT="$(mktemp -d)"
trap 'rm -rf "$BC_ROOT"' EXIT

# render_template：逐字镜像 pointer-consumption.test.sh:138-157（engine fill；ctx 空白切分）。
render_template() {
  local tpl="$1"
  local out="$2"
  shift 2
  local ctx="$*"
  local render_js
  render_js="$(mktemp --suffix=.mjs)"
  cat > "$render_js" <<RENDER
import { fill } from "file://$ENGINE_DIST_TEMPLATE";
import { readFileSync, writeFileSync } from "node:fs";
const ctx = {};
for (const pair of process.argv[2].split(/\s+/)) {
  const i = pair.indexOf("=");
  if (i > 0) ctx[pair.slice(0, i)] = pair.slice(i + 1);
}
writeFileSync(process.argv[3], fill(readFileSync(process.argv[4], "utf8"), ctx), "utf8");
RENDER
  node "$render_js" "$ctx" "$out" "$tpl"
  rm -f "$render_js"
}

record_field() {
  # record_field <json-file> <key>
  node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))[process.argv[2]]??""' "$1" "$2"
}

# fixture repo（triplet 目标 repo + spec_file 物化路径来源）
fixrepo="$BC_ROOT/repo"
git init -q --initial-branch=main "$fixrepo"
git -C "$fixrepo" config user.name "Test"
git -C "$fixrepo" config user.email "test@example.invalid"
mkdir -p "$fixrepo/docs/specs"
printf '# SPEC-990 rework probe\nbody line\n' > "$fixrepo/docs/specs/SPEC-990.md"
echo "base" > "$fixrepo/README.md"
git -C "$fixrepo" add .
git -C "$fixrepo" commit -q -m "init probe"
fixrepo_abs="$(cd "$fixrepo" && pwd)"
fix_head="$(git -C "$fixrepo" rev-parse HEAD)"
fix_spec_path="docs/specs/SPEC-990.md"

rework_tpl="$DD_SPEC_DIR/rework/templates/rework.md"

# ---------------------------------------------------------------------------
# TC-8（rework REJECT 带 triplet：re-seed 闭环，行为 fixture）
# mktemp 下自建 pr store + trigger store；put 一条 reviewing pr 记录；渲染+执行
# rework.md（REJECT + 完整 triplet ctx）；断言 enqueue 闭环 + redo id + triplet 逐字
# + trigger store 零 json（enqueue 是 effect 声明非直投）+ pr status=rejected。
# ---------------------------------------------------------------------------
tc8_fail=0
tc8_pr="$BC_ROOT/tc8/pr"
tc8_trig="$BC_ROOT/tc8/trigger"
mkdir -p "$tc8_pr" "$tc8_trig"
node "$LOOP_STORE_CLI" "$tc8_pr" put '{"id":"pr-SPEC-990","status":"reviewing","spec_id":"SPEC-990","spec_file":"'"$fixrepo_abs"'/'"$fix_spec_path"'","branch":"dd/SPEC-990","base_commit":"'"$fix_head"'"}' >/dev/null
tc8_script="$BC_ROOT/tc8/run.sh"
render_template "$rework_tpl" "$tc8_script" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc8_trig" \
  "pr_store_dir=$tc8_pr" \
  "pr_id=pr-SPEC-990" \
  "spec_id=SPEC-990" \
  "spec_file=$fixrepo_abs/$fix_spec_path" \
  "verdict=REJECT" \
  "feedback=badwork" \
  "feedback_file=$fixrepo_abs/.dd-review/feedback.md" \
  "repo=$fixrepo_abs" \
  "commit=$fix_head" \
  "spec_path=$fix_spec_path"
tc8_out="$(bash "$tc8_script")"
TC8_OUT="$tc8_out" TC8_TRIG="$tc8_trig" TC8_PR="$tc8_pr" TC8_REPO="$fixrepo_abs" TC8_COMMIT="$fix_head" TC8_PATH="$fix_spec_path" node -e '
  const out = JSON.parse(process.env.TC8_OUT);
  const a = out.effects && out.effects[0];
  if (!a || a.op !== "enqueue" || a.queue !== "trigger") { console.error("FAIL: TC-8 effects[0] not enqueue/trigger: " + JSON.stringify(a)); process.exit(1); }
  const task = a.task;
  if (!/^SPEC-990-r[0-9]+$/.test(task.id)) { console.error("FAIL: TC-8 task.id not redo form: " + task.id); process.exit(1); }
  if (task.repo !== process.env.TC8_REPO || task.commit !== process.env.TC8_COMMIT || task.spec_path !== process.env.TC8_PATH) {
    console.error("FAIL: TC-8 triplet drift: repo=" + task.repo + " commit=" + task.commit + " path=" + task.spec_path); process.exit(1);
  }
' || tc8_fail=1
# trigger store 零 json：enqueue 是 effect 声明非直投（正门收编行为证明）
tc8_trig_count="$(find "$tc8_trig" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$tc8_trig_count" -eq 0 ] \
  || { echo "FAIL: TC-8 trigger store json count=$tc8_trig_count expected 0 (enqueue 非直投)" >&2; tc8_fail=1; }
# pr 记录 status=rejected（update 豁免真实生效，与 TC-3 静态锚互证）
tc8_pr_status="$(record_field "$tc8_pr/pr-SPEC-990.json" status)"
[ "$tc8_pr_status" = "rejected" ] \
  || { echo "FAIL: TC-8 pr status=$tc8_pr_status expected rejected" >&2; tc8_fail=1; }
if [ "$tc8_fail" -eq 0 ]; then
  echo "ok: TC-8 rework REJECT 带 triplet 闭环（enqueue+redo id+triplet 逐字+trigger 零 json+pr rejected）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-9（rework REJECT 不带 triplet：省略语义）
# ctx 的 repo/commit/spec_path 置空；断言 task 无三键 + 键集合逐字恰
# {feedback, feedback_file, id, spec_file, status}（空则整键省略、禁空串）。
# ---------------------------------------------------------------------------
tc9_fail=0
tc9_pr="$BC_ROOT/tc9/pr"
tc9_trig="$BC_ROOT/tc9/trigger"
mkdir -p "$tc9_pr" "$tc9_trig"
node "$LOOP_STORE_CLI" "$tc9_pr" put '{"id":"pr-SPEC-990","status":"reviewing","spec_id":"SPEC-990","spec_file":"'"$fixrepo_abs"'/'"$fix_spec_path"'","branch":"dd/SPEC-990","base_commit":"'"$fix_head"'"}' >/dev/null
tc9_script="$BC_ROOT/tc9/run.sh"
render_template "$rework_tpl" "$tc9_script" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc9_trig" \
  "pr_store_dir=$tc9_pr" \
  "pr_id=pr-SPEC-990" \
  "spec_id=SPEC-990" \
  "spec_file=$fixrepo_abs/$fix_spec_path" \
  "verdict=REJECT" \
  "feedback=badwork" \
  "feedback_file=$fixrepo_abs/.dd-review/feedback.md" \
  "repo=" \
  "commit=" \
  "spec_path="
tc9_out="$(bash "$tc9_script")"
TC9_OUT="$tc9_out" node -e '
  const out = JSON.parse(process.env.TC9_OUT);
  const task = out.effects[0].task;
  for (const k of ["repo","commit","spec_path"]) {
    if (k in task) { console.error("FAIL: TC-9 task must not include " + k + " (空则整键省略)"); process.exit(1); }
  }
  const keys = Object.keys(task).sort().join(",");
  const expect = ["feedback","feedback_file","id","spec_file","status"].sort().join(",");
  if (keys !== expect) { console.error("FAIL: TC-9 key set drift: " + keys + " != " + expect); process.exit(1); }
' || tc9_fail=1
if [ "$tc9_fail" -eq 0 ]; then
  echo "ok: TC-9 rework REJECT 不带 triplet（三键省略 + 键集合逐字 {feedback,feedback_file,id,spec_file,status}）"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-10（rework APPROVE 回归）：ctx verdict=APPROVE；断言 effects[0].op=halt +
# pr status=approved + trigger store 恰 0——dd PR #4 operator 冒烟五断言固化收尾。
# ---------------------------------------------------------------------------
tc10_fail=0
tc10_pr="$BC_ROOT/tc10/pr"
tc10_trig="$BC_ROOT/tc10/trigger"
mkdir -p "$tc10_pr" "$tc10_trig"
node "$LOOP_STORE_CLI" "$tc10_pr" put '{"id":"pr-SPEC-990","status":"reviewing","spec_id":"SPEC-990","spec_file":"'"$fixrepo_abs"'/'"$fix_spec_path"'","branch":"dd/SPEC-990","base_commit":"'"$fix_head"'"}' >/dev/null
tc10_script="$BC_ROOT/tc10/run.sh"
render_template "$rework_tpl" "$tc10_script" \
  "loop_store_cli=$LOOP_STORE_CLI" \
  "trigger_store_dir=$tc10_trig" \
  "pr_store_dir=$tc10_pr" \
  "pr_id=pr-SPEC-990" \
  "spec_id=SPEC-990" \
  "spec_file=$fixrepo_abs/$fix_spec_path" \
  "verdict=APPROVE" \
  "feedback=ok" \
  "feedback_file=" \
  "repo=$fixrepo_abs" \
  "commit=$fix_head" \
  "spec_path=$fix_spec_path"
tc10_out="$(bash "$tc10_script")"
TC10_OUT="$tc10_out" node -e '
  const out = JSON.parse(process.env.TC10_OUT);
  const a = out.effects && out.effects[0];
  if (!a || a.op !== "halt") { console.error("FAIL: TC-10 effects[0].op not halt: " + JSON.stringify(a)); process.exit(1); }
' || tc10_fail=1
tc10_trig_count="$(find "$tc10_trig" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$tc10_trig_count" -eq 0 ] \
  || { echo "FAIL: TC-10 trigger store json count=$tc10_trig_count expected 0" >&2; tc10_fail=1; }
tc10_pr_status="$(record_field "$tc10_pr/pr-SPEC-990.json" status)"
[ "$tc10_pr_status" = "approved" ] \
  || { echo "FAIL: TC-10 pr status=$tc10_pr_status expected approved" >&2; tc10_fail=1; }
if [ "$tc10_fail" -eq 0 ]; then
  echo "ok: TC-10 rework APPROVE 回归（halt + pr approved + trigger 零）"
else
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "input-primitives FAILED"
  exit 1
fi
echo "input-primitives PASSED"
