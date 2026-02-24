<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![Compatibility Gate 1 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml)
[![Compatibility Gate 2 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml)
[![Compatibility Gate 3 Builtin](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml)
[![JS Oracle Smoke](https://github.com/fullofcaffeine/hxhx/actions/workflows/js-oracle-smoke.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/js-oracle-smoke.yml)
[![Compatibility Gate 1](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml)
[![Compatibility Gate 2](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml)
[![Compatibility Gate 3](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.12.0-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack targeting Haxe `4.3.7` compatibility.  
It is developed together with `reflaxe.ocaml` so the toolchain can bootstrap and ship native binaries under MIT.

## Why this exists

- Make compiler internals easier to understand and modify.
- Track upstream Haxe `4.3.7` behavior using oracle-driven gates.
- Keep a permissive, embeddable distribution path.
- Compile Reflaxe targets to native binaries for better performance.

## Current status

- Compatibility target is **Haxe `4.3.7`**.
- Per-commit checks run **Gate 1 Lite**, **Gate 2 Lite**, **Gate 3 Builtin**, and a **strict plugin matrix** lane.
- Per-commit CI also runs a **JS oracle smoke** lane (upstream `haxe` vs `hxhx js-native` runtime output on repo-local fixtures).
- Full upstream compatibility gates (**Gate 1/2/3**) run weekly and on manual trigger.
- Legacy Flash/AS3 targets are intentionally unsupported.
- `hxhx` and `reflaxe.ocaml` are usable now; parity/performance work continues.

## Choose your path

- **Evaluate `hxhx`**
  - [Roadmap and milestones](docs/01-getting-started/HXHX_1_0_ROADMAP.md)
  - [Acceptance criteria and gate definitions](docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md)
  - [Testing and gate workflows](docs/01-getting-started/TESTING.md)
- **Use `reflaxe.ocaml` now**
  - [`reflaxe.ocaml` README](packages/reflaxe.ocaml/README.md)
  - [Use `reflaxe.ocaml` with upstream Haxe](docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)
- **Contribute to compiler/backend work**
  - [Backend layering and contracts](docs/02-user-guide/HXHX_BACKEND_LAYERING.md)
  - [Builtin backend behavior](docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md)
  - [Macro host protocol](docs/02-user-guide/HXHX_MACRO_HOST_PROTOCOL.md)
  - [Stdlib sync boundary](docs/00-project/STD_LIB_POLICY.md)
  - [Provenance policy (MIT shipping path)](docs/00-project/PROVENANCE_POLICY.md)

## Quick start (contributors)

```bash
npm install
npx lix download
npm run ci:guards
npm test
```

Build `hxhx` from committed bootstrap snapshots:

```bash
bash scripts/hxhx/build-hxhx.sh
```

Refresh committed bootstrap snapshots (`packages/hxhx/bootstrap_out`):

```bash
# Full deterministic refresh (clean + verify)
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh

# Faster local loop (incremental emit + skip verify)
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast

# Reuse a repo-owned haxe --wait server:
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --use-repo-server --keep-repo-server --incremental --no-verify

# Skip stage0 emit entirely when inputs are unchanged:
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --skip-if-unchanged --incremental --no-verify

# Server cleanup choices:
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --kill-repo-server          # safe, repo-owned only
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --kill-all-haxe-servers     # unsafe, global kill

# Repo-owned haxe server helper:
bash scripts/hxhx/haxe-server.sh start
bash scripts/hxhx/haxe-server.sh status
bash scripts/hxhx/haxe-server.sh stop

# If heartbeat is disabled but you still want periodic diagnostics:
HXHX_STAGE0_HEARTBEAT=0 HXHX_STAGE0_DIAG_EVERY=30 \
  bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast
```

Benchmark the regen harness (cold/warm/skip scenarios):

```bash
npm run hxhx:bench:bootstrap-regen
```

Optional JS parity smoke (upstream compiler vs `hxhx js-native` runtime behavior):

```bash
npm run test:upstream:js-oracle-smoke
```

Self-hosting status/smoke:

```bash
npm run status:self-hosting
npm run test:self-hosting-smoke
npm run test:stage0-policy

# Strict replacement-ready bundle (delegation blocked):
HXHX_M7_STRICT=1 HXHX_FORBID_STAGE0=1 npm run test:upstream:replacement-ready:full

# Strict plugin matrix (macro libs + eval.vm API smoke + Stage3 plugin fixture):
HXHX_PLUGIN_MATRIX_STRICT=1 npm run test:plugins:strict-matrix
```

## Environment setup

Required tools:

- Node.js + npm
- Haxe `4.3.7`
- OCaml `5.2+`, `dune`, `ocaml-findlib` (for native lanes)

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Linux (opam):

```bash
sudo apt-get update
sudo apt-get install -y opam m4 pkg-config libgmp-dev
opam init -a --disable-sandboxing
opam switch create 5.2.1
eval "$(opam env)"
opam install -y dune ocamlfind
```

## Reflaxe OCaml quick usage

Emit OCaml from Haxe:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Emit + native build:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

For full usage and mainstream Haxe integration, see
[`packages/reflaxe.ocaml/README.md`](packages/reflaxe.ocaml/README.md).

## CI glossary (plain English)

- **CI**: fast safety checks on normal changes.
- **Gate 1 Lite**: quick upstream macro smoke.
- **Gate 2 Lite**: quick workload smoke.
- **Gate 3 Builtin**: linked backend smoke (`ocaml-stage3`; optional `js-native` lane on manual runs).
- **Gate 1/2/3**: heavier upstream compatibility gates (weekly/manual).
- **Plugin matrix (strict)**: macro-library compatibility + eval.vm plugin API smoke + Stage3 plugin fixture checks.
- Focused Gate2 display runs on macOS use deterministic retry/skip knobs; see
  [Testing command catalog](docs/01-getting-started/TESTING.md).

## Project layout (monorepo)

- `packages/hxhx`: CLI/product entrypoint.
- `packages/hxhx-core`: compiler core and backend contracts.
- `packages/hxhx-macro-host`: Stage4 macro host process.
- `packages/reflaxe.ocaml`: OCaml backend/runtime package.
- `examples/`: `hxhx`-oriented examples (preset/plugin/compiler wiring).
- `packages/reflaxe.ocaml/examples/`: `reflaxe.ocaml`-oriented examples (still exercised through `hxhx` in this repo).
- `workloads/`: acceptance workloads.

`hxhx` and `reflaxe.ocaml` stay together for now because they still share bootstrap/runtime iteration loops.

## More docs

- [Testing command catalog](docs/01-getting-started/TESTING.md)
- [Self-hosting checklist (beginner-friendly)](docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md)
- [1.0 roadmap (non-expert)](docs/01-getting-started/HXHX_1_0_ROADMAP.md)
- [Acceptance model](docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md)
- [OCaml profile contract (`portable|metal`)](docs/02-user-guide/OCAML_PROFILE_CONTRACT.md)
- [OCaml runtime capability matrix (`portable` vs `metal`)](docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md)
- [Stage0 policy (`runtime/build/maintenance`)](docs/00-project/STAGE0_POLICY.md)
- [Stdlib provenance policy + ledger](docs/00-project/STD_LIB_POLICY.md)
- [Cleanup and cache policy](docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md)
- [Boundaries and long-term repo strategy](docs/00-project/BOUNDARIES.md)
- [Provenance policy (ML2HX non-shipping)](docs/00-project/PROVENANCE_POLICY.md)
- [Public release checklist](docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md)

## License

MIT (see [`LICENSE`](LICENSE)).
