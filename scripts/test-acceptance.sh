#!/usr/bin/env bash
set -euo pipefail

# Run acceptance-only examples (heavier workloads).
# This delegates to the existing examples runner with a filter flag.

ONLY_ACCEPTANCE_EXAMPLES=1 bash scripts/test-examples.sh

