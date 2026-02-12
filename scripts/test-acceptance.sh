#!/usr/bin/env bash
set -euo pipefail

# Run heavier acceptance checks:
# 1) acceptance-only examples under examples/
# 2) compiler-shaped workloads under workloads/

ONLY_ACCEPTANCE_EXAMPLES=1 bash scripts/test-examples.sh
bash scripts/test-workloads.sh
