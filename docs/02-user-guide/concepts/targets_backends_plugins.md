# Targets, Backends, and Plugins

This page explains how target selection maps to backend execution.

## Core concepts

- **Target preset**: CLI-level selector (`--target ...`) that chooses a run plan.
- **Backend**: code generator implementation that emits artifacts.
- **Builtin backend**: backend compiled into `hxhx`.
- **Backend plugin**: backend loaded at runtime from native OCaml dynlink artifact (`.cmxs` / `.cma`) via manifest.

## Builtin vs plugin backend

| Mode | What it means | Best for | Tradeoff |
| --- | --- | --- | --- |
| Builtin backend | Shipped in the `hxhx` binary | Stable out-of-box usage | Requires release integration |
| Backend plugin | Runtime-loaded native artifact | Fast iteration and external backends | ABI/toolchain coupling |

## Promotion (Reflaxe to native)

Native promotion means taking Reflaxe backend logic and packaging it into a native artifact that `hxhx` can load.

Current conceptual lanes:

1. **Native macro module lane**: native macro-host acceleration path.
2. **Native backend plugin lane**: runtime-loaded backend provider path.

See:
- `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`

## Important beginner note

If you only need to compile code today, start with `docs/01-getting-started/START_HERE.md`.
This page is for understanding architecture and extension points.
