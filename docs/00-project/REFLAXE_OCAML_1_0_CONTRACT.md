# reflaxe.ocaml 1.0 Contract

Last audited: 2026-03-13

This page is the canonical product contract for `reflaxe.ocaml` as a standalone target.

It is deliberately separate from:

- `docs/00-project/FULL_1_0_CONTRACT.md`
  - strict `hxhx` compiler-equivalence claim
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
  - multi-host promotion matrix for Reflaxe compilers

## Goal

`reflaxe.ocaml 1.0` means:

- upstream `haxe 4.3.7` can use `reflaxe.ocaml` as a real OCaml target for the declared scope,
- the target/runtime/stdlib surface needed for that scope is production-credible,
- the install/build/run workflow is documented and reproducible,
- and the claim is backed by explicit evidence instead of repo lore.

This is a target-product claim.
It is not a claim that `hxhx` is already `Full 1.0`.

## Ownership boundary

This contract owns:

- upstream `haxe 4.3.7` + `reflaxe.ocaml` compatibility for the declared scope,
- target-owned stdlib/runtime/lowering closure,
- target-level performance credibility,
- operator-facing docs for installation, use, and troubleshooting.

This contract does not own:

- `hxhx` `Scoped 1.0` or `Full 1.0` compiler claims,
- the broader Reflaxe compiler promotion matrix,
- cross-host plugin ABI policy beyond what `reflaxe.ocaml` itself needs as a target,
- behavior that upstream `haxe 4.3.7` does not support.

## Compatibility baseline

- Host compiler baseline: `Haxe 4.3.7`
- Semantic authority: upstream Haxe `4.3.7`
- Target under contract: `reflaxe.ocaml`
- Packaging mode under contract: `-lib reflaxe.ocaml`

Primary user workflow:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Native-build workflow:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Declared 1.0 scope

The declared `reflaxe.ocaml 1.0` scope includes:

1. Upstream Haxe host usage
   - `haxe 4.3.7` remains the controlling frontend and macro host.

2. OCaml output generation
   - deterministic OCaml project emission through the documented target entrypoint.

3. Dune build integration
   - emitted projects can be built through the documented dune path for the declared profiles.

4. Target-owned runtime and stdlib closure
   - the runtime shims, `_std` overrides, and lowering intrinsics required by the declared compatibility matrix.

5. Production-facing docs
   - users can install, invoke, and troubleshoot the target without relying on internal session history.

## Scope references

This contract relies on these narrower surfaces:

- upstream-use guide:
  - `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- current compatibility summary:
  - `docs/02-user-guide/COMPATIBILITY_MATRIX.md`
- stdlib/runtime closure references:
  - `docs/02-user-guide/STDLIB_COVERAGE_PLAN.md`
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
  - `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`
- profile/build behavior:
  - `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`

## Required evidence

`reflaxe.ocaml 1.0` must be justified by explicit evidence lanes.

Required marker set:

- `RO_HAXE_4_3_7_MATRIX:PASS`
  - upstream `haxe 4.3.7` validation matrix for the declared target scope
- `RO_RUNTIME_STDLIB_CLOSURE:PASS`
  - target-owned stdlib/runtime/lowering closure audit is complete for the declared scope
- `RO_PRODUCTION_DOCS:PASS`
  - operator-facing install/use/troubleshooting docs exist and match reality
- `RO_PRODUCTION_READY:PASS`
  - aggregate marker emitted only when the required product-level inputs are satisfied

Supporting evidence:

- focused repo-local regressions
- portable fixtures
- benchmark snapshots

Supporting evidence is useful for diagnosis and iteration speed, but it does not replace the upstream-host target matrix.

## Production-ready statement

A truthful public statement at this layer looks like:

- `reflaxe.ocaml is production-ready for the declared Haxe 4.3.7 scope`

It must not be shortened into:

- `hxhx is Full 1.0`
- `the whole repo is 1.0`
- `all Reflaxe promotion paths are production-ready`

Those are separate claims with separate contracts.

## Non-goals

These are explicitly out of scope for this contract:

- proving `hxhx` compiler equivalence to upstream Haxe
- proving all Reflaxe compiler promotion paths
- proving every Haxe version beyond `4.3.7`
- sibling-repo-specific semantics that upstream Haxe `4.3.7` does not define
- undocumented host/plugin combinations

## Decision rules

- `upstream Haxe first`
  - upstream `4.3.7` remains the semantics authority
- `target product second`
  - fix target-level gaps before broadening host/promotion claims
- `no hidden scope inflation`
  - if a new requirement belongs to promotion or compiler equivalence, track it under the other contract instead of silently expanding this one
