#!/usr/bin/env bash
# spec-inject.sh — 人工模式指针注入（design §3.3 第 3 钉；SPEC-006）
#
# 只校验不代 commit（INV-2）；幂等键 (repo,commit) 以 id=<spec_id>@<commit8> 落地（INV-4）。
# 产出的 trigger 记录与 drafter 管道生产者产出的 trigger 记录形状同构、闸门同一、
# 幂等键同一（INV-1）——操作员从"按 runbook 手拼 JSON"升级为"一条命令投指针"。
#
# 用法：spec-inject.sh <repo> <spec相对路径> <trigger_store_dir> [impl-plan相对路径]
set -euo pipefail

LOOP_STORE_CLI="${LOOP_STORE_CLI:-/data/code/self/loop-engine/dist/lib/store-cli.js}"

usage() {
  cat >&2 <<EOF
[spec-inject] usage: $0 <repo> <spec相对路径> <trigger_store_dir> [impl-plan相对路径]
  把一条 spec 指针消息注入 trigger store（与 drafter 同管道生产者无关，INV-1）。
  repo      = spec 所在 git 仓库（本地绝对路径）
  spec 相对路径 = spec 文件在 repo 内的相对路径（如 docs/specs/SPEC-NNN-slug.md）
  trigger_store_dir = 目标 trigger store 目录
  impl-plan 相对路径 = 可选；提供则同 commit 覆盖 spec 与 plan，物化为 feedback_file
EOF
}

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "[spec-inject] missing $label: $path" >&2
    echo "[spec-inject] build Loop Engine first: cd /data/code/self/loop-engine && npm run build" >&2
    exit 3
  fi
}

# 1. 参数与依赖
if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
  usage
  exit 2
fi
require_file "$LOOP_STORE_CLI" "LOOP_STORE_CLI"

repo_arg="$1"
spec_path="$2"
trigger_store_dir="$3"
impl_plan_path="${4:-}"

# 2. repo 校验
if ! git -C "$repo_arg" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[spec-inject] not a git repository: $repo_arg" >&2
  exit 2
fi
repo="$(cd "$repo_arg" && pwd)"

# 3. committed 校验（INV-2，spec 与 impl-plan 逐个）
#    工具绝不代 add 代 commit——只校验。两条校验：HEAD 树存在 + 工作树 clean。
check_committed() {
  local rel="$1"
  local label="$2"
  if ! git -C "$repo" cat-file -e "HEAD:$rel" >/dev/null 2>&1; then
    echo "[spec-inject] $label not committed at HEAD: $rel" >&2
    echo "[spec-inject] 工具不代 commit，请自行 commit 后重试（未跟踪/未提交/路径错三合一）" >&2
    exit 4
  fi
  if [ -n "$(git -C "$repo" status --porcelain -- "$rel")" ]; then
    echo "[spec-inject] working tree dirty for $label: $rel; commit your changes first" >&2
    exit 4
  fi
}
check_committed "$spec_path" "spec"
if [ -n "$impl_plan_path" ]; then
  check_committed "$impl_plan_path" "impl-plan"
fi

# 4. 取 commit
commit="$(git -C "$repo" rev-parse HEAD)"
if [[ ! "$commit" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "[spec-inject] unexpected commit hash: $commit" >&2
  exit 3
fi
commit8="${commit:0:8}"

# 5. 构造 id（governance：文件名必须 SPEC-NNN-slug.md 形态）
spec_id="$(basename "$spec_path" .md)"
if [[ ! "$spec_id" =~ ^SPEC-[0-9]+ ]]; then
  echo "[spec-inject] spec filename must match SPEC-NNN-slug.md: $spec_path" >&2
  exit 2
fi
record_id="${spec_id}@${commit8}"

# 6. 物化缓存（INV-3：内容 = git show 逐字节输出，非工作树拷贝）
cache_dir="$trigger_store_dir/../.spec-cache"
mkdir -p "$trigger_store_dir" "$cache_dir"
spec_cache="$cache_dir/$record_id.md"
git -C "$repo" show "$commit:$spec_path" > "$spec_cache"
feedback_file=""
if [ -n "$impl_plan_path" ]; then
  feedback_file="$cache_dir/$record_id.impl-plan.md"
  git -C "$repo" show "$commit:$impl_plan_path" > "$feedback_file"
fi

# 7. 构造 record（字段顺序即形状契约——TC-C3 键集合断言的左侧）
spec_cache_abs="$(cd "$cache_dir" && pwd)/$record_id.md"
feedback_file_abs=""
if [ -n "$impl_plan_path" ]; then
  feedback_file_abs="$(cd "$cache_dir" && pwd)/$record_id.impl-plan.md"
fi
record_json="$(SPEC_ID="$spec_id" RECORD_ID="$record_id" SPEC_CACHE_ABS="$spec_cache_abs" \
  FEEDBACK_FILE_ABS="$feedback_file_abs" REPO="$repo" COMMIT="$commit" SPEC_PATH="$spec_path" \
  node -e '
const o = {
  id: process.env.RECORD_ID,
  status: "open",
  spec_file: process.env.SPEC_CACHE_ABS,
  feedback: "(none)",
  repo: process.env.REPO,
  commit: process.env.COMMIT,
  spec_path: process.env.SPEC_PATH,
  feedback_file: process.env.FEEDBACK_FILE_ABS,
};
process.stdout.write(JSON.stringify(o));
')"

# 8. 投递（INV-4：put-if-absent 认领；已存在 → 幂等 exit 0）
set +e
node "$LOOP_STORE_CLI" "$trigger_store_dir" put-if-absent "$record_json" >/tmp/spec-inject.$$.out 2>/tmp/spec-inject.$$.err
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "[spec-inject] created: $record_id -> $trigger_store_dir"
  rm -f /tmp/spec-inject.$$.out /tmp/spec-inject.$$.err
  exit 0
elif [ "$rc" -eq 1 ]; then
  existing_status="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).status' /tmp/spec-inject.$$.out 2>/dev/null || echo unknown)"
  echo "[spec-inject] already injected (idempotent, repo+commit key): $record_id status=$existing_status"
  rm -f /tmp/spec-inject.$$.out /tmp/spec-inject.$$.err
  exit 0
else
  cat /tmp/spec-inject.$$.err >&2 || true
  cat /tmp/spec-inject.$$.out >&2 || true
  rm -f /tmp/spec-inject.$$.out /tmp/spec-inject.$$.err
  exit "$rc"
fi
