# hxhx Customization And Variation Architecture

Last prepared: 2026-07-04
Status: architecture design for `haxe.ocaml-vary.4`; no production-readiness claim

Related beads:

- `haxe.ocaml-vary` - modular `hxhx` customization and Haxe-family variation architecture
- `haxe.ocaml-vary.5` - minimal pluggable customization proof
- `haxe.ocaml-vary.6` - documented Haxe-family variation workflow
- `haxe.ocaml-f1cl` - strict Full 1.0 Haxe `4.3.7` baseline claim
- `haxe.ocaml-rpmx` - Reflaxe compiler promotion matrix

## Purpose

This document defines how `hxhx` can become easy to customize without making
the stock compiler ambiguous.

The core rule is:

> Baseline `hxhx` remains Haxe `4.3.7`-compatible by default. Any behavior that
> bends Haxe must be explicitly activated, removable, auditable, and excluded
> from baseline release evidence unless the baseline contract is deliberately
> changed.

This design builds on the accepted Reflaxe boundary:

- `hxhx` is authored as ordinary Haxe compiler code.
- `reflaxe.ocaml` is a native compilation/bootstrap route for those Haxe
  sources.
- Reflaxe-style APIs are valid at target/backend/plugin seams.
- Reflaxe does not own parser, resolver, typer, module graph, diagnostics, or
  macro lifecycle semantics in the baseline compiler.

The accepted boundary is recorded in
[`ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`](ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md).

## Definitions

### Baseline compiler

The default `hxhx` product. It must preserve the declared Haxe `4.3.7`
compatibility contract and is the only product covered by Full 1.0 baseline
release claims.

### Plugin/customization

An explicitly enabled extension that runs through a versioned compiler seam and
can be disabled without changing baseline behavior. A customization may add
diagnostics, policies, target support, code generation behavior for a selected
target, or macro/hook behavior that fits the upstream-compatible macro model.

### Variation

A deliberate Haxe-family compiler product, profile, or dialect that may differ
from baseline Haxe semantics. A variation can reuse most of `hxhx`, but it owns
its differences and cannot borrow baseline Haxe `4.3.7` equivalence claims.

### Research seam

A quarantined experiment that may explore deeper compiler-core changes, such as
parser or typer variation, but is not on the baseline release path until a
separate decision proves the lifecycle, parity, provenance, and performance
risk.

## Supported Extension Classes

### 1. Upstream-compatible macro and hook plugins

This is the Haxe-compatible plugin surface:

- CLI macros such as `--macro ...`
- build macros such as `@:build` / `@:autoBuild`
- hook APIs such as `Context.onAfterTyping` and `Context.onGenerate`

These belong to Stage4. They may affect user compilation in the same way
upstream Haxe macros do, but they do not redefine the compiler core contract.

Rules:

- Stage3 still owns parse/resolve/type orchestration.
- Stage4 owns macro execution and hook dispatch.
- Library macro initialization must be deterministic and gated by the native
  macro-host maturity documented in
  [`HXHX_STAGE4_MACROS_AND_PLUGIN_ABI.md`](../02-user-guide/HXHX_STAGE4_MACROS_AND_PLUGIN_ABI.md).
- Baseline parity evidence must distinguish native macro-host behavior from
  stage0/delegated behavior.

### 2. Backend and target plugins

This is the target-promotion surface:

- `IBackend`
- `ITargetCore`
- `TargetCoreBackend`
- `BackendRegistry`
- `BackendAbi`
- `ReflaxeTargetAdapter`

Backend plugins consume `GenIrProgram` or a future concrete GenIR projection
after `hxhx` has parsed, resolved, typed, and established the compiler
contract.

Rules:

- Backends do not own name lookup, typing, macro semantics, or diagnostics.
- Builtin and plugin wrappers for the same target core must be activation
  choices, not behavior forks.
- ABI, GenIR, macro API, host capability, implementation ID, and manifest-kind
  mismatches fail before backend execution.
- Reflaxe-style APIs are welcome here because this seam already sits after
  compiler-core ownership.

### 3. Policy and diagnostic customizations

This is the first hxhx-specific customization class to prove. It should be
lower risk than language-dialect work because it can operate on compiler-owned
data after parsing or typing.

Examples:

- an extra project policy diagnostic,
- a forbidden API check,
- a report-only compile audit,
- a target/package activation policy,
- a stricter release-profile check.

Rules:

- Disabled mode must be byte-for-byte or behavior-equivalent with the baseline
  fixture for the tested surface.
- Activation must be explicit through a flag, manifest, or named profile.
- The customization must declare whether it is read-only, diagnostic-only, or
  behavior-changing.
- Full 1.0 baseline lanes must run with hxhx-specific customizations disabled
  unless the lane explicitly proves a customization product.

### 4. Selected compiler variations

A variation is for cases where a plugin is not enough. It may bundle policies,
targets, stdlib choices, or eventually language-level differences.

Rules:

- A variation has an explicit ID and selection mechanism.
- A variation has its own compatibility statement and tests.
- Baseline `hxhx` remains the default selection.
- A variation cannot silently change baseline Full 1.0 evidence.
- Any frontend or typer difference must be represented as a named variation
  decision, not a hidden condition in shared code.

### 5. Research-only compiler-core framework changes

Deeper Reflaxe-shaped compiler-core work is possible as research, but it is not
the default architecture.

Research-only examples:

- Reflaxe framework APIs owning typed-AST production,
- target activation participating in parser/resolver/typer semantics,
- macro/plugin initialization changing core phase ordering,
- a non-Haxe frontend framework wrapped around `hxhx` core phases.

Rules:

- Keep the experiment outside baseline release lanes.
- Require a dedicated bead, design review, and validation plan.
- Prove stage0-free behavior where the claim requires it.
- Do not import Reflaxe framework APIs into parser/resolver/typer/diagnostic
  ownership code without an explicit experimental marker.

## Activation Model

Every non-baseline behavior needs an activation record. The exact file format is
future work, but the compiler should treat the record as if it contains:

- stable customization or variation ID,
- version,
- owner/package,
- declared hook points,
- declared behavior class: `diagnostic`, `policy`, `backend`, `macro`,
  `variation`, or `research`,
- baseline impact: `none`, `diagnostic-only`, `selected-target-only`, or
  `changes-language-semantics`,
- required ABI and host capabilities,
- release-claim policy.

Activation must be:

- explicit: never inferred merely from classpath presence,
- deterministic: precedence and duplicate IDs are fail-fast,
- inspectable: CI can report which customizations were active,
- reversible: disabling the activation returns to baseline behavior.

## Hook Placement

Allowed baseline-compatible hook placements:

| Placement | Owner | Allowed for baseline plugins? |
| --- | --- | --- |
| CLI/library macro initialization | Stage4 macro host | Yes, once native macro parity supports the surface |
| Build macro expansion | Stage4 macro host | Yes, under upstream-compatible macro semantics |
| After typing / on generate hooks | Stage4 macro host | Yes |
| Backend selection and emission | Backend registry / target core | Yes |
| Post-typing diagnostic policy | hxhx customization seam | Yes, if explicit and disabled in baseline parity lanes |

Variation-only hook placements:

| Placement | Why variation-only |
| --- | --- |
| Parser grammar changes | Changes the accepted language |
| Resolver/name lookup changes | Changes baseline Haxe semantics |
| Typer/unification changes | Changes baseline Haxe semantics |
| Macro lifecycle ordering changes | Changes plugin/macro compatibility |
| Diagnostic severity rewrites that alter success/failure | Changes release evidence |

## Release Claim Rules

Baseline claims:

- The default `hxhx` binary/profile must remain Haxe `4.3.7`-compatible.
- Full 1.0 gates must record that variation/customization behavior is disabled
  unless a gate is explicitly testing customization infrastructure.
- Stage0 fallback cannot count for strict native evidence.

Customization claims:

- A customization can claim only the behavior it proves.
- Diagnostic-only customizations must not be described as compiler forks.
- Backend customizations must prove activation parity when also available as
  builtins.

Variation claims:

- A variation has its own name, version, compatibility statement, and gates.
- A variation may be "Haxe-family", but it is not the baseline Haxe `4.3.7`
  replacement claim.
- README/North Star progress bars move only when user-facing readiness changes,
  not when a design note or internal spike lands.

## Provenance Rules

Customization and variation work follows the same clean-room policy as the rest
of the compiler:

- Upstream Haxe is a behavior oracle, not source to copy or translate.
- Do not vendor upstream compiler tests or fixtures.
- Use repo-owned fixtures and black-box oracle runs.
- Keep behavior differences documented at the product/profile level.

This is especially important for variations. A dialect or fork can make
intentional choices, but those choices must not become an excuse to import
upstream compiler implementation code or to weaken the baseline provenance
contract.

## Minimal Proof Plan

The first proof avoids parser/typer semantics. It uses an explicit Stage3 flag:

```bash
--hxhx-customization report-typed-summary
```

`report-typed-summary` is diagnostic-only. It consumes counters Stage3 already
computed in `--hxhx-type-only` or `--hxhx-no-emit` mode and prints a deterministic
report. It must not mutate parsed modules, typed modules, macro state, backend
registrations, or compiler configuration.

1. Compile a fixture with customization disabled and record the baseline output.
2. Compile the same fixture with a named customization enabled.
3. Assert deterministic enabled behavior, such as one extra diagnostic/report
   or a stricter policy failure.
4. Assert disabling the customization restores the baseline result.
5. Assert Full 1.0 baseline guards do not enable the customization by accident.

That proof is tracked by `haxe.ocaml-vary.5`.

The first variation workflow should remain documentation-first:

1. Explain when a plugin/customization is enough.
2. Explain when a deliberate Haxe-family variation is appropriate.
3. Require a variation ID, compatibility statement, tests, and release-claim
   separation.
4. Link to the baseline Full 1.0 and provenance policies.

That workflow is tracked by `haxe.ocaml-vary.6`.

## CI And Policy Tripwires

Existing tripwires already enforce important parts of this design:

- `scripts/ci/reflaxe-hxhx-core-boundary-check.js` keeps Reflaxe framework APIs
  out of hxhx compiler-core ownership files.
- Backend ABI and provider-boundary guards keep backend activation explicit and
  fail-fast.
- Full 1.0 release enforcement keeps baseline claims gated by the documented
  markers.

Future tripwires should be added with the proof implementation, not invented in
advance without an API:

- a guard that reports active customizations/variations in strict baseline lanes,
- a guard that fails if a variation-only hook is used by the baseline profile,
- a manifest/schema check for duplicate customization IDs and unsupported hook
  points.

No new CI script is required by this design note alone because the public API is
not implemented yet. The follow-up proof must add the relevant guard once the
activation surface exists.

## Non-Goals

This design does not:

- make customization a supported user platform today,
- change README progress bars,
- close Full 1.0 parity work,
- allow target plugins to redefine frontend semantics,
- make Reflaxe the compiler-core framework for `hxhx`,
- create backward-compatibility obligations for pre-1.0 experimental APIs.

## Summary

The architecture is a tiered model:

1. Keep baseline `hxhx` ordinary Haxe-authored and Haxe `4.3.7`-compatible by
   default.
2. Use Stage4 for upstream-compatible macro/hook plugins.
3. Use backend/target-core seams for target plugins and Reflaxe promotion.
4. Add hxhx-specific customizations only through explicit, inspectable,
   disabled-by-default activation.
5. Treat full Haxe-family variations as separate selected products with their
   own claims and gates.
6. Keep deeper compiler-core framework changes quarantined as research unless a
   dedicated architecture decision promotes them.
