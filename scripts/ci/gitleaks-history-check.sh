#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

resolve_gitleaks_bin() {
	if command -v gitleaks >/dev/null 2>&1; then
		command -v gitleaks
		return 0
	fi

	if [ -x "$ROOT_DIR/gitleaks" ]; then
		echo "$ROOT_DIR/gitleaks"
		return 0
	fi

	return 1
}

if ! GITLEAKS_BIN="$(resolve_gitleaks_bin)"; then
	echo "[guard:gitleaks] ERROR: gitleaks is required but was not found." >&2
	echo "[guard:gitleaks] Install: https://github.com/gitleaks/gitleaks#installing" >&2
	exit 1
fi

echo "[guard:gitleaks] Running gitleaks on full git history..."
"$GITLEAKS_BIN" detect --source . --config .gitleaks.toml --redact --log-opts="--all"
echo "[guard:gitleaks] OK: no leaks found."
