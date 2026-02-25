#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== stdlib portable full: tier1 baseline"
bash scripts/test-stdlib-portable-tier1.sh

echo "== stdlib portable full: Stage0 runtime/stdlib integration set"
npm run test:m6:runtime
npm run test:m6:array
npm run test:m6:string
npm run test:m6:bytes
npm run test:m6:map
npm run test:m6:sys-env
npm run test:m6:filestat
npm run test:m6:exceptions

echo "✓ stdlib portable full OK"
