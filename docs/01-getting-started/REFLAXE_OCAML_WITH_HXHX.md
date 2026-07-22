# Using `reflaxe.ocaml` with `hxhx`

This guide explains the current status of using `reflaxe.ocaml` through
`hxhx` instead of upstream `haxe`.

Short version:

- use upstream `haxe + reflaxe.ocaml` for the production-candidate OCaml output path today
- use `hxhx + reflaxe.ocaml` when you are validating native `hxhx` compiler behavior, plugin hosting, or promotion infrastructure
- do not treat `hxhx + reflaxe.ocaml` as the default production route until the Full 1.0 gates pass
- do not enable warm Reflaxe compilation-server reuse; see
  `docs/01-getting-started/COMPILATION_SERVER.md` for the current safe workflows

## What is supported today

The supported `hxhx + reflaxe.ocaml` surface today is an experimental validation
surface, not the default production route.

It is useful for:

- proving that `hxhx` can build or load `reflaxe.ocaml`-related native artifacts
- testing non-delegating compiler behavior with upstream-Haxe fallback disabled
- validating the plugin-host and builtin-target packaging shapes
- comparing failures against the upstream `haxe + reflaxe.ocaml` baseline

It is not yet the recommended path for:

- shipping OCaml output from a normal application
- claiming `hxhx` is a full Haxe `4.3.7` replacement
- claiming broad macro/plugin parity for arbitrary user projects
- claiming one native plugin artifact works interchangeably across upstream `haxe` and `hxhx`

## Which path should I choose?

| Need | Choose | Why |
| --- | --- | --- |
| Produce OCaml from Haxe with the least host-compiler risk | upstream `haxe + reflaxe.ocaml` | This is the standalone target-product path under the `reflaxe.ocaml` 1.0 contract. |
| Validate native compiler behavior without upstream-Haxe fallback | strict `hxhx` native lanes | This tests `hxhx` itself, not just the OCaml target. |
| Build or load native Reflaxe backend artifacts for `hxhx` | `hxhx` promotion/plugin workflows | This is the current native host/plugin validation path. |
| Decide whether `hxhx + reflaxe.ocaml` is production-ready for your app | Do not assume readiness yet | The remaining Full 1.0 compiler gates must close first. |

Start with upstream `haxe + reflaxe.ocaml` if your goal is application output.
Switch to `hxhx` only when you explicitly need native compiler validation or
native hosting behavior.

## Current evidence

Evidence that exists:

- standalone upstream `haxe + reflaxe.ocaml` product readiness is tracked by
  `haxe.ocaml-ro10` and documented in
  `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
- the Reflaxe promotion matrix is tracked by `haxe.ocaml-rpmx` and documented in
  `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
- Full 1.0 plugin parity for `reflaxe.ocaml` artifacts inside `hxhx` is tracked
  by `haxe.ocaml-f1cl.8` and documented in
  `docs/00-project/PLUGIN_PARITY_FULL_1_0.md`

Evidence still required before calling `hxhx + reflaxe.ocaml` production-ready:

- strict `hxhx` Haxe `4.3.7` equivalence gates must pass under
  `haxe.ocaml-f1cl`
- upstream-derived Full 1.0 suite and target gates must pass without hidden
  stage0 fallback under `haxe.ocaml-f1cl.3`
- release go/no-go and release-claim enforcement must close under
  `haxe.ocaml-f1cl.6` and `haxe.ocaml-f1cl.7`
- performance parity or better must remain auditable under `haxe.ocaml-f1cl.5`

The closed promotion and plugin proofs are necessary evidence, but they are not
enough by themselves. They prove important host/plugin seams; they do not prove
that `hxhx` is ready to replace upstream Haxe for general `reflaxe.ocaml` users.

## Practical commands

Build the current `hxhx` binary:

```bash
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
"$HXHX_BIN" --version
```

Run a strict native lane with upstream-Haxe fallback disabled:

```bash
HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --ocaml --hxhx-no-emit -cp src -main Main
```

Run the promotion-path evidence when you are working on native hosting:

```bash
npm run test:rpmx:hxhx-plugin
npm run test:rpmx:hxhx-builtin
```

Run the broader replacement-readiness gate only when you need Full 1.0 evidence:

```bash
npm run test:upstream:replacement-ready:strict
```

## Production rule

For a production app today:

- default to upstream `haxe + reflaxe.ocaml`
- keep `hxhx + reflaxe.ocaml` as validation or migration evidence
- cite `hxhx + reflaxe.ocaml` as production-ready only after the Full 1.0 owner beads have current passing evidence

Related docs:

- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
- `docs/01-getting-started/CHOOSE_A_REFLAXE_PROMOTION_PATH.md`
- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/CI_GATES.md`
