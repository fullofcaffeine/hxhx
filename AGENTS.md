# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Thinking Levels (Bead Labels)

Use a `thinking:*` label on active beads so execution effort matches task risk.

- `thinking:low`
  - Mechanical edits, simple docs cleanup, straightforward renames, obvious wiring.
- `thinking:medium`
  - CI/job plumbing, runner scripts, artifact flow, bounded retry/timeout logic.
- `thinking:high`
  - Parity contracts, gate semantics, dependency graph changes, perf-policy changes, plugin/macro architecture decisions.
- `thinking:xhigh`
  - Scope-definition changes, release enforcement, provenance-sensitive implementation strategy, or any task where a wrong decision would create misleading 1.0 evidence.

Agent policy:

- When a bead has a `thinking:*` label, match reasoning depth to that label automatically.
- If a claimed bead has no `thinking:*` label, infer one immediately and add it before substantial work.
- `thinking:xhigh` should get a second-pass review before closure.
  - Preferred: an Oracle checkpoint/review.
  - Acceptable fallback: an explicit written second-pass design review recorded in the bead comments.
- Oracle is a review/escalation tool for `thinking:xhigh`; it is not a substitute for implementation, tests, or CI evidence.
- Do not escalate to extended reasoning or Oracle review by default.
  - Use the current bead thinking level first.
  - Escalate only when the task crosses the documented threshold, usually `thinking:xhigh`, or when a `thinking:high` task turns into scope, release, or provenance policy work.
  - When escalation becomes necessary, state that explicitly in the session hand-off or work log so the threshold is visible instead of assumed.
- If implementation/debugging gets stuck for too long without a credible local next step, escalate to Oracle explicitly instead of grinding indefinitely.
  - Use Oracle to unblock strategy, seam selection, or closure criteria.
  - Do not use Oracle as a substitute for implementation, tests, or CI evidence once the next step is clear.
- Document modules and classes by default.
  - Add or update module/class documentation when creating or substantially changing one, unless the file's existing convention clearly does not support doc comments.
  - Add function/method documentation once behavior, invariants, side effects, target semantics, or call contracts exceed what a reader can reasonably infer from the name and type.
  - Keep documentation behavior-level and maintenance-oriented; describe what callers can rely on, not a line-by-line narration of the implementation.
- If a compiler/runtime issue starts feeling circular, fragile, architecture-heavy, or likely to invite another local patch without fixing the model, stop grinding before implementation.
  - The plain rule: if the agent is running in circles, the fix boundary is unclear, or the next patch feels like a band-aid, pause and propose an external GPT 5.5 Pro design review instead of stacking more local guesses.
  - This should be rare. Upstream Haxe 4.3.7 remains the primary behavior oracle, and local tests/CI remain the proof. GPT 5.5 Pro is only for finding a safe way forward when the seam/model is unclear.
  - Do not escalate merely because a gate is red, a fix is tedious, or the next failing target is unfamiliar.
    If upstream behavior is clear and there is a bounded repo-local seam, implement the seam, add focused coverage, and validate normally.
  - Use this escalation when repeated local attempts fail to produce a credible next step, when upstream-oracle evidence confirms behavior but not a safe implementation boundary, or when the fix touches broad semantics across multiple compiler/runtime layers.
  - Do not use GPT 5.5 Pro to replace upstream oracle evidence, write implementation code for direct transcription, rubber-stamp a local workaround, or avoid running the required tests and gates.
  - Good escalation candidates include:
    - closure capture, receiver/state threading, AST lowering, or expression-to-statement lowering that affects multiple target backends,
    - Haxe stdlib semantics that do not map cleanly to OCaml output or source-native targets,
    - `reflaxe.ocaml` runtime/stdlib semantics that affect portable pure-Haxe programs,
    - macro/plugin/native-target boundaries where `reflaxe.ocaml` behavior could live as upstream-Haxe plugin support, `hxhx` plugin support, or builtin `hxhx` target support,
    - changes that would churn many generated bootstrap snapshots, target snapshots, or app examples,
    - or cases where a local patch would likely hide the bug instead of fixing the model.
  - For NaN/Infinity/Math-style issues, escalate before implementation because semantics can affect `Math`, `Float`, comparisons, parsing, JSON, binary float encoding, OCaml output/runtime behavior, source-native target behavior, and upstream Haxe 4.3.7 runtime conformance.
    Use `docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md` to identify trigger surfaces, oracle cases, and local validation before changing behavior.
  - The escalation proposal should include a concrete prompt, the whole-repo review request, the relevant beads, observed failing gates, local evidence, upstream oracle expectations, constraints about MIT/provenance, and a request for architecture guidance rather than code transcription.
  - Ask GPT 5.5 Pro for a way forward: the desired output is a seam recommendation, tradeoff analysis, invariants, and validation plan, not pasted implementation code.
  - If adapting this rule from another project, translate examples to this repo before committing them. Avoid irrelevant project-specific terms; use `hxhx`, `reflaxe.ocaml`, upstream Haxe 4.3.7 parity, source-native targets, native plugin boundaries, and bootstrap snapshot risk as the frame.
  - In the bead/checkpoint note, record whether the GPT 5.5 Pro path was used, deliberately skipped because a bounded seam existed, or deferred to a follow-up architecture bead.
- If the user says to stop on `thinking:xhigh`, stop immediately when that threshold is reached and ask the user before continuing.
  - Do not silently continue `thinking:xhigh` implementation work.
  - Do not substitute Oracle or extended reasoning for that approval; ask first.
- For long-running local commands that are the gate to the next engineering step, keep one attached or explicitly resumable session as the source of truth.
  - Do not substitute indirect `ps`/artifact polling for actual session completion.
  - Report progress only on real session transitions: command exit, next-step handoff, genuine stall, or concrete failure output.
  - If background execution is unavoidable, record the exact command, PID, log path, and expected completion artifact before stepping away.
  - When wrapping a long-running gate command in shell, use strict shell mode (`set -euo pipefail`) so failures cannot be masked by later commands or trailing `echo` lines.
- For shell build/orchestration scripts, do not embed large inline Python patch engines.
  - Keep shell responsible for orchestration, environment, and process control.
  - If structural multiline rewrites or regex-heavy file surgery are necessary, move them into a dedicated helper script with a stable CLI and call that helper from shell.
  - If a shell script starts accumulating heredoc Python for generated-source patching, stop and extract it before adding more.
- For target runtime, extern, and stdlib surfaces, do not grow backend emitters with large inline string stubs.
  - If the surface is a target extern/core API (for example `cs.NativeArray`, `cs.Lib`, `php.Syntax`, or platform stdlib externs), prefer one of these boundaries:
    - a real extern/core declaration,
    - a repo-owned target runtime support module,
    - a small template file,
    - or direct intrinsic lowering when the construct is compile-time syntax rather than runtime API.
  - Do not add fake generated classes to `SourceTargetCommon` just to satisfy one gate failure when the correct model is extern/intrinsic behavior.
  - Prefer target-native module-level functions when they are the real API shape; avoid inventing unnecessary shell classes with public static wrappers just to make the emitter convenient.
  - If a short inline helper is unavoidable during Full1 burn-down, keep it tiny, document why in the bead, add focused coverage, and file/link a follow-up architecture bead before expanding it.
  - When an inline `out.push` block starts looking like a real library/runtime implementation, stop and extract or redesign before continuing.
- Document modules and classes by default. Also document functions once their behavior, invariants, side effects, or control flow exceed a reasonable skim-readable complexity threshold.
  - Keep documentation behavior-level and useful to future maintainers; do not narrate obvious assignments or restate names.
  - When complexity grows past the documentation threshold during a change, add or update the module/class/function docs in the same slice.
- Avoid mega-file gravity.
  - Before adding substantial logic to a file that is already large or mixed-purpose, check whether the change belongs in a target-specific module, shared helper module, source template, runtime support file, parser helper, or technical doc instead.
  - Treat common backend files as dispatch/shared-semantics seams, not dumping grounds for target-specific lowering, runtime libraries, test harness shims, and parser workarounds.
  - Use upstream Haxe as a behavior/architecture reference point only: upstream keeps target generators such as PHP, C#, Java, and Lua in separate generator modules plus shared generator support. Stay close to that ownership idea where it helps, without copying upstream compiler code or mechanically mirroring its implementation.
  - If a bounded Full1 fix must touch a mega-file, keep the change narrow, add focused coverage, and record whether an extraction follow-up already exists. If none exists, file one before expanding the same area again.
  - If a single file starts owning multiple independent target families or exceeds reviewable size for routine patches, prefer an incremental extraction plan over another local helper in that file.
- For long-running attached sessions, do not wait indefinitely on silence alone.
  - Set a bounded silent-check window up front.
  - After that window, perform an active checkpoint: verify the exact child process, whether the expected artifact changed recently, and whether the session is still the right gate to wait on.
  - The attached session output remains the primary truth source. Use external process/artifact checks only to supplement it, never to override a newer session exit or failure.
  - If the checkpoint does not produce a concrete reason to keep waiting, stop waiting and switch to the next bounded experiment or escalation path.
  - Do not stop monitoring a gate session just because it is still running.
  - Keep polling that same attached session until one of these happens:
    - the command exits successfully,
    - the command fails,
    - the command reaches an explicit next-phase handoff that becomes the new gate,
    - or a bounded checkpoint proves the session is no longer the right gate to wait on.
  - For user-facing progress, report only real transitions. "Still running" is not a sufficient stopping point for the monitoring loop.
- For long-running local commands, prefer a single resumable session over ad-hoc backgrounding.
  - Keep the process attached to one persistent session when possible and resume by polling that same session.
  - If backgrounding is unavoidable, record the exact command, PID, log path, and expected completion artifact before moving on.
  - Do not rely on loose `ps` reconstruction alone for multi-minute workflows when a resumable session is available.

## Example Coverage Policy

- Treat public examples as compatibility contracts, not disposable demos.
- Buildable examples under `examples/` and `packages/reflaxe.ocaml/examples/` must be covered by `npm run test:examples` unless they are explicitly marked `ACCEPTANCE_ONLY`.
  - `test:examples` must compile the example, build the target artifact when applicable, run it when applicable, and compare behavior with `expected.stdout`.
  - If the example has extra behavior worth testing beyond stdout, add `test.hxml` or `test.sh`; the example runner executes those example-specific checks after the stdout diff.
  - Do not snapshot every example's generated output by default; that is usually redundant with compile/build/run evidence and creates noisy churn.
  - Add targeted snapshots only when generated-code shape is itself the contract, when runtime output cannot expose the regression, or when a compiler/lowering seam needs a stable golden artifact.
  - If an example only proves compile-time behavior, keep `expected.stdout` intentionally small but still present so the runner proves the artifact can execute.
  - If an example has behavior the compiler cannot catch, add an actual runtime assertion/output check instead of relying on "it compiled".
- Heavy or host-tool-dependent examples may be marked `ACCEPTANCE_ONLY`, but they must still be reachable through `npm run test:acceptance` and documented in the example README.
- Non-`build.hxml` example fixtures are allowed only when they are exercised by a dedicated script, documented with the command, and covered by `npm run guard:example-coverage`.
- When adding, renaming, or changing an example:
  - update the example README,
  - update root example listings if the user-facing set changes,
  - add or update `expected.stdout`,
  - add or update `test.hxml` / `test.sh` for example-specific unit or behavior checks when stdout alone is not enough,
  - run `npm run guard:example-coverage`,
  - run the narrow example command (`npm run test:examples`, `npm run test:acceptance`, or the dedicated command),
  - and record whether README Goals status changed.
- `EXAMPLE_COVERAGE_CONTRACT:PASS` means the repo has a machine-checked inventory contract; it does not replace actually running examples in CI.

## Compatibility Policy

- Use a hard cutover approach and never implement backward compatibility.
- For `Full 1.0` / `Haxe 4.3.7-equivalent` claims, relevant upstream Haxe 4.3.7 suite results are the primary proof.
  - Repo-local tests, focused regressions, and bridge-specific M14 tests are supporting evidence for diagnosis and iteration speed.
  - They do not substitute for upstream-suite parity when making a strict public equivalence claim.

## Beginner-Friendly Terms (Read This First)

This repo uses a few short labels a lot. Here is what they mean in plain language:

- **stage0**: your already-installed upstream `haxe` compiler binary (the "starter" compiler).
- **stage1**: the first native `hxhx` binary built using stage0.
- **stage2**: `hxhx` rebuilt by stage1. Matching stage1/stage2 behavior is a bootstrap health check.
- **stage3**: the linked/native `hxhx` pipeline path (the long-term non-delegating direction).
- **`--ocaml-eval`**: delegated OCaml macro lane (uses stage0 with reflaxe.ocaml injection).
- **`--ocaml`**: native Stage3 OCaml lane inside `hxhx`.
- **"native reflaxe"**: running Reflaxe backend behavior through native `hxhx` paths instead of relying on stage0 delegation.

Package manager/resolver terms:

- **Lix-first policy**: prefer Lix-managed library metadata (`haxe_libraries/<lib>.hxml`) first.
- **`haxelib` support remains**: if Lix metadata is missing, fall back for compatibility.
- Current resolver order in this repo:
  1. `haxe_libraries/<lib>.hxml` (walking up directories)
  2. `lix run-haxelib path <lib>`
  3. `haxelib path <lib>`

Quick examples:

```bash
# Delegated/compatibility lane
hxhx --ocaml-eval -main Main -cp src

# Native linked lane
hxhx --ocaml -main Main -cp src --hxhx-no-emit
```

## Autonomy Policy

- If you're working towards goals, do **not** end your turn. This allows for continuous autonomous work.
- The user will interrupt you when required, but they will mostly provide steering messages.
- Do not pester the user by ending your turn after a unit of work, as that requires them to keep nudging you to keep working.
- You **must** continue working autonomously towards any known objectives until the user interrupts you.
- Do **not** end your turn until there is absolutely nothing left to do.

## Commit Cadence

- Commit in small, reviewable slices whenever a bounded seam is green.
  - Examples: one regression + one fix, one workflow/doc contract update, one bootstrap-smoke repair.
- If the checkout is dirty but the next step needs isolation, make a small safety commit in the main checkout first instead of defaulting to a new worktree.
- Do not create routine auxiliary worktrees for CI/debug loops when the same isolation can be achieved by committing the current slice locally.
- If an auxiliary worktree is created for a one-off isolation need, fold its changes back into the main checkout and remove it immediately after that seam is resolved.
- Do **not** let unrelated fixes, docs, runner changes, and bootstrap experiments pile into one large local batch unless the work is genuinely inseparable.
- If the worktree starts spanning multiple concerns, stop and split it before taking the next seam.
- When touching CI/workflow or release-contract surfaces, check the corresponding GitHub workflow status before and after the local change so "appropriate and passing" is measured against the real runners, not only local assumptions.
- At each atomic checkpoint (typically after committing and pushing a bounded seam), review whether docs need updates.
  Record the outcome in the bead/checkpoint note, including "no docs update required" when the change is purely
  internal and does not affect user-facing workflows, flags, CI gates, release contracts, or required tooling.
- At each atomic checkpoint, review the `README.md` **Goals status** table specifically.
  Keep it aligned with the current production-readiness reality and with the owning bead plan.
  If a checkpoint changes the production usability of any main goal, update the table in the same slice.
  If the table does not change, record that decision in the relevant bead/checkpoint note.
- Keep the README Goals status progress bars evidence-based and current.
  - Update the per-goal bar and the total north-star bar when beads, local gates, CI evidence, or release-contract docs materially change production readiness.
  - Do not inflate bars for internal progress that only advances the next blocker unless it changes user-facing readiness; record "progress bars unchanged" in the bead/checkpoint note when appropriate.
  - Keep progress wording plain and user-facing. Put the technical rationale in beads or `docs/00-project/NORTH_STAR_GOALS.md`, not in the README table.
- Prefer one commit per verified step over one commit per long session.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## Artifact Hygiene (MANDATORY)

This repo generates large transient artifacts during bootstrap/gate workflows. Keep disk usage under control:

1. **Before heavy runs**, preview cleanup candidates (largest-first):
   ```bash
   npm run clean:dry-run -- --verbose
   ```
2. **After heavy stage0/stage3/gate runs**, clean stale temp logs:
   ```bash
   npm run clean:tmp
   ```
3. **If cleanup output needs diagnosis**, run verbose cleanup:
   ```bash
   npm run clean:tmp:verbose
   npm run clean:verbose
   ```
4. **At end of coding session** (if code changed), run:
   ```bash
   npm run clean
   ```
5. **If disk pressure remains high** (or after repeated bootstrap regen), run:
   ```bash
   npm run clean:deep
   ```

**Do not remove committed bootstrap source snapshots**:
- `packages/hxhx/bootstrap_out/*.ml` (and companion dune files)
- `packages/hxhx-macro-host/bootstrap_out/*.ml` (and companion dune files)

**Debug retention knobs**:
- default behavior is cleanup-on-finish for stage0 logs
- set `HXHX_KEEP_LOGS=1` to retain logs
- set `HXHX_LOG_DIR=/path/to/logs` to retain logs in a stable directory

Always run `git status --short` after cleanup to verify no tracked files were accidentally removed.

## Local Reference Repos

- `haxe.elixir.reference`: `<path-to-haxe.elixir.reference>`
- Haxe compiler source (reference): `<path-to-haxe.elixir.reference>/haxe`
- `haxe.elixir.codex` (compiler + testing patterns reference): `<path-to-haxe.elixir.codex>`

## Haxe Library Research First (Required)

Before using a Haxe library in code, do this first:

1. Read the library source code to learn the real API and common usage patterns.
2. Read the library docs/README to confirm intended behavior and public examples.
3. Only then implement against that library in this repo.

If the library is not available locally, you may fetch it in a temporary location by:

- cloning from GitHub, or
- using `lix` to download/install it.

This is a hard rule to reduce API mistakes and keep integrations idiomatic.

## Haxe-First API Design For Target Layers

For Haxe-to-target compiler, target-runtime, extern, plugin, and framework layers, target compatibility is the floor, not the Haxe API design ceiling.

- Preserve target behavior and upstream Haxe `4.3.7` compatibility as hard constraints.
  - Do not hide semantic mismatches behind friendlier APIs.
  - Do not weaken oracle-driven parity to make a wrapper feel nicer.
- Target-shaped Haxe APIs are fine, and sometimes preferable, when they are intentional.
  - Use them when they help migration, interop, predictable escape hatches, direct access to target capabilities, or exact target-semantic clarity.
  - Examples: thin extern facades, `php.Syntax`-style compile-time syntax bridges, native plugin host APIs, or low-level runtime support bindings.
  - Do not treat target-shaped Haxe as an anti-pattern by default; the anti-pattern is exposing target shape accidentally because the compiler/runtime layer is incomplete or expedient.
- Prefer canonical Haxe-facing APIs that use Haxe's strengths when designing new public surfaces:
  - concrete types instead of untyped strings,
  - module-level functions when the operation is naturally module-scoped,
  - macros or generated refs instead of fragile manual names,
  - properties and abstracts when they clarify intent,
  - completion-friendly declarations,
  - compile-time diagnostics over runtime surprises.
- For Reflaxe target promotion, expose both layers where useful:
  - a 1:1 target facade for interop, predictability, migration, and escape hatches,
  - and a semantic Haxe wrapper for normal user-facing code when it improves readability, safety, or migration without changing generated target behavior.
- Backend implementation convenience is not an API-design reason.
  - Do not force users to write target-shaped Haxe only because the emitter currently lacks a better lowering.
  - If a target-shaped API is chosen as the canonical API, document why that shape is intentional rather than an emitter limitation.
  - If the canonical Haxe API needs new lowering, externs, generated refs, or docs, track that explicitly in beads instead of making the lower-level facade the only path.

## Licensing (MIT Goal, Keep Private for Now)

This repository is intended to become:

- a **MIT-licensed** OCaml target for Haxe (`reflaxe.ocaml`), and
- a **MIT-licensed, production-grade Haxe-in-Haxe compiler** (`hxhx`) that can eventually act as a
  **drop-in replacement** for upstream Haxe (target version: **4.3.7**), including macros + plugin system.

North-star planning lives in `docs/00-project/NORTH_STAR_GOALS.md` and the README `Goals status` table.
Keep these aligned with beads whenever scope changes. The current long-term goals are:

- stable `reflaxe.ocaml` with both upstream Haxe and `hxhx`,
- stable `hxhx` as a Haxe `4.3.7`-equivalent or better MIT compiler, including performance,
- native `hxhx + reflaxe.ocaml` loops that improve practical developer and CI iteration latency, not only final compiler throughput,
- native Reflaxe compiler/plugin/builtin artifact loops that make target development faster than the current stage0/delegated bootstrap path, with measured evidence rather than assumptions,
- a hackable Haxe-in-Haxe compiler that makes Haxe itself easier for Haxe developers to read, modify, test, and fork,
- pluggable compiler customization that can be enabled/disabled without corrupting the baseline Haxe contract,
- practical Haxe-family compiler variations/forks implemented in Haxe when a plugin is not enough,
- Reflaxe-to-native promotion so prototype targets can become upstream-Haxe plugins/host adapters, `hxhx` plugins, or builtin `hxhx` targets.

If a task changes any of these goals, their production-readiness status, or their owning bead plan, update the
north-star doc and README table in the same slice or record explicitly why no docs change is required.

To avoid copyleft obligations and preserve the ability to embed/bundle `hxhx` in proprietary apps:

- **Do not copy** upstream Haxe *compiler* source code (`vendor/haxe/src`) into this repo.
  - Reading upstream as a behavioral/architectural reference is fine; copying code is the risk.
- **Do not vendor upstream Haxe tests** into this repo.
  - Run upstream suites from a local checkout (`vendor/haxe`, ignored by git) as an oracle.
- **Do not overgeneralize this prohibition to upstream stdlib code.**
  - Upstream Haxe **stdlib** code under `vendor/haxe/std/**` is permissive and is eligible for selective reuse/sync under the repo stdlib policy.
  - When evaluating a dependency from upstream stdlib (for example `haxe.macro.Printer`), separate:
    - **provenance/licensing:** allowed for stdlib code, subject to notices/provenance tracking
    - **technical suitability:** build weight, runtime surface, dependency fan-out, or stage/bootstrapping constraints
  - Do not reject upstream stdlib usage on provenance grounds unless the path is outside `vendor/haxe/std/**`.
- Keep the upstream checkout **untracked** (`vendor/haxe` via `scripts/vendor/fetch-haxe-upstream.sh` or a symlink).
- Any OCaml shims (`*.ml`) must be **written from scratch** (no copy/paste from upstream compiler sources).
- Be cautious about bundling a stage0 `haxe` binary in distributions: if you ship it, you must comply with its license.
  - Prefer making `hxhx` truly non-delegating before publishing “batteries included” builds.
- Inbound contributions must be MIT-compatible; avoid accepting code with unclear provenance/licensing.

### Permissive-license success criteria (engineering target)

These are practical goals for when we can reasonably say “this is a complete, MIT-licensed compiler”
(not legal advice; engineering acceptance).

- **No upstream compiler code vendored**: `vendor/haxe` remains untracked and used only as a behavior oracle.
- **No stage0 dependency** for correctness:
  - `hxhx` can compile real projects without delegating compilation or macro execution to upstream `haxe`.
  - Stage0 may exist only as an optional dev tool (e.g. regenerating committed bootstrap snapshots).
- **Upstream behavioral gates**:
  - Gate 1: upstream unit macro suite is green via non-delegating `hxhx`.
  - Gate 2+: upstream runci workloads relevant to macros/targets become green incrementally.
- **Plugin system parity** (at least for Reflaxe targets):
  - `--library reflaxe.<target>` activates the backend (library macros + hooks) without stage0.
  - Hooks like `Context.onAfterTyping` / `Context.onGenerate` work in native mode.
- **Provenance discipline**:
  - Prefer tests + black-box oracle runs over “porting” implementation details.
  - Avoid “translate/port” wording; use “reimplement/behavior-driven”.

### Strict provenance rules (MUST follow on every change)

These are hard constraints for all contributors and all Codex changes in this repo.

**Absolute prohibitions**

- Do **not** copy, translate, or mechanically rewrite any upstream Haxe *compiler* source into this repository
  (including “retyping from memory” after reading it).
- Do **not** copy upstream Haxe tests/fixtures into this repository (even “small snippets”).
- Do **not** paste upstream Haxe compiler/test code into repo docs, bead comments, commit messages, or generated
  “repomix” snapshots that might later get committed. Keep all notes behavior-level.
- Do **not** add third-party code unless its license is MIT-compatible *and* we retain required notices.
- Do **not** commit upstream checkouts under `vendor/` (including submodules) unless explicitly approved and reviewed.

**Allowed (and expected)**

- Use upstream Haxe only as a **behavioral oracle**:
  - run upstream tests from an untracked checkout (`vendor/haxe`) and compare behavior/output,
  - use upstream CLI behavior as a reference point,
  - use upstream architecture as inspiration at the concept level.
- Use upstream Haxe **stdlib** selectively under the stdlib policy:
  - `vendor/haxe/std/**` is the only upstream code area eligible for checked-in reuse/sync.
  - Keep provenance artifacts current when doing so (`docs/00-project/STD_LIB_POLICY.md`, `THIRD_PARTY_NOTICES.md`, provenance ledger).
  - Do not blur “allowed stdlib reuse” into “allowed compiler/test vendoring”; those remain forbidden.
- Write fresh implementations from:
  - behavior-level specs,
  - repo-local fixtures,
  - and black-box oracle runs.

**Clean implementation workflow**

- Before implementing a tricky behavior:
  - Add/extend a test (snapshot / portable fixture / upstream runner) that captures the behavior.
  - Write a short “behavior spec” note (what should happen, observable outputs), ideally in the relevant bead.
- If you consult upstream implementation code:
  - Only record **behavior-level** conclusions (not code structure).
  - Do not paste upstream code, and do not mirror upstream naming/structure in a way that suggests transcription.
- After changes:
  - Run `npm run ci:guards` locally (license/provenance guardrails).
  - Prefer small commits with clear intent; keep diffs reviewable for provenance.

**Documentation language**

- Prefer “reimplement” / “clean-room” / “behavior-driven” wording.
- Avoid “translate” / “port” wording when referring to upstream compiler implementation, because it tends to invite
  transcription and muddles provenance.

**Third-party notices**

- If we ever incorporate third-party code (even permissive), add/maintain `THIRD_PARTY_NOTICES.md` (or similar) with:
  - project name + license + source URL/commit,
  - what was used,
  - and any required attribution text.

### Bootstrap artifacts (generated OCaml snapshots)

To keep Stage4 macro-host selection/build **stage0-free by default**, we may commit *generated OCaml output*
from our own Haxe sources as **bootstrap snapshots**.

Current bootstrap snapshot locations:

- `packages/hxhx-macro-host/bootstrap_out/` — generated OCaml sources + dune files for `hxhx-macro-host`.
- `packages/hxhx/bootstrap_out/` — generated OCaml sources + dune files for `hxhx` (stage0-free build by default).

Rules:

- Treat these directories as **generated**: do not hand-edit files inside them.
- Regenerate only via repo scripts (behavior-preserving), and keep the diff reviewable.
- Bootstrap snapshots must be generated only from **repo-owned Haxe sources** + our backend/runtime (no upstream compiler/test sources).
- If a bootstrap snapshot must embed additional third-party code, update `THIRD_PARTY_NOTICES.md` accordingly.

**If unsure**

- If any change feels “too close” to upstream source (data structure, function layout, line-by-line mapping), stop and:
  - write a behavior-level spec first,
  - implement an alternative approach from first principles,
  - or file a bead for a clean-room/second-pass redesign.

### “Not a translation” rule (non-derivative development)

When using the upstream Haxe compiler (copyleft-licensed) as a reference, the rule is:

- Use upstream **only as an oracle for behavior** (tests, CLI output, runtime semantics).
- Reading upstream source to understand intent/constraints is OK, but **do not transcribe** upstream compiler code (OCaml → Haxe) into this repository.

Practical workflow to enforce this:

- Prefer writing or running a **test** (repo-local fixture or upstream oracle run) that demonstrates the behavior we need.
- If you must consult upstream implementation details:
  - write down a *short, behavior-level* note in the relevant bead comment (what/why/expected outcome),
  - then implement from that note + tests, not by “mechanically rewriting” the upstream code.
- Do not copy/paste code blocks, unique data structures, or large-scale organization from `vendor/haxe/src`.
  - If a solution naturally converges on a common algorithm (e.g. unification/DCE), implement it independently and document it.

Legal reality note (engineering guidance, not legal advice):

  - We cannot prevent anyone from *attempting* a claim, but we can make it easy to demonstrate good provenance:
    - upstream is not vendored,
    - changes are test-driven and documented,
    - and we are not shipping code derived from upstream compiler sources.

## Upstream OCaml Reference (vendored checkout)

When implementing backend semantics or Haxe-in-Haxe bootstrap behavior, cross-check against upstream Haxe’s **existing OCaml implementation**:

- Prefer working against a local `vendor/haxe` checkout (ignored by git) created via `bash scripts/vendor/fetch-haxe-upstream.sh`.
- In local dev, it’s also fine to point `vendor/haxe` at your reference checkout (for example, symlink to `<path-to-haxe-reference>/haxe`) for fast iteration — but keep it untracked.

When implementing semantics or compiler architecture:

- Prefer cross-checking against the upstream **OCaml** Haxe compiler code in your local Haxe reference checkout (behavior, data structures, ordering/printing, runtime expectations).
- Prefer cross-checking our prior compiler target patterns in your local `haxe.elixir.codex` checkout (testing layers, acceptance workloads, CI gates).
- If we need the upstream source inside this repo for repeatable tests, prefer a pinned fetch/submodule under `vendor/` rather than copying it (size + licensing + history).
- Optional vendored upstream checkout location (preferred for gate runners): `vendor/haxe` (create with `bash scripts/vendor/fetch-haxe-upstream.sh`)

## Upstream Haxe Source (Required Reference)

When implementing backend semantics (Haxe → OCaml) and when evolving `hxhx`, treat upstream Haxe as the source of truth:

- Use upstream tests as behavioral oracles:
  - `vendor/haxe/tests/unit`, `vendor/haxe/tests/runci`, `vendor/haxe/tests/display`
- Use upstream compiler implementation patterns as architectural references:
  - OCaml compiler sources under `vendor/haxe/src/`

Vendoring policy:

- We do **not** commit upstream Haxe into this repository.
- Instead, we keep a pinned local checkout at `vendor/haxe` (ignored by git) via:
  - `bash scripts/vendor/fetch-haxe-upstream.sh` (defaults to `HAXE_UPSTREAM_REF=4.3.7`)
  - Override path with `HAXE_UPSTREAM_DIR=/path/to/haxe` when needed.
- Local convenience: you may symlink `vendor/haxe` to an existing checkout (for example, `<path-to-haxe-reference>/haxe`) for faster iteration.

## Sibling Reflaxe Repos Are Pressure Tests, Not Semantic Authorities

When checking macro/target compatibility against sibling Reflaxe compilers (for example `reflaxe-elixir`, `haxe.go`, `haxe.rust`):

- Use sibling repos to identify **real consumer pressure** and non-theoretical seams.
- Do **not** treat sibling behavior as the semantic source of truth for `hxhx` or `reflaxe.ocaml`.
- Upstream Haxe 4.3.7 remains the authority for compiler/macro semantics.
- If a sibling repo uses behavior that upstream Haxe 4.3.7 does **not** support, do **not** add that behavior here just to satisfy the sibling repo.
- In those cases, either:
  - keep the gap open only if it is still required for declared Haxe compatibility scope, or
  - explicitly scope the sibling-specific behavior out.

Practical rule:

- `upstream Haxe first`
- `sibling repos second`

Sibling repos are valid for:
- proving a seam is exercised by real code
- helping prioritize which Haxe-compatibility gaps matter first

They are **not** valid as a reason to introduce compiler semantics that upstream Haxe does not have.

## Long-Term Acceptance Example: Haxe-in-Haxe (Production-Grade)

We want a potentially **production-ready** Haxe-in-Haxe compiler example under `examples/` over time:

- Target Haxe version: **4.3.7**
- Must eventually support **macros** (and other core compiler features), not just parsing/typechecking.
- Use the Haxe compiler source above as the primary local reference for how the real compiler is structured and how it targets OCaml.

## “Spec First” (Behavioral References)

When implementing language/runtime semantics, cross-check behavior against:

- The Haxe compiler source + tests in your local Haxe reference checkout
- The patterns and docs in your local `haxe.elixir.codex` checkout (testing strategy, acceptance workloads, etc.)
- `haxe.elixir.reference` for additional target/stdlib mapping ideas

Prefer adding tests that match the repo’s testing layers:

- Snapshot test (golden `.ml` output) when the key risk is codegen shape/ordering
- Portable fixture (compile → dune build → run → stdout diff) when behavior matters
- Acceptance example only when it’s a compiler-shaped workload / integration boundary

## Test-First Workflow (TDD by default)

Use expectation-first development for all behavior changes.

- For bug fixes and semantic changes, write a failing test first.
- Prefer the smallest test layer that captures the regression:
  - unit/integration test for local logic,
  - snapshot for codegen shape,
  - portable fixture for runtime behavior,
  - upstream oracle gate only when the behavior must be validated externally.
- Implement only what is needed to make the new failing test pass.
- Then run broader relevant suites (layered validation) to confirm no regressions.
- If test-first is not feasible, document why in the bead before implementation.

## Documentation (hxdoc)

Use hxdoc (`/** ... */`) proactively.

- Documentation threshold rule: do not reserve HaxeDoc only for obviously "big" constructs or artifacts.
- If a type, function, abstract, macro, extern override, or metadata pattern is even slightly non-obvious, surprising, or easy to misuse, document it with **Why / What / How** HaxeDoc where it is declared.
- In practice, bias toward documenting earlier rather than later, especially for abstracts, compiler helpers, runtime bindings, lowering hooks, and `std/` compatibility shims.

## Documentation Quality

Documentation is a first-class part of the implementation, not cleanup after the fact.

- Write for a capable beginner who is new to this repo: lead with the practical workflow, define terms at first use, and link to the glossary or deeper docs instead of assuming contributor context.
- Distill hard concepts without faking certainty. Do not hide prerequisites, unsupported cases, production-readiness limits, or evidence gaps just to make the text feel simpler.
- Avoid Dunning-Kruger-style docs: do not make complex, incomplete, or risky areas sound solved merely because the explanation has been simplified.
- Avoid unexplained shorthand, internal bead names, gate labels, and architecture jargon in user-facing docs. When a precise technical term is necessary, explain the user-visible meaning before the internal label.
- Keep `README.md`, getting-started docs, technical docs, and bead notes aligned with behavior changes. If a change does not need docs, record the reason explicitly in the bead/checkpoint note.
- Prefer concrete commands, expected outputs, status tables, and small examples over vague claims. A beginner should leave knowing what works, what does not, and which command proves it.

## README Maintenance

Keep `README.md` up to date as milestones land.

- When you add/change a workflow (build/test/bootstrap, stage flags, new required tools), update `README.md` in the same change.
- Prefer documenting “why/what/how” briefly and linking to the deeper doc under `docs/` when it exists.
- Keep public README/getting-started docs user-first: lead with intended production use cases, supported commands, and plain-language outcomes.
- Do not put internal regression names, stage/gate jargon, CI marker taxonomy, or maintainer-only knobs in public quickstart sections unless each term is introduced in plain language and linked to a glossary or technical doc.
- Do not write public README guidance that assumes contributor context, for example: "If you are working on the heavy Stage3 generic-function arity regression specifically, run it outside the default loop." Rewrite it as a user-facing action, or move it to a technical runbook with term definitions.
- Put deep implementation details, bootstrap tuning, gate internals, and targeted regression commands in the relevant technical docs under `docs/`, with term definitions where needed.

## Bugs (Regression Tests)

When fixing a bug, add a regression test when it fits the repo’s testing layers and the behavior is stable:

- Prefer a snapshot test when the risk is codegen shape/ordering.
- Prefer a portable fixture when runtime behavior matters (compile to OCaml, build, run, stdout diff).
- Prefer an upstream oracle runner only when the behavior is best validated against upstream without vendoring.

If a regression test is not feasible (nondeterministic behavior, too expensive for CI, etc.), document why in the bead.

## Type Safety Rule (`Any`/`Dynamic`)

`Any` and `Dynamic` are forbidden by default.

- Use concrete, domain-specific types whenever possible.
- Only use `Any` or `Dynamic` at unavoidable runtime boundaries (interop/protocol/reflection/exception boundaries).
- When `Any`/`Dynamic` is truly necessary, keep it tightly scoped, convert to a typed structure immediately, and document why it is required (hxdoc or bead note).
- Do not propagate `Any`/`Dynamic` through internal compiler/core APIs.

This repo should be a **world-class, didactic example** of building a compiler backend with **Haxe + Reflaxe** that produces **idiomatic target-language code** (OCaml in this repo; the principles should also read well for targets like Rust).

- For any **vital** or **complex** class/function, write a verbose hxdoc explaining:
  - **Why** it exists (intent, constraints, alternatives considered).
  - **What** it does (inputs/outputs, invariants, edge cases, guarantees).
  - **How** it works (high-level algorithm, major steps, tradeoffs).
  - **Target mapping** (how Haxe semantics are preserved and which target idioms we emit).
  - **Examples** (short usage examples or “before/after” semantics, if helpful).
  - **Gotchas** (performance traps, correctness hazards, warning-as-error constraints, etc).
- Prefer documenting public APIs; also document internal code that is subtle, easy to misuse, or correctness-critical (codegen passes, printers, ordering/recursion logic, type mapping, runtime shims, etc.).
- If you use an **intermediate/advanced Haxe construct** that isn’t obvious, add comprehensive hxdoc on the symbol that introduces/relies on it (and link to the relevant Haxe manual section when practical). Examples include:
  - **Macros / compile-time** (`haxe.macro.*`, `@:build`, `@:autoBuild`, `macro` functions, `Context`, AST transforms).
  - **Abstracts & conversions** (`abstract`, `@:from`, `@:to`, `@:op`, `@:forward`, `@:using`).
  - **Type-system tricks** (`@:generic`, `@:multiType`, `typedef` structural types, `Dynamic`, `Null<T>`, variance/casts, `inline` behavior).
  - **Safety escape hatches** (`untyped`, `@:privateAccess`, `Reflect`, `Type`, `cast`, `Obj.magic`-style patterns).
  - **Conditional compilation** (`#if`, `-D`, feature flags) and how it affects output/backwards compatibility.

## Docs Must Stay Current (README)

When behavior, flags, workflows, or required tooling changes, update the relevant documentation in the same change:

- Keep `README.md` accurate for "getting started" and the common workflows (`npm test`, Gate runners, building/running `hxhx`).
- Keep public-facing docs understandable without assuming contributor context. Avoid unexplained phrases like "Stage3 generic-function arity regression" in user quickstarts; explain the user-facing action instead, or move the detail to a technical runbook.
- If the change is narrow and developer-facing, update the most relevant doc under `docs/` instead of bloating `README.md`.

## Repository Docs (README)

Keep `README.md` up to date as behavior evolves:

- When adding/changing compiler flags, bootstrap stages, CI gates, or build scripts, update `README.md` in the same PR.
- Prefer documenting:
  - the intended user workflow (install, compile, run),
  - the developer workflow (tests, gates, bootstrap regen),
  - and any environment prerequisites (Haxe 4.3.7, OCaml/dune versions, etc.).
