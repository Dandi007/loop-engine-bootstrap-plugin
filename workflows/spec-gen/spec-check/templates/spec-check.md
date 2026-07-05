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

# INV-3 guard: the approved spec must exist on the implementation branch.
# 注：本检查是快速预检；最终裁决以目标 repo `make gate`（scripts/mr-gate.sh）为准。
# We check the branch tree directly (not the diff) because the spec file is
# committed to main by the drafter before the work branch is created.
# git show needs a repo-relative path, so strip the workspace_repo prefix.
rel_spec_file="${spec_file#$repo/}"
if git -C "$repo" show "$branch":"$rel_spec_file" >/dev/null 2>&1; then
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
        feedback: "REJECT: the approved spec file is missing from the implementation branch. Ensure the spec file is committed to the branch and try again.",
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
