#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SMOKE_FIXTURE_ID="__semantic_diff_minimizer_smoke"
SMOKE_FIXTURE_DIR="$ROOT/test/portable/fixtures/$SMOKE_FIXTURE_ID"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$SMOKE_FIXTURE_DIR"' EXIT

DIVERGENCE_REPORT="$TMP_DIR/divergence_report.json"
OUT_DIR="$TMP_DIR/generated"
MANIFEST_PATH="$OUT_DIR/minimized_manifest.json"

mkdir -p "$SMOKE_FIXTURE_DIR/src"
cat > "$SMOKE_FIXTURE_DIR/src/Main.hx" <<'EOF'
class Main {
	public static function main() {
		var value = 42;
		var text = "KEEP_TOKEN";
		if (value > 0) {
			trace(text);
		}
	}
}
EOF

cat > "$DIVERGENCE_REPORT" <<EOF
{
  "schemaVersion": 1,
  "contractId": "reflaxe.family.std.semantic_diff_divergence_report",
  "contractVersion": "1.0.0",
  "leftAdapterId": "synthetic_left",
  "rightAdapterId": "synthetic_right",
  "summary": {
    "fixturesCompared": 1,
    "divergenceCount": 1
  },
  "divergences": [
    {
      "fixtureId": "$SMOKE_FIXTURE_ID",
      "differingFields": ["stdout"],
      "replayCommands": {
        "left": "if rg -q 'KEEP_TOKEN' test/portable/fixtures/$SMOKE_FIXTURE_ID/src/Main.hx; then echo A; else echo B; fi",
        "right": "echo B"
      }
    }
  ]
}
EOF

echo "== semantic-diff minimizer: minimize synthetic divergence"
node scripts/stdlib/minimize-semantic-diff-divergences.js \
  --divergence-report "$DIVERGENCE_REPORT" \
  --out-dir "$OUT_DIR" \
  --no-print-json

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "Missing minimizer manifest: $MANIFEST_PATH" >&2
  exit 1
fi

node -e '
const fs = require("fs");
const manifestPath = process.argv[1];
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (manifest.summary?.exportedCount !== 1) {
  console.error("expected exportedCount=1");
  process.exit(1);
}
if (manifest.summary?.minimizedCount !== 1) {
  console.error("expected minimizedCount=1");
  process.exit(1);
}
const first = Array.isArray(manifest.results) ? manifest.results[0] : null;
if (first == null) {
  console.error("missing first minimizer result");
  process.exit(1);
}
if ((first.stats?.beforeBytes ?? 0) <= (first.stats?.afterBytes ?? 0)) {
  console.error("expected beforeBytes > afterBytes");
  process.exit(1);
}
if (typeof first.output?.metadataPath !== "string" || first.output.metadataPath.length === 0) {
  console.error("missing metadataPath in minimizer result");
  process.exit(1);
}
process.stdout.write("semantic-diff minimizer manifest checks OK\n");
' "$MANIFEST_PATH"

echo "✓ semantic-diff minimizer smoke OK"
