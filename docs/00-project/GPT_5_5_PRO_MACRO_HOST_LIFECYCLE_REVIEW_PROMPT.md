# GPT-5.5 Pro External Macro-Host Lifecycle Review Prompt

Prepared: 2026-07-13

Repository baseline: `fullofcaffeine/hxhx` commit `d66dd26d006cbadef542df451b21f848758d0749`

Owning bead: `haxe_ocaml-vhk47.1`

Parent Full1 macro/eval bead: `haxe_ocaml-vhk47`

Status: architecture review request, not an implementation decision

Give this file to GPT-5.5 Pro together with the focused repository bundle described near the end. This file is the controlling prompt.

## Read this first: the problem in plain language

`hxhx` can run Haxe macros in two ways:

- **in-process**: the macro runs inside `hxhx`;
- **external host**: `hxhx` starts a separate `hxhx-macro-host` program and talks to it.

The in-process weekly checks pass. The external-host checks currently do not have one clearly owned host program to reuse across the job.

The unit-macro runner can build a special host on demand, but that build is private to one compiler process. The next runner cannot see or reuse it. If on-demand building is enabled while stage0 is disabled, compiling the host can itself ask for another host and recurse.

A new local probe found a simpler possible seam: build the committed generic macro-host snapshot once, with stage0 forbidden, then give that same executable to the unit, runci, and display checks. All three checks passed locally with that one host.

We need an independent architecture review before implementing this because a locally passing workflow shortcut is not enough. The design must also be honest for Full1, safe for real project macros, non-recursive, candidate-bound, and understandable to maintainers who are new to compiler development.

## Your role

Act as an independent principal compiler architect and release-evidence reviewer. Inspect the uploaded code and contracts, challenge the local interpretation, and recommend the smallest sound lifecycle for the external macro host.

This is a design review. Do not write implementation code for direct transcription. Return a seam recommendation, invariants, tradeoffs, migration slices, and a validation plan.

Explain the result in teaching-oriented language. Define specialist terms when first used and distinguish:

- the compiler process (`hxhx`);
- the reusable macro-host executable;
- project-specific macro code;
- a macro-host process/session started for one compilation;
- a build artifact reused across several CI steps;
- stage0 maintenance from stage0-free runtime evidence.

## Decision requested

Recommend exactly who should build or obtain the external macro-host executable, when it should happen, how later compiler invocations find it, and how recursion becomes impossible.

The preferred result has these properties:

1. one candidate-bound host artifact is prepared before the external-host workload starts;
2. unit, runci, and display checks reuse that artifact;
3. individual `hxhx` compiler processes may start fresh host **processes**, but they do not rebuild the host **artifact**;
4. Full1 evidence does not invoke or silently fall back to upstream `haxe` for correctness;
5. project-specific macro modules have a credible route that does not require recompiling the entire generic host for every compiler invocation;
6. the in-process mode remains an independent comparison lane;
7. missing, stale, cross-commit, incompatible, or recursively requested hosts fail clearly.

If one of these properties is wrong, say so and replace it with a better invariant.

## Non-negotiable project constraints

- Upstream Haxe 4.3.7 is the behavior oracle, not an implementation donor.
- Do not propose copying, translating, mechanically rewriting, or retyping upstream Haxe compiler source.
- Do not propose vendoring upstream Haxe tests or fixtures. The repo runs them from an ignored checkout and writes its own focused regressions.
- Shipping code and inbound dependencies must remain MIT-compatible.
- Full1 runtime correctness must be stage0-free. Stage0 may remain an explicit maintenance tool for refreshing committed bootstrap snapshots.
- A focused smoke or synthetic fixture does not replace upstream-suite evidence.
- Generated OCaml under `bootstrap_out/**` is a committed build input/evidence artifact. The Haxe source is the hand-written architecture.
- Do not solve this by weakening the external-host checks, removing required markers, silently switching them to in-process mode, or treating a cancelled/skipped run as success.
- Keep ordinary parser, resolver, typer, diagnostics, typed-AST, and macro lifecycle ownership in `hxhx`; do not move the compiler core into Reflaxe APIs by default.
- Prefer a bounded lifecycle seam over another ad hoc environment-variable patch.
- Preserve the hard-cutover policy; do not add backward-compatibility layers.

## Current architecture facts to verify

### 1. The client already models one host process per compilation

`packages/hxhx/src/hxhx/macro/MacroHostClient.hx`:

- resolves `HXHX_MACRO_HOST_EXE` first;
- otherwise looks for a sibling `hxhx-macro-host` executable near `hxhx`;
- opens one stateful macro-host session for a compilation so hooks survive across compiler phases;
- expects a fresh host process per compilation today;
- does not itself own release-artifact provenance.

This distinction matters: reusing one executable artifact across CI steps does not require reusing one long-lived host process across unrelated compilations.

### 2. The compiler has per-invocation auto-build glue

`packages/hxhx/src/hxhx/Stage3MacroHostSupport.hx`:

- checks `HXHX_MACRO_HOST_AUTO_BUILD` when external mode has no configured executable;
- collects project-owned macro entrypoints and classpaths;
- calls `scripts/hxhx/build-hxhx-macro-host.sh`;
- writes the returned path into the current process environment;
- then opens the external-host session.

This is convenient for development, but the resulting path is not exported to later workflow steps or sibling compiler processes.

`Stage3Compiler.hx` also has a similar auto-build path for build macros. Review both call sites; do not fix only CLI macros while leaving build-macro recursion possible.

### 3. The build script has three materially different products

`scripts/hxhx/build-hxhx-macro-host.sh` currently chooses among:

1. **Generic committed snapshot**
   - used when no dynamic entrypoints or extra classpaths are requested;
   - built with Dune from `packages/hxhx-macro-host/bootstrap_out`;
   - stage0-free at runtime;
   - produces the full Stage4 host behavior captured in that committed snapshot.

2. **Fresh Stage4 host generated by stage0**
   - preferred today when dynamic project entrypoints/classpaths are requested and upstream `haxe` is available;
   - compiles `hxhxmacrohost.Main` plus generated exact-string entrypoints;
   - works for the focused upstream unit-macro workload after commit `507adab9`;
   - is not acceptable as Full1 runtime proof if correctness depends on this stage0 generation.

3. **Stage3-built bring-up host**
   - selected for dynamic inputs when stage0 is absent/forbidden or when explicitly preferred;
   - compiles `hxhxmacrohost.Stage3Main`;
   - its own documentation says it is protocol-correct for the self-test subset and intentionally does not implement `macro.run`;
   - is not automatically equivalent to the full Stage4 host.

The script name hides these different semantics. Decide whether they should remain one command with an explicit requested product, split into separate commands, or be replaced by another lifecycle.

### 4. A generic host plus native macro modules already has an early ABI seam

The full host contains early support for loading native macro modules at runtime:

- `hxhxmacrohost.Main` handles `macro.loadNativeModule` and `macro.runNativeExpr`;
- `NativeMacroModuleDynlink`, `NativeMacroModuleHost`, `NativeMacroModuleAbi`, and `NativeMacroModuleHostAbi` define a versioned registration boundary;
- `MacroHostClient` exposes load/run calls;
- `scripts/hxhx/run-macro-module-dynlink-smoke.sh` proves a small OCaml-authored `.cmxs` module can register and run an expression, but that smoke currently uses stage0 to build the full host and hand-written OCaml fixture modules.

This may be the beginning of the right long-term separation—generic host versus project-specific macro modules—or merely an early experiment. Do not assume it is the answer. Evaluate what would be required to compile ordinary Haxe-authored project macros into compatible candidate-bound modules without circularity or hidden stage0 use.

### 5. Distribution discovery already expects a sibling host

`MacroHostClient.resolveMacroHostExe()` looks next to the `hxhx` binary for names such as `hxhx-macro-host`. A build-once, package-together model would align with that existing user-facing seam. Determine whether CI should model that distribution shape or whether Full1 needs a different host-discovery contract.

## Exact failure history

### Scheduled run

Current owned failure:

- workflow: `Macro Runtime Parity (Weekly)`;
- run: `29243580105`, attempt 1;
- candidate SHA: `be044b128eaa8b9f0853ff8d45af5a34f00b656a`;
- external-host job failed in the unit-macro step after about 252 seconds;
- in-process unit, runci, and protocol checks passed;
- artifact ID: `8276541049`;
- artifact digest: `sha256:d2a53f35e2b06f2e385c939378df22c71fc1f1c4fdbe141c7b69861f46d714fa`.

The original job surfaced only a generic host-build exit. Commit `d66dd26d` now preserves the real compiler error and original exit status in the runci wrapper.

### First bounded repair

Local reproduction showed that the freshly generated host registry incorrectly tried to compile both:

- `unit.HelperMacros.getCompilationDate()`; and
- `HelperMacros.getCompilationDate()`.

The second form is a runtime-supported spelling alias, not necessarily a project class. Commit `507adab9` keeps both forms in expression expansion but removes built-in aliases from project-owned generated entrypoints. It also surfaces the final 80 build-output lines on host-build failure.

After that change, the exact external-host unit-macro command passed from both current Haxe source and the officially regenerated bootstrap snapshot.

### Deeper lifecycle failure

The next external-host runci invocation then reported:

```text
hxhx(stage3): macro failed: missing macro host exe (set HXHX_MACRO_HOST_EXE)
```

That runner deliberately invokes `hxhx` with stage0 disabled and does not prepare or pass a host executable.

Manually enabling auto-build in that state caused recursive builds: compiling the host through Stage3 inherited auto-build, that compilation asked for another external host, and the cycle repeated. The experiment was stopped and no recursive workaround was retained.

### New build-once probe at `d66dd26d`

A bounded local probe tested the generic committed snapshot instead of dynamic auto-build:

1. built one `hxhx` executable from committed bootstrap input with `HXHX_FORBID_STAGE0=1` and an unusable stage0 sentinel;
2. built one generic full macro-host executable from `packages/hxhx-macro-host/bootstrap_out` with the same stage0-forbidden settings;
3. passed that exact host path through `HXHX_MACRO_HOST_EXE` to every external-host check;
4. kept `HXHX_FORBID_STAGE0=1` and the unusable stage0 sentinel for the workloads.

The same host artifact passed:

- `test:upstream:unit-macro-stage3-no-emit`;
- `test:upstream:runci-macro-stage3-no-emit`;
- `test:upstream:display-stage3-no-emit`;
- `test:m14:macro-runtime-mode-switch`.

Observed markers included:

- `hxhx_macro_runtime_mode=external-host`;
- `macro_run[0]=ok`;
- `hook_onGenerate[0]=ok`;
- `stage3=no_emit_ok`;
- `wait_stdio=ok`;
- `GENERIC_MACRO_HOST_REUSE_PROBE:PASS`;
- `GENERIC_MACRO_HOST_DISPLAY_PROTOCOL_PROBE:PASS`.

This is strong focused evidence for the CI lifecycle seam. It is not, by itself, proof that arbitrary user macro modules work or that Full1 macro parity is complete.

One runner still checks that a `HAXE_BIN` command exists before doing any work, even when a prebuilt host is supplied. In the probe it pointed to a guaranteed-failing sentinel and was never invoked. Review whether that prerequisite should be removed or made conditional so stage0-free evidence does not depend on the mere presence of a stage0 binary.

## Current weekly workflow shape

`.github/workflows/macro-runtime-parity-weekly.yml` creates a matrix with `external-host` and `inproc` jobs. Each job:

1. installs toolchains and upstream Haxe 4.3.7;
2. builds `hxhx` once and exports `HXHX_BIN`;
3. runs unit macro;
4. runs runci macro;
5. runs display and the focused protocol/mode check;
6. emits the mode marker only if every step passed.

It does **not** currently build/export a macro host before the external-host workload. The unit runner sets auto-build inside its own compiler invocation; later steps do not inherit the resulting executable path.

The workflow installs upstream Haxe for oracle/tooling needs, so “Haxe is installed” is not proof that runtime delegation occurred. The design needs positive trace/provenance evidence showing that the candidate compiler and host did not invoke stage0 for correctness.

## Contract mismatch to address

`docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md` currently says no scoped macro-runtime blockers remain, while the latest required scheduled external-host lane is red and now has active bead `haxe_ocaml-vhk47.1`.

Recommend precise wording that distinguishes:

- previously completed semantic API coverage;
- the now-open host-artifact lifecycle/release-evidence blocker;
- focused local reuse evidence;
- a genuinely green candidate-bound aggregate.

Do not call the blocker resolved merely because the build-once probe passed.

## Candidate approaches to challenge

These are hypotheses, not decisions. Rank or reject them.

### Approach A: build the generic committed host once in the external-host CI job

- Build `hxhx` once.
- Build the generic macro host once from committed bootstrap input with stage0 forbidden.
- Record candidate SHA, source/snapshot digest, build command, executable digest, host ABI versions, and build trace.
- Export `HXHX_MACRO_HOST_EXE` for all later steps.
- Disable on-demand host artifact builds in release evidence.
- Let each compiler invocation spawn its own fresh process from the same executable.

Question: is a tracked bootstrap snapshot sufficiently candidate-bound when it is part of the candidate commit, or must Full1 rebuild the host from current Haxe source with candidate `hxhx` before counting it?

### Approach B: make current-source native `hxhx` build the full Stage4 host once

- Compile `hxhxmacrohost.Main`, not the limited `Stage3Main`.
- Do it before workloads and outside any macro-requesting compiler invocation.
- Reuse the resulting artifact.

Question: is this technically ready, and what bootstrap/macro dependencies must be broken first to avoid requiring the host while building itself?

### Approach C: generic host plus separately promoted project macro modules

- Package a generic full host with `hxhx`.
- Compile project/library macros into versioned native modules.
- Load those modules through the existing or revised ABI.
- Keep the host artifact stable while project macro modules are candidate/project specific.

Question: does the existing dynlink seam provide a credible foundation, or would using it now create a second incomplete macro architecture? What is the smallest behavior-first proof using Haxe-authored macro input rather than hand-written OCaml fixtures?

### Approach D: retain lazy auto-build as a development convenience only

- Permit auto-build in non-release local workflows.
- Add a hard recursion guard and explicit product selection.
- Forbid it in Full1 evidence unless it consumes a pre-authorized artifact plan.

Question: should lazy auto-build remain at all, and if so, what exact boundary prevents it from hiding stage0 or recursively compiling a host?

You may recommend a hybrid or a different approach, but state why it is safer and smaller.

## Questions you must answer

1. What is the recommended near-term CI lifecycle for the external host?
2. Is Approach A valid Full1 evidence, only diagnostic evidence, or valid after additional provenance checks?
3. What exactly makes a host artifact “same candidate” when committed generated snapshots are involved?
4. Should the external job build its host locally, or should a separate producer job build one immutable artifact that consumers download and verify?
5. Which environment variables are configuration, which are evidence inputs, and which should be removed from release paths?
6. How should auto-build recursion be made structurally impossible, including the separate build-macro path in `Stage3Compiler`?
7. Should `build-hxhx-macro-host.sh` be split into explicit generic-host, current-source-host, and dynamic-module commands?
8. Is `Stage3Main` still useful, or is its limited protocol-only role now more confusing than helpful?
9. How should real project/library macro modules reach the external host without stage0 and without recompiling the whole host per invocation?
10. Is the native macro-module ABI the right long-term seam? If not, what should replace or quarantine it?
11. What should the distribution contain so external-host mode works for an end user without environment setup?
12. Which upstream Haxe 4.3.7 workloads are necessary before claiming external-host parity beyond the focused build-once probe?
13. What trace proves stage0 was not invoked even when upstream Haxe is installed for oracle or package tooling?
14. What failures must be hard errors: absent host, digest mismatch, SHA mismatch, ABI mismatch, dynamic entrypoints requested against a generic-only host, recursive build depth, or stale artifact?
15. What is the smallest sequence of reviewable implementation slices?
16. Which docs/beads/markers must change immediately so the current red lane is represented honestly?

## Required invariants to evaluate

Challenge and refine this draft invariant set:

- A release-evidence compiler invocation never builds its own host artifact.
- The host artifact is prepared before the workload and identified by path plus digest.
- One external-host job uses one immutable host artifact for all required workloads.
- A fresh host process may be spawned per compiler invocation; process lifetime and artifact lifetime are separate concepts.
- Host/client ABI and macro API versions are checked before macro execution.
- Candidate SHA and source/snapshot provenance are recorded before the first workload.
- Stage0 fallback is impossible, not merely unused by convention.
- Dynamic project macro needs cannot silently fall back to “ran:<expr>” or another placeholder result.
- Generic-host limitations are explicit and do not become a false broad macro-parity claim.
- In-process and external-host artifacts remain independently attributable.
- A recursion regression covers CLI macros and build macros.
- Any development-only auto-build path is excluded from Full1 evidence and fails at build depth greater than one.

## Required validation plan

Your recommendation must give concrete evidence tiers and stop conditions for:

1. a pure lifecycle/recursion fixture;
2. a generic-host build with a deliberately unusable stage0 sentinel;
3. host/client ABI mismatch and missing/tampered artifact negatives;
4. unit, runci, and display using the exact same host digest;
5. one Haxe-authored non-builtin project macro or build macro;
6. separate in-process comparison evidence;
7. a fresh scheduled/reusable macro parity aggregate for one candidate SHA;
8. Full1 RC artifact provenance and freshness;
9. distribution install/run behavior with a sibling host executable;
10. cleanup and timing evidence so host preparation does not become an unbounded per-invocation cost.

For every proposed gate, say what it proves and what it does not prove.

## Requested bead patch

Recommend how to update `haxe_ocaml-vhk47.1` and whether it should split into children. For each proposed child provide:

- beginner-friendly title;
- priority and `thinking:*` level;
- user-visible reason;
- dependency direction;
- concise acceptance criteria based on behavior/evidence;
- whether it blocks the current Full1 macro aggregate or is later product work.

Do not create a giant “finish macros” task. Separate at least:

- CI host-artifact preparation/reuse;
- recursion and stage0-fallback prevention;
- artifact provenance/ABI evidence;
- project-specific macro-module strategy, if it is not required for the immediate selected upstream workload;
- docs/status truthfulness.

## Required output format

Return these sections:

1. **Executive recommendation**
   - State the chosen lifecycle in 5–10 plain-language bullets.
   - Say whether the build-once generic snapshot is an acceptable near-term Full1 seam.

2. **Current flow explained**
   - Give a short sequence diagram or numbered flow understandable to a new contributor.
   - Separate artifact build, process spawn, macro session, and project macro module.

3. **Option comparison**
   - Compare Approaches A–D and any better alternative.
   - Include correctness, provenance, recursion, developer experience, packaging, and future project-macro support.

4. **Recommended ownership boundaries**
   - Name the module/script/workflow that should own each decision.
   - State which current responsibility is in the wrong place.

5. **Invariants and failure policy**
   - Provide the final invariant list and hard-error cases.

6. **Validation and evidence plan**
   - Focused tests, real upstream workloads, same-SHA artifacts, stage0 trace, ABI negatives, timing, and RC handoff.

7. **Incremental implementation slices**
   - Order the next small commits.
   - Give entry/exit evidence and rollback boundary for each.

8. **Bead patch**
   - Exact changes/new tasks with plain-language titles and acceptance criteria.

9. **Docs and claim corrections**
   - Exact meaning changes needed in the blockers doc, CI docs, Full1 contract, or README.
   - Do not raise readiness from the local probe.

10. **What not to do**
    - List shortcuts that would create false Full1 evidence or long-term macro debt.

11. **Confidence and missing evidence**
    - Separate facts from inference.
    - Name any additional file, run artifact, or probe needed before implementation.

## Focused files to inspect

### Controlling prompt and policy

- `AGENTS.md`
- `docs/00-project/GPT_5_5_PRO_MACRO_HOST_LIFECYCLE_REVIEW_PROMPT.md`
- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/MACRO_EVAL_PARITY_CONTRACT.md`
- `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`
- `docs/00-project/STAGE0_POLICY.md`
- `docs/00-project/CI_GATES.md`
- `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`
- `docs/02-user-guide/compat/full-1.0-scope.json`
- `.beads/issues.jsonl` entries for `haxe_ocaml-vhk47`, `haxe_ocaml-vhk47.1`, and `haxe_ocaml-vhk47.2`

### Workflow and runners

- `.github/workflows/macro-runtime-parity-weekly.yml`
- `.github/workflows/gate-full1.yml`
- `scripts/hxhx/build-hxhx.sh`
- `scripts/hxhx/build-hxhx-macro-host.sh`
- `scripts/hxhx/regenerate-hxhx-macro-host-bootstrap.sh`
- `scripts/hxhx/run-upstream-unit-macro-stage3-no-emit.sh`
- `scripts/hxhx/run-upstream-runci-macro-stage3-no-emit.sh`
- `scripts/hxhx/run-upstream-display-stage3-no-emit.sh`
- `scripts/ci/runci-macro-no-emit-runner-fixture-test.sh`

### Compiler/client lifecycle

- `packages/hxhx/src/hxhx/Stage3Compiler.hx`
- `packages/hxhx/src/hxhx/Stage3MacroHostSupport.hx`
- `packages/hxhx/src/hxhx/macro/MacroRuntimeMode.hx`
- `packages/hxhx/src/hxhx/macro/MacroRuntimeSession.hx`
- `packages/hxhx/src/hxhx/macro/MacroHostClient.hx`
- `packages/hxhx/src/hxhx/macro/InProcMacroRuntime.hx`
- `packages/hxhx/src/hxhx/macro/InProcMacroSession.hx`

### Host and possible project-module seam

- `packages/hxhx-macro-host/src/hxhxmacrohost/Main.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/Stage3Main.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/EntryPoints.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/BuiltinMacros.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/MacroRuntime.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/NativeMacroModuleAbi.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/NativeMacroModuleDynlink.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/NativeMacroModuleHost.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/NativeMacroModuleHostAbi.hx`
- `packages/hxhx-macro-host/src/hxhxmacrohost/api/**`
- `scripts/hxhx/run-macro-module-dynlink-smoke.sh`
- `test/M14NativeMacroModuleHostAbiIntegrationTest.hx`
- `test/M14MacroRuntimeModeSwitchIntegrationTest.hx`
- `test/fixtures/hxhx-macros/**`

### Generated evidence, not hand-written architecture

Include the small build manifests and enough of `packages/hxhx-macro-host/bootstrap_out/**` to prove what the generic snapshot builds. Do not spend review effort critiquing generated OCaml style, and do not ask for direct edits to generated `.ml` files.

## Upload guidance

Use a focused current-commit Repomix bundle containing the files above, plus this prompt as a separate root file. Also include a small local-evidence note with:

- baseline commit;
- scheduled run/artifact identity;
- the two fix commits;
- exact build-once probe commands at behavior level;
- pass/fail markers;
- confirmation that generated `.ml` files came from official regeneration, not hand edits.

Do not upload:

- `.git/**`;
- ignored upstream checkouts under `vendor/**`;
- dependencies or package caches;
- `.tmp/**`, `_build/**`, `out/**`, logs, binaries, or retained worktrees;
- secrets or machine-local configuration;
- upstream Haxe compiler source/tests as implementation material.

The reviewer does not need a separate upstream Haxe repository for this lifecycle decision. If upstream behavior is questioned, request a black-box probe rather than implementation-source review.

## Final instruction

Prefer the smallest design that makes the current evidence honest and the end-user distribution understandable. Do not turn this into a whole macro-system rewrite. Equally, do not recommend a CI-only environment-variable patch that passes the selected workload while leaving real project macros, artifact provenance, or recursive host building undefined.
