set -euo pipefail
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
  # Emit an enqueue effect; the engine applies it via the workflow's routes table.
  SPEC_ID="$spec_id" SPEC_FILE="$spec_file" node -e '
process.stdout.write(JSON.stringify({
  result: "spec-rework APPROVE: enqueued trigger for " + process.env.SPEC_ID,
  effects: [
    { op: "enqueue", queue: "trigger", task: {
        id: process.env.SPEC_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback: "(none)",
    }},
    { op: "halt" },
  ],
}));
'
  exit 0
elif [ "$verdict" = "REJECT" ]; then
  # Send the idea back to the idea store for a fresh draft attempt.
  base_idea_id="${spec_id%%-r[0-9]*}"
  rework_idea_id="$base_idea_id-r$(date +%s)"
  IDEA_ID="$rework_idea_id" SPEC_FILE="$spec_file" FEEDBACK_FILE="$feedback_file" FEEDBACK="$feedback" node -e '
process.stdout.write(JSON.stringify({
  result: "spec-rework REJECT: enqueued idea " + process.env.IDEA_ID,
  effects: [
    { op: "enqueue", queue: "idea", task: {
        id: process.env.IDEA_ID,
        status: "open",
        spec_file: process.env.SPEC_FILE,
        feedback_file: process.env.FEEDBACK_FILE,
        feedback: "Spec review REJECT on a previous attempt. Read the full review and address every point. Summary: " + process.env.FEEDBACK,
    }},
    { op: "halt" },
  ],
}));
'
  exit 0
else
  echo "unsupported verdict: $verdict" >&2
  exit 1
fi
