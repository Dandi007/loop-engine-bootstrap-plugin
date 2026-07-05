#!/usr/bin/env bash
# Static tests for SPEC-003-b2-pipeline-contracts.
# Verifies the bootstrap-plugin's six self-bootstrap workflows declare io
# contracts (io: section + contracts/*.schema.json) and that the record schemas
# are ajv-compilable and accept/reject the right fixtures.
#
# This test does NOT call LLMs and does NOT run drain. It only does static
# assertions: io section presence, schema originals, ajv compile, fixture
# validate, symlink integrity, io/routes key parity, and the dd-plugin
# exemption anchor (INV-4).
#
# ajv and yaml are borrowed from the engine dependency tree (engine package.json
# depends on ajv@^8.20.0 / yaml@^2.5.0); this repo stays zero-npm-dependency.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_ROOT="${LOOP_ENGINE_ROOT:-/data/code/self/loop-engine}"
DD_PLUGIN_ROOT="${DD_PLUGIN_ROOT:-/data/code/self/loop-engine-dev-dispatch-plugin}"
fail=0

if [ ! -d "$ENGINE_ROOT/node_modules/ajv" ]; then
  echo "SKIP: engine node_modules/ajv missing; npm install in $ENGINE_ROOT" >&2
  exit 0
fi

CONTRACTS_DIR="$ROOT/workflows/spec-gen/contracts"

# ---------------------------------------------------------------------------
# TC-1: exactly 6 workflow.yaml have an io: section (top-level, line-anchored)
# ---------------------------------------------------------------------------
io_count="$(grep -l '^io:' "$ROOT"/workflows/spec-gen/*/workflow.yaml 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$io_count" -eq 6 ]; then
  echo "ok: TC-1 io section on all 6 workflows"
else
  echo "FAIL: TC-1 io count=$io_count expected 6" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-2: exactly 5 schema originals under contracts/, name set matches
# ---------------------------------------------------------------------------
expected_names="idea pr spec-pr trigger verdict"
actual_count="$(find "$CONTRACTS_DIR" -maxdepth 1 -name '*.schema.json' -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$actual_count" -eq 5 ]; then
  echo "ok: TC-2 schema original count=5"
else
  echo "FAIL: TC-2 schema original count=$actual_count expected 5" >&2
  fail=1
fi
actual_names="$(find "$CONTRACTS_DIR" -maxdepth 1 -name '*.schema.json' -type f 2>/dev/null -exec basename {} .schema.json \; | sort | tr '\n' ' ' | sed 's/ *$//' || true)"
expected_sorted="$(echo "$expected_names" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//')"
if [ "$actual_names" = "$expected_sorted" ]; then
  echo "ok: TC-2 schema name set matches {idea,pr,spec-pr,trigger,verdict}"
else
  echo "FAIL: TC-2 schema name set='$actual_names' expected='$expected_sorted'" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-3: all 5 originals ajv-compilable (compile throws on bad schema → non-0 exit)
# ---------------------------------------------------------------------------
tc3_fail=0
shopt -s nullglob
schema_files=("$CONTRACTS_DIR"/*.schema.json)
shopt -u nullglob
if [ "${#schema_files[@]}" -eq 0 ]; then
  echo "FAIL: TC-3 no schema files found under $CONTRACTS_DIR" >&2
  tc3_fail=1
fi
for schema_file in "${schema_files[@]}"; do
  if ! ENGINE_ROOT="$ENGINE_ROOT" node -e '
    const { createRequire } = require("node:module");
    const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
    const Ajv = req("ajv");
    const ajv = new Ajv({ allErrors: true });   // 与 engine src/output-contract.ts:101 同参
    const schema = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
    ajv.compile(schema);                         // 编译失败即抛错退出非 0
  ' "$schema_file"; then
    echo "FAIL: TC-3 ajv compile failed for $schema_file" >&2
    tc3_fail=1
  fi
done
if [ "$tc3_fail" -eq 0 ]; then
  echo "ok: TC-3 all 5 schemas ajv-compilable"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-4 / TC-5 / TC-6: fixture validate (good pass / bad reject / wide-input pass)
# ---------------------------------------------------------------------------
# Build a temp dir of fixtures and a node validator that compiles each schema
# once and validates the records. Records are tagged {schema, expect, record}.
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Good records (TC-4): one per class. trigger uses the -r<epoch> rework-suffix
# id variant; verdict has both pr_id and spec_pr_id variants (2 examples).
cat > "$FIXTURE_DIR/good-trigger.json" <<'JSON'
{"schema":"trigger","expect":"pass","record":{"id":"SPEC-170-b2-pipeline-contracts-r1783237261","status":"done","spec_file":"/tmp/SPEC-170.md","feedback":"(none)","spec_id":"SPEC-170"}}
JSON
cat > "$FIXTURE_DIR/good-pr.json" <<'JSON'
{"schema":"pr","expect":"pass","record":{"id":"pr-SPEC-004","status":"checking","spec_id":"SPEC-004","spec_file":"/tmp/SPEC-004.md","branch":"dd/SPEC-004","base_commit":"abc123","diff":"...","diff_file":"/tmp/x.diff","claimed_by":"spec-check"}}
JSON
cat > "$FIXTURE_DIR/good-verdict-pr.json" <<'JSON'
{"schema":"verdict","expect":"pass","record":{"id":"verdict-SPEC-002","status":"decided","spec_id":"SPEC-002","verdict":"APPROVE","feedback":"ok","pr_id":"pr-SPEC-002"}}
JSON
cat > "$FIXTURE_DIR/good-verdict-specpr.json" <<'JSON'
{"schema":"verdict","expect":"pass","record":{"id":"verdict-SPEC-005","status":"reworked","spec_id":"SPEC-005","verdict":"REJECT","feedback":"too vague","spec_pr_id":"spec-pr-SPEC-005"}}
JSON
cat > "$FIXTURE_DIR/good-spec-pr.json" <<'JSON'
{"schema":"spec-pr","expect":"pass","record":{"id":"spec-pr-SPEC-001","status":"reviewing","spec_id":"SPEC-001","spec_file":"/tmp/SPEC-001.md","claimed_by":"spec-review"}}
JSON
cat > "$FIXTURE_DIR/good-idea.json" <<'JSON'
{"schema":"idea","expect":"pass","record":{"id":"idea-bootstrap-seed","status":"open","feedback":"bootstrap seed idea","feedback_file":"","spec_file":""}}
JSON

# Bad records (TC-5): >=4 rejections
cat > "$FIXTURE_DIR/bad-pr-status.json" <<'JSON'
{"schema":"pr","expect":"reject","record":{"id":"pr-SPEC-004","status":"bogus","spec_id":"SPEC-004","spec_file":"/tmp/SPEC-004.md","branch":"dd/SPEC-004","base_commit":"abc123"}}
JSON
cat > "$FIXTURE_DIR/bad-trigger-missing-spec_file.json" <<'JSON'
{"schema":"trigger","expect":"reject","record":{"id":"SPEC-170-x","status":"open","feedback":"(none)"}}
JSON
cat > "$FIXTURE_DIR/bad-verdict-maybe.json" <<'JSON'
{"schema":"verdict","expect":"reject","record":{"id":"verdict-SPEC-002","status":"decided","spec_id":"SPEC-002","verdict":"MAYBE","feedback":"undecided"}}
JSON
cat > "$FIXTURE_DIR/bad-idea-empty-id.json" <<'JSON'
{"schema":"idea","expect":"reject","record":{"id":"","status":"open","feedback":"x"}}
JSON

# Wide-input regression (TC-6, INV-3): pr record with unknown fields must PASS
cat > "$FIXTURE_DIR/wide-pr.json" <<'JSON'
{"schema":"pr","expect":"pass","record":{"id":"pr-SPEC-009","status":"ready","spec_id":"SPEC-009","spec_file":"/tmp/SPEC-009.md","branch":"dd/SPEC-009","base_commit":"abc123","repo":"loop-engine","commit":"def456"}}
JSON

if ! ENGINE_ROOT="$ENGINE_ROOT" ROOT="$ROOT" FIXTURE_DIR="$FIXTURE_DIR" node -e '
  const { createRequire } = require("node:module");
  const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
  const Ajv = req("ajv");
  const fs = require("node:fs");
  const path = require("node:path");
  const ajv = new Ajv({ allErrors: true });
  const contractsDir = path.join(process.env.ROOT, "workflows/spec-gen/contracts");
  // Compile each schema once.
  const validate = {};
  for (const f of fs.readdirSync(contractsDir)) {
    if (!f.endsWith(".schema.json")) continue;
    const name = f.replace(/\.schema\.json$/, "");
    const schema = JSON.parse(fs.readFileSync(path.join(contractsDir, f), "utf8"));
    validate[name] = ajv.compile(schema);
  }
  let bad = 0;
  for (const f of fs.readdirSync(process.env.FIXTURE_DIR).sort()) {
    const { schema, expect, record } = JSON.parse(fs.readFileSync(path.join(process.env.FIXTURE_DIR, f), "utf8"));
    const v = validate[schema];
    if (!v) { console.error("no schema compiled for " + schema); bad = 1; continue; }
    const ok = v(record);
    const wantPass = expect === "pass";
    if (ok !== wantPass) {
      console.error("FAIL: " + f + " expected " + expect + " but validate=" + ok +
        (ok ? "" : " errors=" + JSON.stringify(v.errors)));
      bad = 1;
    }
  }
  if (bad) process.exit(1);
'; then
  echo "FAIL: TC-4/TC-5/TC-6 fixture validation mismatch" >&2
  fail=1
else
  echo "ok: TC-4/TC-5/TC-6 fixtures validate (good pass, bad reject, wide-input pass)"
fi

# ---------------------------------------------------------------------------
# TC-7: symlink integrity (INV-5) — exactly 13 symlinks, 0 plain copies,
#       every realpath lands inside the originals directory
# ---------------------------------------------------------------------------
link_count="$(find "$ROOT"/workflows/spec-gen/*/contracts -name '*.schema.json' -type l 2>/dev/null | wc -l | tr -d ' ' || true)"
copy_count="$(find "$ROOT"/workflows/spec-gen/*/contracts -name '*.schema.json' ! -type l 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$link_count" -eq 13 ]; then
  echo "ok: TC-7 symlink count=13"
else
  echo "FAIL: TC-7 symlink count=$link_count expected 13" >&2
  fail=1
fi
if [ "$copy_count" -eq 0 ]; then
  echo "ok: TC-7 plain-copy count=0 (single source of truth)"
else
  echo "FAIL: TC-7 plain-copy count=$copy_count expected 0" >&2
  fail=1
fi
# Every symlink realpath must land inside the originals directory.
tc7_path_fail=0
if [ -d "$CONTRACTS_DIR" ]; then
  orig_abs="$(cd "$CONTRACTS_DIR" && pwd)"
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    target="$(realpath "$link" 2>/dev/null || true)"
    if [ -z "$target" ] || ! echo "$target" | grep -q "^${orig_abs}/"; then
      echo "FAIL: TC-7 symlink $link realpath '$target' not under $orig_abs" >&2
      tc7_path_fail=1
    fi
  done < <(find "$ROOT"/workflows/spec-gen/*/contracts -name '*.schema.json' -type l 2>/dev/null)
else
  echo "FAIL: TC-7 contracts dir missing; cannot verify symlink targets" >&2
  tc7_path_fail=1
fi
if [ "$tc7_path_fail" -eq 0 ]; then
  echo "ok: TC-7 all symlinks resolve under contracts/ originals"
else
  fail=1
fi

# ---------------------------------------------------------------------------
# TC-8: io.out key set == routes key set, io.in non-empty, contract paths
#       start with contracts/ (INV-7). Uses engine yaml package.
# ---------------------------------------------------------------------------
if ! ENGINE_ROOT="$ENGINE_ROOT" ROOT="$ROOT" node -e '
  const { createRequire } = require("node:module");
  const req = createRequire(process.env.ENGINE_ROOT + "/package.json");
  const YAML = req("yaml");
  const fs = require("node:fs");
  const path = require("node:path");
  const root = process.env.ROOT;
  const dirs = ["draft", "review", "rework", "spec-check", "deploy-verify", "merger"];
  let bad = 0;
  for (const d of dirs) {
    const wfPath = path.join(root, "workflows/spec-gen", d, "workflow.yaml");
    const wf = YAML.parse(fs.readFileSync(wfPath, "utf8"));
    if (!wf.io || !wf.io.in || !wf.io.out) {
      console.error("FAIL: TC-8 " + d + " missing io.in or io.out");
      bad = 1; continue;
    }
    if (!wf.io.in.queue || !wf.io.in.contract) {
      console.error("FAIL: TC-8 " + d + " io.in.queue/contract empty");
      bad = 1;
    }
    if (!wf.io.in.contract.startsWith("contracts/")) {
      console.error("FAIL: TC-8 " + d + " io.in.contract does not start with contracts/: " + wf.io.in.contract);
      bad = 1;
    }
    for (const [q, c] of Object.entries(wf.io.out)) {
      if (!String(c).startsWith("contracts/")) {
        console.error("FAIL: TC-8 " + d + " io.out[" + q + "] contract does not start with contracts/: " + c);
        bad = 1;
      }
    }
    const outKeys = Object.keys(wf.io.out).sort().join(",");
    const routeKeys = Object.keys(wf.routes || {}).sort().join(",");
    if (outKeys !== routeKeys) {
      console.error("FAIL: TC-8 " + d + " io.out keys [" + outKeys + "] != routes keys [" + routeKeys + "]");
      bad = 1;
    }
  }
  if (bad) process.exit(1);
'; then
  echo "FAIL: TC-8 io/routes key parity mismatch" >&2
  fail=1
else
  echo "ok: TC-8 io.out keys == routes keys for all 6 workflows"
fi

# ---------------------------------------------------------------------------
# TC-9: dd-plugin exemption anchor (INV-4) — exactly 0 io: sections in the
# dd-plugin's three workflows. Exemption basis: design §2 B2 line scopes to
# "self-bootstrap six workflows"; the dd-plugin work/review/rework trio (third
# repo) is contracted on its own roadmap. B1 lesson PR #6 (edb1a85): a
# zero-clearance assertion wrongly clobbered an exempt item (fleet-impl rework
# input loop_store_cli), so the exemption MUST carry a keep-assertion (count==0
# against the dd repo path), not just a count against this repo.
# ---------------------------------------------------------------------------
if [ ! -d "$DD_PLUGIN_ROOT" ]; then
  echo "SKIP: TC-9 dd-plugin root $DD_PLUGIN_ROOT not available; exemption anchor not evaluated" >&2
else
  dd_io_count="$(grep -l '^io:' "$DD_PLUGIN_ROOT"/workflows/spec/*/workflow.yaml 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ "$dd_io_count" -eq 0 ]; then
    echo "ok: TC-9 dd-plugin exemption anchor (io count=0)"
  else
    echo "FAIL: TC-9 dd-plugin io count=$dd_io_count expected 0 (exemption violated)" >&2
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "pipeline-contracts FAILED"
  exit 1
fi
echo "pipeline-contracts PASSED"
