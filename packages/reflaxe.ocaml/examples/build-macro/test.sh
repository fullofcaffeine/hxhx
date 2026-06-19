#!/usr/bin/env bash
set -euo pipefail

grep -qx 'generated=from_build_macro' expected.stdout
grep -qx 'OK build-macro' expected.stdout
