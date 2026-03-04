# Embedding `hxhx` (Supported Subprocess Contract)

This page defines the supported embedding surface for integrating `hxhx` into another application.

Current scope: **subprocess embedding** (spawn `hxhx`, pass args/env, consume exit code + diagnostics + report artifacts).

## Contract ID

- `hxhx.embed.subprocess.v1`

Use this ID in your integration docs/config so upgrades are explicit and auditable.

## Supported surface (v1)

### Stable inputs

- Executable path:
  - `hxhx` from a local build (`bash scripts/hxhx/build-hxhx.sh`)
  - or distribution layout `dist/hxhx/<version>/<platform>-<arch>/bin/hxhx`
- CLI arguments:
  - Upstream-compatible args (`-cp`, `-main`, `-D`, output flags)
  - `hxhx` lane args (`--ocaml`, `--ocaml-eval`, `--compat`, and canonical `--js <file>`)
- Environment variables:
  - `HXHX_FORBID_STAGE0=1` to enforce non-delegating behavior during native-lane embedding
  - `HXHX_MACRO_HOST_EXE=/path/to/hxhx-macro-host` when macro-host resolution must be explicit

### Stable outputs

- Process exit code:
  - `0` for successful compilation
  - non-zero for compilation/runtime contract failure
- Diagnostics stream:
  - compiler diagnostics are emitted to process output streams (stdout/stderr)
  - location-bearing diagnostics should remain in `file:line:col` style when available
- Emit/report artifacts in your chosen output directory:
  - Stage3 OCaml lane report:
    - `ocaml_portable_metalization_plan_report.json`
  - Stage0 `reflaxe.ocaml` runtime planning reports (when using that path):
    - `ocaml_profile_report.json`
    - `ocaml_runtime_plan_report.json`

## Versioning guarantees

- `v1` is the supported embedding baseline for subprocess usage.
- Additive behavior is allowed in `v1` (extra optional JSON fields, extra non-breaking diagnostics).
- Breaking contract changes require a new contract ID (`...v2`) and a corresponding doc update.

## Runnable example (compile + diagnostics + report capture)

Run:

```bash
npm run hxhx:example:embedding-subprocess
```

What it does:

1. Resolves or builds `hxhx`.
2. Compiles `examples/hxhx-embedding-subprocess/src/Main.hx` with `--ocaml` and captures:
   - exit code
   - stdout/stderr logs
   - `ocaml_portable_metalization_plan_report.json` summary
3. Runs a deterministic failing compile (`-main MissingMain`) and captures diagnostics.
4. Writes a machine-readable summary:
   - `.tmp/embedding-subprocess-example/embedding_subprocess_result.json`

Pass marker:

- `EMBEDDING_SUBPROCESS_EXAMPLE:PASS`

## Integration checklist (host app)

1. Pin the contract ID (`hxhx.embed.subprocess.v1`) in your host integration config.
2. Spawn `hxhx` with explicit args and an explicit output directory per request.
3. Capture both stdout and stderr for diagnostics/audit logs.
4. Parse expected JSON reports from the output directory when targeting OCaml lanes.
5. Treat non-zero exit codes as compile failures and return diagnostics upstream to callers.

## Related docs

- `docs/00-project/BOUNDARIES.md`
- `docs/02-user-guide/HXHX_DISTRIBUTION.md`
- `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
