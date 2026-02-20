<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![Compatibility Gate 1 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml)
[![Compatibility Gate 2 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml)
[![Compatibility Gate 3 Builtin](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml)
[![Compatibility Gate 1](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml)
[![Compatibility Gate 2](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml)
[![Compatibility Gate 3](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.9.5-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack targeting Haxe `4.3.7` compatibility.  
It is developed together with `reflaxe.ocaml` so the toolchain can bootstrap and ship native binaries under MIT.

## Why this exists

- Make compiler internals easier to understand and modify.
- Track upstream Haxe `4.3.7` behavior using oracle-driven gates.
- Keep a permissive, embeddable distribution path.
- Compile Reflaxe targets to native binaries for better performance.

## Current status

- Compatibility target is **Haxe `4.3.7`**.
- Per-commit checks run **Gate 1 Lite**, **Gate 2 Lite**, and **Gate 3 Builtin**.
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
  - [Stdlib reuse + provenance boundaries](docs/00-project/STD_LIB_POLICY.md)

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

Optional JS parity smoke (upstream compiler vs `hxhx js-native` runtime behavior):

```bash
npm run test:upstream:js-oracle-smoke
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

## Project layout (monorepo)

- `packages/hxhx`: CLI/product entrypoint.
- `packages/hxhx-core`: compiler core and backend contracts.
- `packages/hxhx-macro-host`: Stage4 macro host process.
- `packages/reflaxe.ocaml`: OCaml backend/runtime package.
- `examples/`: consumer-style examples.
- `workloads/`: acceptance workloads.

`hxhx` and `reflaxe.ocaml` stay together for now because they still share bootstrap/runtime iteration loops.

## More docs

- [Testing command catalog](docs/01-getting-started/TESTING.md)
- [1.0 roadmap (non-expert)](docs/01-getting-started/HXHX_1_0_ROADMAP.md)
- [Acceptance model](docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md)
- [Cleanup and cache policy](docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md)
- [Boundaries and long-term repo strategy](docs/00-project/BOUNDARIES.md)
- [Public release checklist](docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md)

## License

MIT (see [`LICENSE`](LICENSE)).
