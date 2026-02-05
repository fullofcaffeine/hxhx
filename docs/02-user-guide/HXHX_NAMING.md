# `hxhx`: The Haxe-in-Haxe Compiler Name and CLI Surface

This repo’s long-term goal includes a **production-grade Haxe compiler written in Haxe**, compiled to **native OCaml**
via `reflaxe.ocaml`.

We need a name that is:

- easy to type in a shell
- ASCII-only (no Unicode gymnastics for CI/users)
- unambiguous and searchable
- not misleading about Haxe versions (“Haxe 2” already existed historically)

## Decision: `hxhx`

We call the Haxe-in-Haxe compiler:

- **Project name**: `hxhx`
- **Binary name**: `hxhx`

Rationale:

- reads as “Haxe-in-Haxe”
- easy to type and grep
- avoids ambiguous names like `hx2`
- avoids Unicode variants like `hx²`

## Relationship to upstream `haxe`

`hxhx` is not a fork of upstream `haxe`.

Instead:

- upstream `haxe` (the OCaml compiler) remains the **source of truth** for behavior
- `hxhx` aims to become a **drop-in replacement** for a specific compatibility target:
  - initial compatibility target: **Haxe 4.3.7**

“Replacement-ready” is defined by upstream test gates (see `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`).

## Versioning

We distinguish two versions:

- **Compatibility version**: which upstream Haxe version we target (e.g. `4.3.7`)
- **Implementation version**: the version of `hxhx` itself (SemVer)

When implemented, `hxhx --version` should report both.

## Repo layout notes

`hxhx` lives under `packages/hxhx` (it is a real in-repo package/tool, not “just an example”).

We still keep acceptance workloads under `examples/`:

- `examples/hih-workload`: Stage 1 “compiler-shaped workload”
- `examples/hih-compiler`: Stage 2/3 “compiler skeleton”

This split keeps `examples/` focused on *consumers* and keeps `packages/` focused on *reusable buildable units*.
