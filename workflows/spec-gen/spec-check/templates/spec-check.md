set -euo pipefail
repo="{{workspace_repo}}"
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
fi
