# Oracle Checkpoint: Reflaxe Framework Boundary For hxhx

Last prepared: 2026-07-03
Status: reviewed and accepted on 2026-07-03

Related beads:

- `haxe.ocaml-vary` — modular `hxhx` customization and Haxe-family variation architecture
- `haxe.ocaml-rpmx` — Reflaxe compiler promotion matrix via `reflaxe.ocaml`
- `haxe.ocaml-f1cl` — strict Full 1.0 `hxhx` parity and release evidence

## Purpose

Clarify whether the Reflaxe framework should ever be used as the architecture
for creating the `hxhx` compiler itself, or whether it should remain at the
native-compilation, backend, plugin, and target-authoring seams.

This is an architecture review record. The requested output was a seam
recommendation, tradeoff analysis, invariants, and a validation plan, not
implementation code.

## Current Working Hypothesis

There are three distinct meanings of "use Reflaxe for `hxhx`":

1. Compile ordinary Haxe-authored `hxhx` sources through `reflaxe.ocaml` into
   native artifacts. This is strategically important and should remain in scope.
2. Host or implement `hxhx` target backends/plugins with Reflaxe-style APIs.
   This is a natural extension point when it preserves the baseline Haxe
   compiler contract.
3. Build the `hxhx` compiler core itself around the Reflaxe framework. This is
   possible as research, but it is not the default architecture because Reflaxe
   normally assumes a compiler has already parsed, typed, and exposed the Haxe
   AST.

The current local recommendation is: create native `hxhx` artifacts with
Reflaxe, and use Reflaxe for target/backend/plugin seams, but keep the compiler
core authored as ordinary Haxe unless a dedicated design proves the deeper
coupling is worth it.

## Oracle Review Result

Oracle accepted the local hypothesis with one refinement: Reflaxe should be a
first-class native-artifact and backend/plugin seam, but not the default
architecture of the `hxhx` compiler core.

Accepted boundary:

- `hxhx` remains an ordinary Haxe-authored compiler core.
- `reflaxe.ocaml` compiles those Haxe-authored sources into native artifacts.
- Reflaxe-style APIs are valid at target/backend/plugin promotion seams.
- Reflaxe does not own parser, resolver, typer, macro lifecycle, module graph,
  diagnostics, or core compiler phase semantics unless a quarantined research
  bead proves that deeper coupling is worth the circularity.

Operational follow-ups accepted from the review:

- Keep Stage3 ownership over parse/resolve/type/backend orchestration.
- Keep Stage4 ownership over macro execution and plugin ABI.
- Keep backend/plugin activation explicit, versioned, and fail-fast.
- Keep backends consuming `GenIrProgram` or a future concrete GenIR boundary,
  not arbitrary parser/typer internals.
- Add a CI tripwire so parser/resolver/typer/core diagnostic ownership files do
  not import Reflaxe framework APIs by accident.

## Review Prompt

Please review the whole repository architecture at a design level and answer
this boundary question:

Should `hxhx`, the Haxe-in-Haxe compiler, remain an ordinary Haxe-authored
compiler core that uses `reflaxe.ocaml` as a native compilation/bootstrap route,
or should the project consider using the Reflaxe framework itself as a deeper
architecture for creating the `hxhx` compiler?

Please distinguish these candidate layers:

- native artifact route: compiling ordinary Haxe-authored `hxhx` sources
  through `reflaxe.ocaml`,
- backend/plugin route: using Reflaxe-style APIs for `hxhx` target backends,
  compiler plugins, and promoted target artifacts,
- compiler-core route: making parser, typer, macro execution, module
  resolution, diagnostics, or core compiler phase ownership depend on Reflaxe
  framework abstractions.

Constraints:

- Preserve Haxe 4.3.7 baseline parity for `hxhx`.
- Preserve MIT/clean-room provenance. Do not recommend copying, translating, or
  mechanically rewriting upstream Haxe compiler code.
- Treat upstream Haxe as behavior oracle only.
- Do not provide implementation code for direct transcription.
- Optimize for a compiler that remains readable and hackable by Haxe
  developers.
- Keep native performance as a product goal: generated artifacts should be
  measured against delegated/stage0 loops and direct OCaml/native baselines
  where meaningful.

Please answer with:

1. Recommended boundary: which Reflaxe usage levels should be default,
   experimental, or out of scope.
2. Pros and cons of deeper Reflaxe-framework coupling for `hxhx`.
3. Bootstrap and circularity risks, especially around typed AST ownership,
   macro/plugin lifecycle, and target activation.
4. Invariants the repo should enforce if it keeps `hxhx` core ordinary Haxe but
   uses Reflaxe for native artifacts and backend/plugin seams.
5. A minimal validation experiment, if any, that could test deeper Reflaxe
   coupling without corrupting the baseline compiler contract.
6. Documentation or bead updates that should follow from the recommendation.

## Local Review Notes Before Oracle

The main risk in deeper coupling is architectural circularity: Reflaxe is most
useful after a Haxe compiler has produced typed program information, while
`hxhx` must itself own parsing, typing, macro execution, module resolution, and
diagnostics. A full Reflaxe-shaped compiler core might make the compiler easier
to emit natively, but harder to reason about as a faithful Haxe compiler.

The main opportunity is dogfooding: if `hxhx` can compile itself through
`reflaxe.ocaml`, and can host Reflaxe-authored backends/plugins natively, then
Haxe developers get an approachable compiler-authoring loop without rewriting
compiler logic in OCaml.
