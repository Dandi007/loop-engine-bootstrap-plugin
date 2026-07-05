set -euo pipefail
repo="{{workspace_repo}}"
trigger_store_dir="{{trigger_store_dir}}"
base_commit="{{base_commit}}"
branch="{{branch}}"
pr_id="$(cat <<'EOF'
{{pr_id}}
EOF
)"
spec_id="$(cat <<'EOF'
{{spec_id}}
EOF
)"
spec_file="$(cat <<'EOF'
{{spec_file}}
EOF
)"

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

# INV-3 guard: the approved spec pointer must be resolvable in the workspace clone.
# 注：本检查是快速预检；最终裁决以目标 repo `make gate`（scripts/mr-gate.sh）为准。
# 守卫语义升级（SPEC-006 INV-7）：从「spec 在 impl 分支树上」改为「指针在 workspace
# 可解析」——git show 改用 commit 而非 branch。worker 分支不含 spec 文件时守卫不再
# 拦截；分支内容纪律仍由 deploy-verify 的 accept_cmd 执法。
if [ -n "$commit_v" ] && git -C "${repo_v:-$repo}" show "$commit_v:$spec_path_v" >/dev/null 2>&1; then
  RESULT="spec-check passed $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: "ready-to-deploy" },
    { op: "halt" },
  ],
}));
'
else
  # Reject back to the Impl Loop trigger store so the worker retries.
  base_spec_id="${spec_id%%-r[0-9]*}"
  redo_spec_id="$base_spec_id-r$(date +%s)"
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" REPO_V="$repo_v" COMMIT_V="$commit_v" SPEC_PATH_V="$spec_path_v" RESULT="spec-check rejected $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "REJECT: spec pointer unresolvable (repo=$repo_v commit=$commit_v path=$spec_path_v). Re-commit the spec and re-inject, or fix the workspace clone.",
        repo: process.env.REPO_V,
        commit: process.env.COMMIT_V,
        spec_path: process.env.SPEC_PATH_V,
    }},
    { op: "complete", status: "rejected" },
    { op: "halt" },
  ],
}));
'
fi
