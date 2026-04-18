# Full 1.0 Plugin Parity Contract

Last audited: 2026-04-18

This page defines the Full 1.0 plugin parity evidence required for `hxhx`
itself. It is a contract-definition document, not runtime proof by itself.

Success marker for this contract:

- `FULL1_PLUGIN_PARITY_CONTRACT:PASS`

Runtime/evidence marker for the finished plugin parity gate:

- `FULL1_PLUGIN_PARITY:PASS`

## Scope

Full 1.0 plugin parity means `reflaxe.ocaml` backend plugin artifacts can be
built, loaded, and exercised through `hxhx` without hidden stage0 delegation.

The relevant plugin surface is intentionally limited to the Haxe compiler
replacement claim:

- `reflaxe.ocaml` is the blocking Full 1.0 plugin target.
- `hxhx` is the load host for native plugin parity evidence.
- `HXHX_FORBID_STAGE0=1` is required for strict `hxhx` proof lanes.
- `--compat` and other stage0 delegation paths do not count as Full 1.0 plugin
  parity evidence.

## Host/Compiler Matrix

| Matrix row | Build compiler | Load host | Required proof | Marker owner |
| --- | --- | --- | --- | --- |
| upstream Haxe to hxhx | upstream Haxe 4.3.7 | `hxhx` strict plugin host | Build the `reflaxe.ocaml` plugin artifact with upstream Haxe, then load and exercise it in `hxhx` with stage0 forbidden. | `haxe.ocaml-f1cl.8.2` |
| hxhx strict to hxhx | `hxhx` strict, stage0 forbidden | `hxhx` strict plugin host | Build the `reflaxe.ocaml` plugin artifact with `hxhx`, then load and exercise it in `hxhx` without stage0 fallback. | `haxe.ocaml-f1cl.8.3` |
| explicit upstream Haxe host-adapter proof | upstream Haxe 4.3.7 | upstream Haxe eval host adapter boundary | Load the `reflaxe.ocaml` artifact through `eval.vm.Context.loadPlugin` and record the exact upstream compiler that produced the artifact. | `haxe.ocaml-f1cl.8.4` |

## Required Markers

Contract-definition marker:

- `FULL1_PLUGIN_PARITY_CONTRACT:PASS`

Runtime/evidence markers:

- `PLUGIN_MATRIX_STRICT:PASS` remains the Scoped 1.0 plugin smoke marker.
- `REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS` proves the upstream Haxe to
  `hxhx` matrix row.
- `REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS` proves the strict `hxhx` to
  `hxhx` matrix row.
- `REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS` proves the explicit
  upstream Haxe eval host-adapter row through `eval.vm.Context.loadPlugin`.
- `FULL1_PLUGIN_PARITY:PASS` is the Full 1.0 aggregate plugin parity marker.

`FULL1_PLUGIN_PARITY:PASS` must not be emitted until all blocking
`reflaxe.ocaml` matrix rows above have artifact-backed evidence.

## Non-Goals

- `reflaxe.elixir` is example-only and non-blocking for the Full 1.0 plugin
  parity claim in this repository.
- Broader Reflaxe compiler promotion is tracked by the promotion matrix, not by
  this Full 1.0 plugin parity contract.
- A successful `--compat` plugin path is not native `hxhx` plugin parity.
- Placeholder plugin fixtures do not replace `reflaxe.ocaml` artifact evidence.

## Follow-up Proof Beads

- `haxe.ocaml-f1cl.8.2`: Reflaxe.ocaml plugin proof: build via upstream Haxe and load in hxhx.
  - Runnable proof: `npm run test:full1:plugin:upstream-to-hxhx`.
  - Row marker: `REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS`.
- `haxe.ocaml-f1cl.8.3`: Reflaxe.ocaml plugin proof: build via hxhx strict and load in hxhx.
  - Runnable proof: `npm run test:full1:plugin:hxhx-to-hxhx`.
  - Row marker: `REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS`.
- `haxe.ocaml-f1cl.8.4`: Explicit upstream Haxe host-adapter proof for reflaxe.ocaml artifacts.
  - Runnable proof: `npm run test:full1:plugin:upstream-host-adapter`.
  - Row marker: `REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS`.
- `haxe.ocaml-f1cl.8.5`: CI workflow: Gate Full1 plugin parity.
  - Workflow: `.github/workflows/full1-plugin-parity.yml`.
  - Aggregate marker: `FULL1_PLUGIN_PARITY:PASS` only after all three proof rows pass.
