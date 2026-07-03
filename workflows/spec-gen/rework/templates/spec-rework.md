set -euo pipefail
loop_store_cli="{{loop_store_cli}}"
idea_store_dir="{{idea_store_dir}}"
trigger_store_dir="{{trigger_store_dir}}"
spec_verdict_id="$(cat <<'EOF'
{{spec_verdict_id}}
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
verdict="$(cat <<'EOF'
{{verdict}}
EOF
)"
feedback="$(cat <<'EOF'
{{feedback}}
EOF
)"
feedback_file="$(cat <<'EOF'
{{feedback_file?}}
EOF
)"

if [ "$verdict" = "APPROVE" ]; then
  # Hand off to the Impl Loop trigger store — the single native store route seam.
  trigger_payload="$(
    SPEC_ID="$spec_id" SPEC_FILE="$spec_file" node -e '
process.stdout.write(JSON.stringify({
  id: process.env.SPEC_ID,
  status: "open",
  spec_file: process.env.SPEC_FILE,
  feedback: "(none)",
}));
'
  )"
  node "$loop_store_cli" "$trigger_store_dir" put "$trigger_payload" >/dev/null
elif [ "$verdict" = "REJECT" ]; then
  # Send the idea back to the idea store for a fresh draft attempt.
  base_idea_id="${spec_id%%-r[0-9]*}"
  rework_idea_id="$base_idea_id-r$(date +%s)"
  idea_payload="$(
    IDEA_ID="$rework_idea_id" SPEC_FILE="$spec_file" FEEDBACK="$feedback" FEEDBACK_FILE="$feedback_file" node -e '
process.stdout.write(JSON.stringify({
  id: process.env.IDEA_ID,
  status: "open",
  spec_file: process.env.SPEC_FILE,
  feedback_file: process.env.FEEDBACK_FILE,
  feedback: `Spec review REJECT on a previous attempt. Read the full review and address every point. Summary: ${process.env.FEEDBACK}`,
}));
'
  )"
  node "$loop_store_cli" "$idea_store_dir" put "$idea_payload" >/dev/null
else
  echo "unsupported verdict: $verdict" >&2
  exit 1
fi

VERDICT="$verdict" node -e 'process.stdout.write(JSON.stringify({ result: `spec-rework consumed ${process.env.VERDICT}`, effects: [{ op: "halt" }] }))'
