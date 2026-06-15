# Dynamic / Any / Untyped Policy

This repo treats `Dynamic`, `Any`, and `untyped` as restricted escape hatches.

## Rule

- Forbidden by default in compiler/core code.
- Allowed only at explicit runtime boundaries (protocol/JSON/dispatch/host seams).
- Any allowed usage must stay tightly scoped and documented.

## Enforcement

`npm run ci:guards` runs:

- `scripts/ci/no-dynamic-check.js`

That guard scans scoped compiler lanes and fails if restricted constructs appear outside allowlisted boundary files.
It explicitly checks typed/generic `Dynamic` and typed/generic `Any` usage, plus `untyped __ocaml__`.

Raw target injection has an additional OCaml-specific design record:

- `docs/00-project/OCAML_SCOPED_RAW_INJECTION_AUTHORITY.md`

That policy defines the proposed `@:ocamlAllowRaw` authority marker for rare low-level modules. It does not weaken
the default rule here: raw `__ocaml__` remains forbidden by default in app/compiler code and must not bypass metal or
`@:haxeMetal` checks.

## Allowlist categories

### Permanent boundary allowlist

- Plugin manifest JSON parsing boundaries:
  - `packages/hxhx-core/src/backend/plugin/ManifestJsonParser.hx`
  - `packages/hxhx-core/src/backend/plugin/ManifestJsonArray.hx`
  - `packages/hxhx-core/src/backend/plugin/BackendPluginManifestParser.hx`
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
