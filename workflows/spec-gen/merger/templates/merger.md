set -euo pipefail
repo="{{workspace_repo}}"
trigger_store_dir="{{trigger_store_dir}}"
base_branch="{{base_branch}}"
merge_log_dir="{{merge_log_dir}}"
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
branch="$(cat <<'EOF'
{{branch}}
EOF
)"
accept_cmd="$(cat <<'EOF'
{{accept_cmd}}
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

mkdir -p "$merge_log_dir"
merge_log="$merge_log_dir/$pr_id-merge.log"
accept_log="$merge_log_dir/$pr_id-accept.log"

# Switch to base branch and record current HEAD for rollback.
git -C "$repo" checkout -q "$base_branch"
before="$(git -C "$repo" rev-parse HEAD)"
merge_status="merge_failed"
failure_reason=""

# Attempt merge. If it fails due to conflict, abort and mark as merge-conflict.
if git -C "$repo" merge --no-ff "$branch" -m "merge(bootstrap): $pr_id ($spec_id)" > "$merge_log" 2>&1; then
  # Merge succeeded. Run acceptance tests on the merged result.
  if (cd "$repo" && sh -lc "$accept_cmd") > "$accept_log" 2>&1; then
    merge_status="merged"
    # Push the merged main to GitHub.
    git -C "$repo" push origin "$base_branch" >/dev/null 2>&1 || true
    # Close the GitHub PR (merge already done locally).
    (cd "$repo" && gh pr close "$branch" -d 2>/dev/null) || true
  else
    # Tests failed after merge. Roll back.
    git -C "$repo" reset --hard "$before" >/dev/null
    failure_reason="acceptance tests failed after merge of $branch
--- last 60 lines of $accept_log ---
$(tail -n 60 "$accept_log")"
  fi
else
  # Merge conflict or other git error. Abort the merge.
  git -C "$repo" merge --abort >/dev/null 2>&1 || true
  merge_status="merge_conflict"
  failure_reason="merge of $branch into $base_branch failed (conflict or git error)
--- last 30 lines of $merge_log ---
$(tail -n 30 "$merge_log")"
fi

# On failure (merge conflict or test failure), enqueue a retry trigger
# so the impl loop can fix the issue and re-submit.
if [ "$merge_status" != "merged" ]; then
  base_spec_id="${spec_id%%-r[0-9]*}"
  redo_spec_id="$base_spec_id-r$(date +%s)"
  REDO_SPEC_ID="$redo_spec_id" SPEC_FILE="$spec_file" REPO_V="$repo_v" COMMIT_V="$commit_v" SPEC_PATH_V="$spec_path_v" FAILURE_REASON="$failure_reason" MERGE_STATUS="$merge_status" RESULT="merge $merge_status $pr_id" node -e '
process.stdout.write(JSON.stringify({
  result: process.env.RESULT,
  effects: [
    { op: "complete", status: process.env.MERGE_STATUS },
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.REDO_SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "Merge phase FAILED. Fix the issue and re-submit:\n" + process.env.FAILURE_REASON,
        repo: process.env.REPO_V,
        commit: process.env.COMMIT_V,
        spec_path: process.env.SPEC_PATH_V,
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
