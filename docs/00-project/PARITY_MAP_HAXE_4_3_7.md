# Haxe 4.3.7 Parity Map

Last audited: 2026-03-03

This map defines the current parity surface in one place so replacement-readiness claims are measurable and machine-searchable.

Scope manifests used by this map:

- Oracle/scoped scope: `docs/02-user-guide/compat/scoped-1.0-targets.json`
- Native strict scope: `docs/02-user-guide/compat/native-scope-targets.json`

## Surface Matrix (Suites x Lanes x Targets x Profiles x Markers)

| Surface ID | Suite / workload | Lane | Targets | Profile | CI lane / command | Pass signal (machine-searchable) |
| --- | --- | --- | --- | --- | --- | --- |
| PM-01 | Upstream unit macro smoke (`tests/unit` macro subset) | Native Stage3 smoke (no-emit) | `Macro` | `n/a` | `.github/workflows/gate1-lite.yml` (`npm run test:upstream:unit-macro-stage3-no-emit`) | `GATE1_LITE:PASS` |
| PM-02 | Upstream unit macro compatibility (`tests/unit` macro) | Oracle compatibility | `Macro` | `n/a` | `.github/workflows/gate1.yml` and M7 full bundle (`npm run test:upstream:replacement-ready:full`) | `GATE1_MACRO:PASS` |
| PM-03 | Upstream runci macro smoke (`tests/runci` macro fast profile) | Oracle compatibility smoke | `Macro` | `n/a` | `.github/workflows/gate2-lite.yml` (`npm run test:upstream:runci-macro-stage3-no-emit`) | `GATE2_LITE:PASS` |
| PM-04 | Upstream runci macro compatibility (`tests/runci` macro stage) | Oracle compatibility | `Macro` | `n/a` | `.github/workflows/gate2.yml` and M7 full bundle (`npm run test:upstream:replacement-ready:full`) | `GATE2_MACRO:PASS` |
| PM-05 | Upstream runci target matrix (`tests/runci/targets`) | Oracle compatibility | `Macro,Js,Neko` (from scope manifests unless overridden) | `n/a` | `.github/workflows/gate3.yml` and M7 full bundle (`npm run test:upstream:replacement-ready:full`) | `GATE3_TARGETS:PASS` |
| PM-06 | Stage0-forbidden OCaml smoke | Native | `ocaml` | `portable` (default) | `.github/workflows/ci.yml` job `stage0-free-smoke` | `STAGE0_FREE_SMOKE:PASS` |
| PM-07 | Native JS emit+run smoke (+ JS oracle subset in same job) | Native | `js` | `n/a` | `.github/workflows/ci.yml` job `js-native-smoke` | `JS_NATIVE_SMOKE:PASS` |
| PM-08 | Plugin strict matrix (+ auditable native plugin happy path) | Native plugin lane | provider / plugin matrix | `n/a` | `.github/workflows/ci.yml` job `plugin-matrix` | `PLUGIN_MATRIX_STRICT:PASS` |
| PM-09 | Builtin target smoke (ocaml+js) for replacement bundle | Native builtin lane | `ocaml,js` | `portable` (default for OCaml) | `scripts/hxhx/run-replacement-ready.sh` (`npm run test:upstream:replacement-ready:full`) | `BUILTIN_TARGET_SMOKE:PASS` |
| PM-10 | Strict stage0-forbidden bundle gate | Native strict replacement scope | `Macro,Js,Neko` + native compile lanes `ocaml,js` | strict M7 (`HXHX_M7_STRICT=1`) | `.github/workflows/gate-m7.yml` / `npm run test:upstream:replacement-ready:strict` | `M7_STRICT_STAGE0:PASS` |
| PM-11 | Replacement-ready bundle gate (scoped 1.0) | Oracle replacement scope | scope-defined (`Macro,Js,Neko`; policy includes native lanes `ocaml`,`js` plus delegated compat lanes `ocaml-eval`,`compat`) | M7 full profile | `.github/workflows/gate-m7.yml` / `npm run test:upstream:replacement-ready` | `M7_REPLACEMENT_READY:PASS` |
| PM-12 | Stdlib semantic-diff scoped PR canary / nightly expanded | Portable oracle diff lane | generated stdlib-focused programs | `portable` | `.github/workflows/semantic-diff.yml` jobs `Semantic diff (PR smoke)` and `Semantic diff (nightly expanded)` | `SEMANTIC_DIFF_LITE_SCOPE:RUN` or `SEMANTIC_DIFF_LITE_SCOPE:SKIP_NO_RELEVANT_CHANGES` (PR scope), `SEMANTIC_DIFF_LITE:PASS` (when scoped run executes), `SEMANTIC_DIFF_NIGHTLY:PASS` (nightly) |

## Marker Registry

These are the canonical marker strings used for parity statements in logs:

- `GATE1_LITE:PASS`
- `GATE2_LITE:PASS`
- `STAGE0_FREE_SMOKE:PASS`
- `JS_NATIVE_SMOKE:PASS`
- `PLUGIN_MATRIX_STRICT:PASS`
- `GATE1_MACRO:PASS`
- `GATE2_MACRO:PASS`
- `GATE3_TARGETS:PASS`
- `BUILTIN_TARGET_SMOKE:PASS`
- `M7_STRICT_STAGE0:PASS`
- `M7_REPLACEMENT_READY:PASS`
- `SEMANTIC_DIFF_LITE_SCOPE:RUN`
- `SEMANTIC_DIFF_LITE_SCOPE:SKIP_NO_RELEVANT_CHANGES`
- `SEMANTIC_DIFF_LITE:PASS`
- `SEMANTIC_DIFF_NIGHTLY:PASS`

## Claim Rules

- Use `M7_REPLACEMENT_READY:PASS` for scoped oracle replacement-readiness statements.
- Use both `M7_STRICT_STAGE0:PASS` and `M7_REPLACEMENT_READY:PASS` for stage0-forbidden/native replacement statements.
- For semantic-diff-lite PR canary claims, include scope marker (`RUN` or `SKIP`), pass marker when present, and `semantic-diff-pr-artifacts`.
