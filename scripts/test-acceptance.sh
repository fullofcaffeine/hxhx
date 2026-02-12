#!/usr/bin/env bash
set -euo pipefail

# Run heavier acceptance checks:
# 1) acceptance-only examples under examples/
# 2) compiler-shaped workloads under workloads/
#
# By default, workloads run in `fast` profile to keep developer iteration snappy.
# Use WORKLOAD_PROFILE=full (or npm run test:acceptance:full) to include heavy
# compiler-shaped workloads.

WORKLOAD_PROFILE="${WORKLOAD_PROFILE:-fast}"
echo "== Acceptance workload profile: ${WORKLOAD_PROFILE}"

ONLY_ACCEPTANCE_EXAMPLES=1 bash scripts/test-examples.sh
WORKLOAD_PROFILE="$WORKLOAD_PROFILE" bash scripts/test-workloads.sh
