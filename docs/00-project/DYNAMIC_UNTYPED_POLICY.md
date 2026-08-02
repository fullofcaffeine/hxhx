# Dynamic / Any / Untyped Policy

This repo treats `Dynamic`, `Any`, and `untyped` as restricted escape hatches.

## Rule

- Forbidden by default in compiler/core code.
- Allowed only at explicit runtime boundaries (protocol/JSON/dispatch/host seams).
- Any allowed usage must stay tightly scoped and documented.

## Enforcement

`npm run ci:guards` runs:

- `scripts/ci/no-dynamic-check.js`
- `scripts/ci/bridge-boundary-check.js`
- `scripts/ci/bridge-boundary-check-fixture-test.js`

That guard scans scoped compiler lanes and fails if restricted constructs appear outside allowlisted boundary files.
It explicitly checks typed/generic `Dynamic` and typed/generic `Any` usage, plus `untyped __ocaml__`.

The bridge guard is narrower and more specific. It records the exact approved callers for backend reflection,
backend input recovery, the compiler-driver OCaml hint, and the compiler-server socket helper. Its plain-language
contract and removal conditions live in:

- `docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md`
- `docs/00-project/BOOTSTRAP_BRIDGE_INVENTORY.json`

Adding an allowlisted file is an architecture change, not routine cleanup. Update the owning bead, focused test,
inventory, and exit evidence rather than adding a path only to make CI green.

Raw target injection has an additional OCaml-specific design record:

- `docs/00-project/OCAML_SCOPED_RAW_INJECTION_AUTHORITY.md`

That policy defines the proposed `@:ocamlAllowRaw` authority marker for rare low-level modules. It does not weaken
the default rule here: raw `__ocaml__` remains forbidden by default in app/compiler code and must not bypass the
global metal checks. The removed `@:haxeMetal` annotation is not an authority or optimization mechanism.

## Allowlist categories

### Permanent boundary allowlist

- Compiler-owned metadata JSON parsing boundaries:
  - `packages/hxhx-core/src/hxhx/CompilerJsonParser.hx`
  - `packages/hxhx-core/src/hxhx/CompilerJsonArray.hx`
  - `packages/hxhx-core/src/backend/plugin/BackendPluginManifestParser.hx`
  - `packages/hxhx-core/src/hxhxmacrohost/NativeMacroModuleReceipt.hx`
- Backend dispatch boundaries:
  - `packages/hxhx-core/src/backend/BackendDispatchBoundary.hx`
  - `packages/hxhx-core/src/backend/GenIrBoundary.hx`
- Native plugin/macro host boundary seams:
  - `packages/hxhx/src/hxhx/Stage3Compiler.hx`
  - `packages/hxhx/src/hxhx/BackendPluginManifestResolver.hx`
  - `packages/hxhx-macro-host/src/hxhxmacrohost/**`

### Temporary migration allowlist

There is currently no temporary migration allowlist entry in `scripts/ci/no-dynamic-check.js`.
Previously-allowlisted emitter seams were moved to typed map/context helpers.

## Contributor guidance

- Do not spread `Dynamic`/`Any` through internal APIs.
- If you need a boundary exception, add it in one file at the seam and document why.
- Prefer typed adapters that immediately convert boundary values into concrete types.
- Do not hand-edit generated bootstrap `.ml` snapshots to change a bridge. Change the owning Haxe or hand-written
  runtime source and regenerate through the documented build path.
