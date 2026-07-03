#!/usr/bin/env bash
# Acceptance checks for loop-engine-bootstrap-plugin.
# These checks are deterministic and do not call LLMs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check(){ if [ ! -e "$ROOT/$1" ]; then echo "MISSING: $1" >&2; fail=1; else echo "ok: $1"; fi; }

check "workflows/fleet.yaml.tpl"
check "workflows/spec-gen/draft/workflow.yaml"
check "workflows/spec-gen/draft/personas/drafter.md"
check "workflows/spec-gen/draft/templates/draft.md"
check "workflows/spec-gen/review/workflow.yaml"
check "workflows/spec-gen/review/personas/spec-reviewer.md"
check "workflows/spec-gen/review/templates/spec-review.md"
check "workflows/spec-gen/rework/workflow.yaml"
check "workflows/spec-gen/rework/templates/spec-rework.md"
check "bin/bootstrap-loop.sh"
check "scripts/render-template.mjs"

ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
ENGINE_DIST_FLEET="$ENGINE_ROOT/dist/fleet.js"

if [ ! -f "$ENGINE_DIST_FLEET" ]; then
  echo "SKIP: Loop Engine dist missing; build it to run schema validation" >&2
else
  RUN_ROOT="$ROOT/.runtime/test-acceptance"
  rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT"

  export PLUGIN_ROOT="$ROOT"
  export DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
  export RUN_ROOT
  export IDEA_STORE_DIR="$RUN_ROOT/stores/idea"
  export SPEC_PR_STORE_DIR="$RUN_ROOT/stores/spec-pr"
  export SPEC_VERDICT_STORE_DIR="$RUN_ROOT/stores/spec-verdict"
  export TRIGGER_STORE_DIR="$RUN_ROOT/stores/trigger"
  export PR_STORE_DIR="$RUN_ROOT/stores/pr"
  export VERDICT_STORE_DIR="$RUN_ROOT/stores/verdict"
  export WORKSPACE_REPO="$RUN_ROOT/workspace-repo"
  export DIFF_DIR="$RUN_ROOT/diffs"
  export REF_LIBRARY_DIR="$RUN_ROOT/ref-lib"
  export REF_LIBRARY_INDEX="$RUN_ROOT/ref-lib/index.md"
  export BOOT_DRAFT_MODEL="test-model"
  export BOOT_DRAFT_RUNTIME="bash"
  export BOOT_REVIEW_MODEL="test-model"
  export BOOT_WORK_MODEL="test-model"
  export BOOT_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_WORK_MODEL="test-model"
  export DD_WORK_RUNTIME="bash"
  export DD_REVIEW_MODEL="test-model"
  export DD_CLAUDE_CONFIG_DIR="$RUN_ROOT/.claude"
  export DD_ACCEPT_CMD="npm test"
  export BOOT_MAX_PASSES="8"

  mkdir -p "$REF_LIBRARY_DIR"
  echo "# Reference library index" > "$REF_LIBRARY_INDEX"

  RENDERED_FLEET="$RUN_ROOT/fleet.yaml"
  node "$ROOT/scripts/render-template.mjs" "$ROOT/workflows/fleet.yaml.tpl" "$RENDERED_FLEET"
  echo "ok: fleet.yaml rendered"

  export ENGINE_DIST_FLEET RENDERED_FLEET PLUGIN_ROOT

  # Validate the rendered fleet manifest against loop-engine's schema.
  schema_check_js="$(mktemp --suffix=.mjs)"
  cat > "$schema_check_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
try {
  const manifest = loadFleetManifest(process.env.RENDERED_FLEET);
  const labels = manifest.pipelines.map((p) => p.label).sort();
  const expected = ["deploy", "draft", "review", "rework", "spec-review", "spec-rework", "work"];
  if (JSON.stringify(labels) !== JSON.stringify(expected)) {
    console.error("unexpected pipeline labels: " + labels.join(","));
    process.exit(1);
  }
  console.log("ok: fleet manifest schema valid");
} catch (e) {
  console.error("fleet manifest invalid: " + e.message);
  process.exit(1);
}
NODE
  node "$schema_check_js" || fail=1
  rm -f "$schema_check_js"

  # INV-2: Impl Loop four pipelines must point at dev-dispatch, not local copies.
  impl_check_js="$(mktemp --suffix=.mjs)"
  cat > "$impl_check_js" <<'NODE'
const { loadFleetManifest } = await import(process.env.ENGINE_DIST_FLEET);
const manifest = loadFleetManifest(process.env.RENDERED_FLEET);
const impl = ["work", "review", "rework", "deploy"];
const localPrefix = process.env.PLUGIN_ROOT + "/";
let ok = true;
for (const label of impl) {
  const p = manifest.pipelines.find((p) => p.label === label);
  if (!p) { console.error("missing pipeline: " + label); ok = false; continue; }
  if (p.config_dir.startsWith(localPrefix)) {
    console.error("FAIL: " + label + " config_dir is local: " + p.config_dir);
    ok = false;
  }
}
if (ok) console.log("ok: Impl Loop config_dirs point outside bootstrap plugin");
else process.exit(1);
NODE
  node "$impl_check_js" || fail=1
  rm -f "$impl_check_js"

  # INV-1: bin/ contains only the bootstrap-loop driver, no inter-loop glue scripts.
  bin_scripts=($(find "$ROOT/bin" -maxdepth 1 -type f ! -name '.gitkeep'))
  if [ "${#bin_scripts[@]}" -eq 1 ] && [ "$(basename "${bin_scripts[0]}")" = "bootstrap-loop.sh" ]; then
    echo "ok: bin/ has only bootstrap-loop.sh"
  else
    echo "FAIL: bin/ contains unexpected scripts: ${bin_scripts[*]}" >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then echo "acceptance FAILED"; exit 1; fi
echo "acceptance PASSED"
