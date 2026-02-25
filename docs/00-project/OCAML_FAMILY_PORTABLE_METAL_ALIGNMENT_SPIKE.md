# OCaml Family Alignment Spike (`portable|metal`)

## Scope

This spike aligns `hxhx`/`reflaxe.ocaml` with the family profile contract used in sibling compiler repos.

Inputs reviewed:

- Local:
  - `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
  - `packages/hxhx-core/src/backend/OcamlProfile.hx`
  - `packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/RuntimeCopier.hx`
  - `packages/hxhx-core/src/backend/ocaml/MetalProfileVerifier.hx`
- Family references (`../haxe.go/docs`):
  - `portable-canonical-contract.md`
  - `phase2-roadmap.md`
  - `hxrt-selective-runtime.md`

## Executive Summary

- **Already aligned**
  - Two-profile model (`portable`, `metal`) exists and is enforced.
  - `metal` is explicit fail-fast (no implicit fallback), matching family direction.
  - Runtime slicing is treated as orthogonal to profile in behavior (implemented for OCaml via module selection in `RuntimeCopier`).
- **Gaps to close**
  - Runtime slicing inference is currently text-token based and can drift.
  - No machine-readable contract/report artifact is emitted per compile.
  - No canonical “runtime plan” artifact exists for CI visibility and drift detection.
  - Profile parsing is duplicated across layers (`hxhx-core` vs `reflaxe.ocaml` macro side).

## Current State vs Family Contract

### 1) Profile model (`portable|metal`) — **Aligned**

- `OcamlProfile` defines strict accepted values and fail-fast validation:
  - `packages/hxhx-core/src/backend/OcamlProfile.hx`
- `BackendContext.ensureOcamlProfileDefine()` normalizes and persists effective value:
  - `packages/hxhx-core/src/backend/BackendContext.hx`
- Contract documented:
  - `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`

Result: profile admission model matches family requirement to avoid profile proliferation.

### 2) Metal safety/strictness — **Aligned**

- `MetalProfileVerifier` rejects dynamic/reflection/untyped fallback constructs:
  - `packages/hxhx-core/src/backend/ocaml/MetalProfileVerifier.hx`
- Behavior is deterministic and diagnostics are actionable.

Result: metal lane is strict by default, which matches family “no silent semantic drift” policy.

### 3) Runtime slicing orthogonal to profile — **Partially aligned**

- `RuntimeCopier` selects runtime modules differently for metal vs portable:
  - portable: copy all runtime modules
  - metal: select transitive runtime module subset
- Selection is currently inferred by scanning emitted `.ml/.mli` text for module-name tokens:
  - `packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/RuntimeCopier.hx`

Result: orthogonality intent is correct, but inference method is brittle compared to compiler-tracked usage.

### 4) Contract/report visibility — **Gap**

No canonical emitted artifacts today for:

- effective profile contract report
- runtime-plan report (what runtime modules/features were selected, and why)

Result: CI and release checks cannot diff contract/runtime plans directly without parsing logs.

## Key Risks

1. **Token-scan false positives/negatives**  
   Runtime module selection can change due to formatting/name collisions instead of semantic usage.

2. **Cross-layer contract drift**  
   Profile normalization logic exists in both `hxhx-core` and `reflaxe.ocaml` contexts.

3. **Low observability for regressions**  
   Without machine-readable reports, profile/runtime drift appears late in failures or output diffs.

## Hardening Plan

### Phase A — Contract/report plumbing (low risk)

1. Emit `ocaml_profile_report.json` per compile with:
   - requested profile
   - normalized profile
   - verifier mode (`enabled/disabled`)
   - verifier result summary
2. Emit `ocaml_runtime_plan_report.json` with:
   - profile
   - runtime selection mode (`full`, `selective`)
   - selected modules/features
   - rationale fields (inferred/manual/forced)

### Phase B — Runtime inference source of truth

Replace text-token inference with compiler-tracked usage:

1. Add runtime feature/module usage collection during lowering/building.
2. Persist usage into compilation context.
3. Feed runtime plan directly from tracked usage; keep token-scan only as temporary debug fallback.

### Phase C — Family-safe diagnostics policy

Keep **strict fail-fast** for `metal` as default:

- No automatic fallback to `portable`.
- Optional advisory diagnostics can suggest portable migration path.
- If a fallback mode is added for local debugging, it must be explicit and never default.

## Recommended Acceptance Signals

1. Contract report and runtime plan report are generated and deterministic.
2. CI validates reports for a fixed fixture set.
3. Runtime selection no longer depends on free-form text scanning.
4. Metal failure behavior remains explicit fail-fast unless user opts into a non-default debug mode.

## Follow-up Task Set

Tracked as follow-up beads under `haxe.ocaml-8nv`:

- contract/runtime report artifacts
- compiler-tracked runtime usage planner
- profile normalization alignment across `hxhx-core` and `reflaxe.ocaml`
- metal diagnostics/fallback policy hardening

## Re-spike Trigger

After sibling repos stabilize selective runtime + metal diagnostics, run a cross-repo reconciliation spike and refresh this alignment doc.
