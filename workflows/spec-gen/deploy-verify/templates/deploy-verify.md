set -euo pipefail
repo="{{workspace_repo}}"
loop_store_cli="{{loop_store_cli}}"
pr_store_dir="{{pr_store_dir}}"
deploy_log_dir="{{deploy_log_dir}}"
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

mkdir -p "$deploy_log_dir"
accept_log="$deploy_log_dir/$pr_id-accept.log"

# Checkout the branch and run acceptance tests.
# NO merge to base branch — that is the merger's job.
git -C "$repo" checkout -q "$branch"
verify_status="verify_failed"
failure_reason=""

if (cd "$repo" && sh -lc "$accept_cmd") > "$accept_log" 2>&1; then
  verify_status="ready-to-merge"
else
  failure_reason="acceptance command failed on branch $branch: $accept_cmd
--- last 60 lines of $accept_log ---
$(tail -n 60 "$accept_log")"
fi

node "$loop_store_cli" "$pr_store_dir" update "$pr_id" "{\"status\":\"$verify_status\"}" verifying >/dev/null

if [ "$verify_status" != "ready-to-merge" ]; then
  base_spec_id="${spec_id%%-r[0-9]*}"
  redo_spec_id="$base_spec_id-r$(date +%s)"
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
