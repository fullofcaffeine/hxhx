#!/usr/bin/env bash
set -euo pipefail

bash run-haxe-oracle.sh
node verify-enum-dynamic-plan.js
