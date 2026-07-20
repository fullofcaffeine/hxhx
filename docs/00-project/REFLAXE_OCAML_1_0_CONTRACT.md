# reflaxe.ocaml 1.0 Contract

Last audited: 2026-07-19

This page is the canonical product contract for `reflaxe.ocaml` as a standalone target.

Current release authorization: **no-go**. The existing
`RO_PRODUCTION_READY:PASS` aggregate proves the historical declared
example/package/performance bundle. Following the accepted native-power and
target-lowering review, it is necessary but not sufficient for a 1.0 release:
`haxe_ocaml-9v1va` must establish the first validated place/evaluation lowering
slice, `haxe_ocaml-0uwin` must make runtime requirements fail closed, and this
aggregate must then open that semantic-safety evidence. Existing package,
matrix, documentation, and performance receipts remain valid within their
recorded scope; they are not revoked or silently reinterpreted.

Accepted architecture checkpoint:

- `docs/00-project/ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`
- `docs/00-project/ORACLE_CHECKPOINT_FEATURE_GATED_TYPED_BODY_LIFECYCLE_2026_07_19.md`

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
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
    - `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.json`
- `RO_RUNTIME_STDLIB_CLOSURE:PASS`
  - target-owned stdlib/runtime/lowering closure audit is complete for the declared scope
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`
    - `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.json`
- `RO_TARGET_PERF_CREDIBLE:PASS`
  - target-level performance evidence exists for upstream `haxe 4.3.7 + reflaxe.ocaml`
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
    - `docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json`
- `RO_TARGET_ITERATION_REPORT:PASS`
  - a copied standalone project completed the declared cold-output,
    unchanged-warm, and one-file-change method without mutating tracked source
  - timings remain report-only until stable hosted trends justify a reviewed
    threshold; this marker proves method and behavior, not a speed budget
- `RO_PRODUCTION_DOCS:PASS`
  - operator-facing install/use/troubleshooting docs exist and match reality
  - source of truth:
    - `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
- `RO_PRODUCTION_READY:PASS`
  - current aggregate marker for the historical declared product-level inputs;
    it does not authorize 1.0 until it also opens the semantic-safety
    prerequisites below
  - local evidence command:
    - `npm run test:reflaxe-ocaml:production-ready`

Required semantic-safety prerequisites before release authorization:

- an upstream-Haxe-oracle-backed place/evaluation/assignment slice is sealed
  before target syntax, including explicit occurrence counts and deterministic
  unsupported diagnostics (`haxe_ocaml-9v1va`);
- runtime requests fail for unknown, missing, stale, modified, or
  profile-illegal sources, and admitted selective requirements have a semantic
  reason plus checked closure (`haxe_ocaml-0uwin`);
- the aggregate checker and retained release receipt open those results rather
  than relying only on the historical example inventory.

These prerequisites do not make the full future native-power roadmap a 1.0
blocker. Generated bindings, advanced adapters, curated exported libraries,
and one upstream-Haxe/`hxhx` target core block only a public scope that claims
those capabilities.

Supporting evidence:

- `RO_TARGET_PERF_PLATFORM:PASS`
  - one host measured the exact installed source ZIP outside the checkout with
    complete raw samples and verified runtime output
  - this is an input receipt, not a cross-platform result by itself
- `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`
  - one clean source ZIP is installed and measured on Linux and macOS with the
    canonical six clean-build scenarios plus the standalone authoring-iteration
    workload, complete raw samples, verified behavior, host/toolchain metadata,
    and an aggregate that opens both receipts
  - source of truth:
    - `.github/workflows/reflaxe-ocaml-package-matrix.yml`
    - `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
  - results are per host; this marker does not authorize cross-host absolute
    timing comparisons or replace `hxhx` compiler/plugin performance evidence
- `RO_PACKAGE_ARTIFACT_MATRIX:PASS`
  - one clean CI producer builds the deterministic source ZIP and Linux plus
    macOS consumers install, compile, build, and run that exact artifact
  - source of truth:
    - `.github/workflows/reflaxe-ocaml-package-matrix.yml`
  - this is verified-host evidence, not a blanket operating-system support
    declaration; Windows remains unclaimed until it has its own clean proof
- `RO_PACKAGE_INSTALL_SMOKE:PASS`
  - a deterministic, source-only ZIP installs into a disposable haxelib
    repository and builds/runs an external application with stock Haxe 4.3.7
  - local evidence command:
    - `npm run test:reflaxe-ocaml:package-install`
  - this marker is platform/toolchain-specific until the release owner retains
    the declared support matrix
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
- `semantic safety before plausible output`
  - behavior inside the declared scope has one validated owner before OCaml
    syntax, and unsupported behavior fails at the Haxe source boundary rather
    than becoming unit, null, `Dynamic`, raw source, or an unsafe cast
- `evidence aggregate is not release authority by name alone`
  - a historical `RO_PRODUCTION_READY:PASS` receipt remains bounded to the
    inputs it opened; release authorization waits for every current required
    prerequisite in this contract
