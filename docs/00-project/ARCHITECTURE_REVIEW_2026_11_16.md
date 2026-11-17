# Architecture Review, 2026-11-16

Status: **accepted by the owner on 2026-11-16** (decisions D1, D2, D4, D6, D7,
and the freeze in the stop list). Decisions D3, D5, and D8 wait for the
measurements named in section 9. The goals and README framing follow in a
separate change.

Reviewed revision: `main` at `02cae08a1`.

Question from the owner: **is hxhx on the right path?** The owner asked for a
review of the whole architecture of `hxhx` and `reflaxe.ocaml`, the goals, and
the Beads plan, "very detailed, all aspects".

## 1. The short version

**Verdict: partly.** The destination is right and no rewrite is needed. The
current way of working does not converge on that destination.

What is right and stays:

- Upstream Haxe 4.3.7 as the behaviour oracle, clean-room provenance, and
  Haxe-authored compiler semantics.
- `reflaxe.ocaml` already compiles the whole `hxhx` compiler (about 210,000
  lines of Haxe) into OCaml that builds and runs. A build with upstream Haxe
  forbidden works from the committed snapshot in about two minutes.
- Honest readiness reporting, and the recent habit of small changes with
  fixtures compared against upstream.

What does not converge:

1. **Too many fronts for the state of the frontend.** Every `hxhx` goal needs a
   frontend at upstream parity. That frontend received about 10% of all authored
   change volume. Meanwhile 13 output surfaces, a plugin SDK, and customization
   work advanced in parallel.
2. **The compiler can succeed without understanding the program.** Typing is
   permissive unless `HXHX_TYPER_STRICT` is set. Unsupported expressions become
   `Opaque` nodes, and the Stage3 emitter turns them into `(Obj.magic 0)`.
   `reflaxe.ocaml` reports success when the generated OCaml fails to build.
3. **Three OCaml lowerings instead of one.** The old Stage3 emitter grew from
   9,840 to 22,212 lines after the July decision to retire it. The planned shared
   core supports four binary operators and cannot compile hello world from `hxhx`.
4. **No single owner for value conversions in `reflaxe.ocaml`.** 141 functions
   in 54 files decide conversions. This review reproduced silent wrong output.
5. **The checks that run do not test what will ship.** The costliest pull-request
   check emits the compiler's OCaml and does not compile it, so the #168 break went
   unnoticed for ten days. Several upstream gates have been red for months.
6. **Beads is a defect log, not a plan.** 426 beads are "in progress" with zero
   live leases. About 90% of them have landed commits on `main`. All 17 P0 beads
   have been idle for six to seventeen weeks.

The three changes for the next 90 days:

1. **Make `reflaxe.ocaml` sound, fast, and shippable first.** It is the first
   product and also the compiler that builds `hxhx`.
2. **Measure the `hxhx` frontend directly, then fix its foundations** on one
   output lane (JavaScript). Use a parse oracle and a typed oracle against
   upstream as the progress metric.
3. **One OCaml path and a process reset.** Freeze the Stage3 emitter and the
   shared fact schema. Triage Beads to a short critical path. Work on at most
   three fronts. Keep a shorter rule set. Do not leave a required check red for
   more than 14 days.

## 2. How this review was done

Three independent inputs, then verification:

| Input | What it did | Limits |
|---|---|---|
| Oracle (GPT-6 Pro, max reasoning, plan mode), request `orq_20261116T225347Z_c900e3d7` | Static review of a 5.6 MB bundle: `AGENTS.md`, `README.md`, all of `docs/00-project`, all compiler, macro-host and `reflaxe.ocaml` sources, the OCaml runtime, CI workflows, a metrics file, and all 805 open or in-progress beads. | Ran nothing. Test bodies, generated output, and CI logs were not in the bundle. |
| Fable (Claude Fable 5.2, max effort) | Live review of a clean worktree at `02cae08a1`. Measured code, history, CI runs, and Beads. Wrote 6 representation probes and 16 ordinary Haxe programs and ran them through `reflaxe.ocaml` and the `hxhx` lanes against upstream. | The machine was heavily loaded, so wall-clock numbers are upper bounds. The batteries are small; they show what breaks, not a pass rate. |
| Driving agent (Claude Opus 5.5) | Wrote a provisional conclusion before reading either review, then reconciled both at xhigh reasoning and re-checked the material claims on `main`. | Did not re-run every measurement. |

The two full reports, the probe programs, and the reproduction commands are kept
outside this repository on the owner's machine, in the review evidence folder
next to the review worktree. They are not committed because they contain
machine-specific paths. Section 7 gives the selected numbers.

Verified by the driving agent on `main` during reconciliation:

- `runtimegen/OcamlBuildRunner.hx:243-245`: without strict mode a failed `dune
  build` returns `Ok("dune build failed … (skipping)")`.
- `.github/workflows/ci.yml:1090-1101`: the self-compile job runs the emit with
  "no dune build".
- `target/OcamlTargetExpressionFact.hx`: four binary operators (`IntEqual`,
  `IntNotEqual`, `BooleanAnd`, `BooleanOr`). Last change under `target/`:
  2026-10-21.
- `TyperStage.hx:59-62`: strict typing depends on `HXHX_TYPER_STRICT`.
- `EmitterStage.hx:1855-1896`: unsupported expressions render as
  `(Obj.magic 0)`.
- `ast/OcamlBuilder.hx:6520-6526`: `Std.string` can emit the literal string
  `"<unsupported>"` into a running program.
- `InProcMacroSession.hx:79`: an unknown init macro returns `"ran:" + e`
  without running.
- `std/runtime/HxDynamicMethods.ml:109`: an unqualified `Option.bind`.
- Fable's probe B, re-run on `main`: `Null<Bool>` and `Null<Color>` values passed
  to `Dynamic` build and print `1`, `false`, and `1|1|s` where upstream prints
  `true`, `true`, and `true|Green|s`.
- `haxe_ocaml-anhiz`: on macOS, Haxe eval's `Process.exitCode()` throws for a
  child that a signal killed, which is a safe failure. The bead's Linux CI
  evidence shows exit 0 for the same kind of death, which is unsafe.

## 3. Where the two reviews agree

| # | Finding | Oracle | Fable | Status |
|---|---|---|---|---|
| A1 | Ship `reflaxe.ocaml` with upstream Haxe as the first product. Keep Full1 as the later compiler-equivalence claim. | Yes, high confidence | Yes, high | Owner decision D1 |
| A2 | The self-compile check must also compile the emitted OCaml, and the snapshot must regenerate from current sources automatically. | Yes | Yes (about 80 s on a 61-minute job) | Immediate action I1 |
| A3 | `reflaxe.ocaml` needs one typed conversion authority. A missing conversion must fail at compile time, not at OCaml build time or at run time. | Yes: complete the registry; a final verifier on lowered code | Yes: a `Repr` algebra, a total `coerce`, and abstract OCaml runtime types | Bug `haxe_ocaml-9cqxj`; design per section 5 |
| A4 | The `Obj.t` carrier itself is legitimate. Site-by-site conversion is the defect. | Yes | Yes | Settled |
| A5 | Converge on one OCaml lowering, and delete the Stage3 emitter after migration. Add no new semantics to it. | Yes | Yes | Freeze now (section 6) |
| A6 | Unsupported or mistyped programs must not produce a successful build. Strict checking must be the default, not an environment switch. | Yes, critical | Yes (types as strings, partial compatibility relation) | Track B |
| A7 | Macro parity needs `haxe.macro.Context` bound to the real typer (`haxe_ocaml-9sj5p.6`), then real init macros and hooks (`.7`), then `UnitBuilder.generateSpec` (`.8`). Several macro APIs are simulated today. | Yes | Yes | Critical path |
| A8 | The broad plugin SDK and customization platform are premature. | Defer the broad SDK | Defer all of it | Owner decision D4 |
| A9 | Beads is a usable inventory and not a plan. Unclaim stale claims, verify and close landed work, group under root epics, cap active work at three fronts. | Yes | Yes, with counts | Owner decision D6 |
| A10 | `AGENTS.md` should be much shorter, and each guard should earn its cost. Keep provenance, stage0-forbidden, and upstream-comparison checks. | Yes | Yes | Owner decision D7 |
| A11 | Parallelize investigations, but serialize changes to one semantic boundary. Large consolidation merges are a warning sign. | Yes | Yes | Owner decision D7 |
| A12 | No whole-compiler rewrite. | Yes | Yes | Settled |

## 4. Where they disagree, and the recommendation

| # | Question | Oracle | Fable | Recommendation |
|---|---|---|---|---|
| B1 | **What joins the two hosts to one OCaml lowering?** | Grow the existing shared core (`target/`). Do not make `hxhx` rebuild upstream's macro object graph. | Freeze `target/`. Use `haxe.macro.Type` typed AST, the interface every Reflaxe target already consumes. `hxhx` must produce these values anyway for `Context.getType` and `typeof`. | **Freeze `target/` now; choose after the typed oracle exists (milestone B1).** I lean toward Fable's interface: macro parity forces `hxhx` to produce `haxe.macro.Type` values, so the cost Oracle warns about is paid either way. `target/` has been idle for four weeks at four operators. |
| B2 | **What executes macros?** | Keep native macro plugins. Do not start an interpreter now. | A typed-tree interpreter written in Haxe as the general executor. Today each macro is compiled by the Stage3 emitter, the path both reviews want to delete. An interpreter also delivers `--interp` and `--run`, which Full1 requires. | **Do `9sj5p.6` first (both agree), then decide.** The dependency of macro plugins on the Stage3 emitter is a real conflict with freezing that emitter. It must be resolved before the hard cut. |
| B3 | **The October M22 native-compiler pilot** | Keep it, but only with one real workload, a deadline, and separate cost measurements. | Defer it. The measured pain (slow compiles) has a cheaper first fix: SHA-256 hashing and manifest writing take about two thirds of timed macro work in a hello-world compile. | **Defer**, and fix compile cost directly first (milestone A4). |
| B4 | **Non-JavaScript `hxhx` backends** | Keep Full1's obligations. Stop large simultaneous target campaigns. | Freeze C++, Cppia, HashLink, Neko, PHP, Lua, Python, Java, and C# until JavaScript parity (F2). | **Freeze new work; fix only regressions** until F2. Full1's definition stays unchanged. |
| B5 | **Frontend data models** | Keep the phases. Make checking mandatory. Attach facts to typed nodes instead of side catalogs. | Measure first. Then probably re-base the syntax tree and types on the public `haxe.macro` shapes: positions on every node, structured types instead of 400 hint re-parse sites, one directional `unify`. | **Measure first (milestone B1).** Decide between "evolve" and "re-base" from the oracle numbers. |
| B6 | **Signal deaths reported as exit 0 (`haxe_ocaml-anhiz`)** | Critical if confirmed. Put it near the top of the critical path. | Not covered. | **Raised to P1.** Partly confirmed: safe on macOS, unsafe evidence on Linux CI. |

## 5. Design direction for value conversions in `reflaxe.ocaml`

Both reviews reach the same rule from different directions. **Every place where a
value crosses from one representation to another goes through one function, and
that function either returns a conversion or stops the compile with a source
position.**

The combined design:

1. **One representation per value, total over Haxe types.** Extend the existing
   `OcamlRepresentationRegistry` instead of adding a second registry. It must
   answer "which carrier does this type use in this storage place" for every
   type, not only for an admitted list. A type parameter always uses the dynamic
   carrier.
2. **One conversion function.** `coerce(expr, from, to, pos)` is the identity
   when the two representations are equal. It is structural for functions: it
   converts arguments in one direction and the result in the other. It uses a
   table for primitive pairs. Any other pair is a positioned compile error, never
   `Obj.magic` and never a placeholder string.
3. **One entry point.** Every typed context calls `coerce`: call arguments,
   returns, assignments, field initializers, array and object literal elements,
   branch joins, captures, method values, and default arguments. At a generic call
   the expected type is the declared parameter type. The bound-method bug of
   PR #195 sits exactly at such a boundary.
4. **Let OCaml check it.** Abstract runtime types (`HxRepr.dyn`, `'a
   HxRepr.nullable`), defined in one runtime module with an `.mli` file, make a
   missing conversion an OCaml type error in every module. Today the checker sees
   `Obj.t` on both sides and accepts it. `Obj.magic` stays inside that runtime
   module only.
5. **A final verifier** on each lowered function checks that every producer and
   consumer edge has equal representations or an explicit conversion.

Measures of progress: functions that emit conversions (141 today, target 10 or
fewer), `Obj.magic` in the generated compiler (134,094 today), the pass rate of
a generated conformance matrix (about 15 value types by about 12 boundary kinds,
compared with `haxe --interp`), and zero `"<unsupported>"` literals.

## 6. Plan for the next 90 days

The days are counted from the day the owner accepts the plan (D0). Three tracks
run at once, and each track has one current outcome at a time.

### Immediate actions (week 1, no owner decision needed)

These fix verified defects or protect evidence. Both reviews support them.

| ID | Action | Bead |
|---|---|---|
| I1 | Land PR #195 (bound-method `Null<Enum>` fix). Regenerate the bootstrap snapshot and import it. Make the self-compile pull-request check also compile the emitted OCaml. | `haxe_ocaml-j091x` |
| I2 | Land PR #196 (a flaky guard that read an empty process-ID file). | `haxe_ocaml-ldyzi` |
| I3 | Make test observation fail closed when a signal kills the observed process. | `haxe_ocaml-anhiz` (P1) |
| I4 | Qualify `Stdlib.Option.bind` in `HxDynamicMethods.ml`. Today OCaml ExtLib's `Option` module shadows it, and the Gate 2 acceptance examples fail. | new, small |
| I5 | Repair or retire the daily stage0 source smoke. It has failed 119 times in a row (a 300-second fail-fast on an hour-long emit). | `haxe_ocaml-4wb9k` |

### Track A: `reflaxe.ocaml` sound, fast, and shippable

| Milestone | By | Content | Exit criteria |
|---|---|---|---|
| A1 | D+7 | I1 done. The snapshot regenerates automatically after merges that touch compiler sources, or a freshness check fails. | A deliberately wrong conversion on a test branch fails the pull-request check. The snapshot stays under 3 days old. |
| A2 | D+21 | Representation and `coerce` per section 5, with a test over the whole pair table. The conformance matrix runs in CI and includes Fable's probes A, B, C, and E. | The matrix runs on every `reflaxe.ocaml` change. A baseline pass rate is published. |
| A3 | D+50 | All emission sites go through the one entry point. The old helper functions are deleted in the same changes. A failed OCaml build is an error by default. | Functions that emit conversions: 10 or fewer. Matrix at 95% or more. No `"<unsupported>"` literal. |
| A4 | D+60 | Compile-cost budget: hashing and manifest writing only at artifact boundaries. The C++ backend builds as a separate unit. | Hello-world emit at 3 CPU-seconds or less (20.5 s today). `hxhx` self-compile at 15 minutes and 4 GB or less (61 minutes and 10 GB today). |
| A5 | D+90 | A corpus of 200 or more ordinary programs compared with upstream. A 1.0 release candidate for a declared scope, with unsupported features rejected at compile time with a position. | Corpus at 95% or more. No known silent wrong output. No OCaml type errors in generated code for accepted programs. |

Stop rule: at D+50, if more than 40 functions still emit conversions or the
matrix is below 80%, pause other `reflaxe.ocaml` work and review the design with
the owner.

### Track B: measure and fix the `hxhx` frontend, on one lane

| Milestone | By | Content | Exit criteria |
|---|---|---|---|
| B1 | D+14 | Parse oracle and typed oracle over the upstream standard library and `tests/unit`. Upstream Haxe is used only as a black box, which the provenance policy allows. Both numbers are reported on every pull request. | Two baseline numbers published. |
| B2 | D+21 | Owner decisions D3 and D5 (interface and data models), taken from the numbers. | Decisions recorded. |
| B3 | D+45 | Strict checking by default, with no `Opaque` or placeholder success. Type hints are parsed once into structured types. `hxhx` type-checks its own sources as a required check; generate the bundled-sources table instead of using a macro. | Parse oracle at 99% or more of files. Self-type-check green. |
| B4 | D+90 | One directional `unify`, and `Context` served from the typer (`9sj5p.6`). | Typed oracle at 50% or more of standard-library modules. Ordinary corpus on JavaScript at 70% or more. |

Stop rule: a parse oracle under 99% at D+45, or a typed oracle under 50% at
D+90, stops the re-base and returns the choice to the owner.

### Track C: one OCaml path and a process reset

| Milestone | By | Content | Exit criteria |
|---|---|---|---|
| C1 | D+3 | The stop list below is in force. | No merged change adds a `Stage3Ocaml*` file or a node kind under `target/`. |
| C2 | D+10 | Beads triage per section 8, after owner approval. | Fewer than 30 beads in progress, each with a live owner. Five or fewer P0 beads, each touched within 7 days. |
| C3 | D+14 | A short `AGENTS.md` that links to detailed policies. A pull-request loop of about 30 minutes. Each red required workflow is fixed or disabled with an owner and a re-enable condition. | Median green pull-request time 30 minutes or less. No workflow red for more than 14 days. |
| C4 | D+90 | A design note and a first proof that `reflaxe.ocaml` lowers a small program from `hxhx`'s typed output and matches upstream. | One program passes end to end through one lowering. |

### Stop list (from D0)

1. New semantics in `EmitterStage.hx` and `backend/ocaml/Stage3Ocaml*.hx`, except
   what keeps the existing macro-plugin path and bootstrap working.
2. New node kinds under `reflaxe.ocaml/…/target/`.
3. New feature work on non-JavaScript `hxhx` backends (regressions only).
4. The M22 pilot, the broad plugin SDK, customization, Haxe-family variations,
   and the Bend2-inspired dialect (it stays P3 research, as already decided).
5. New evidence machinery: receipts, collectors, ledgers, policy guards, and
   proof or digest records on individual lowering decisions.
6. Claiming a bead when it is created, and leaving landed work "in progress".
7. Large consolidation merges, unless the owner asks for one.
8. Closing a bead whose title promises more than its closing note delivers.
   Rename it to the delivered scope first.
9. Further whole-project reviews before the two oracle numbers exist.

## 7. Selected measurements

All are from Fable's review at `02cae08a1` unless marked. Fable's report gives
the method for each one.

| Measurement | Value |
|---|---|
| Authored Haxe | `hxhx-core` 184,200 lines; `reflaxe.ocaml` 110,895; tests 235,275 |
| `hxhx-core` backends | 103,512 lines (C++ 49,146; source targets 26,426; OCaml 11,516; JavaScript 8,148; Neko 7,107) |
| Change volume by area, whole history | frontend 9.8%, other backends 13.7%, `reflaxe.ocaml` 13.7%, tests 28.3%, docs 9.4%, CI and scripts 11.2% |
| Recent semantic change (2026-10-29 to 11-16) | frontend 42%, Stage3 OCaml emitter 38%, `reflaxe.ocaml` 14%, macros 6% |
| Stage3 OCaml path size | 9,840 lines on 2026-07-23; 22,212 lines on 2026-11-16 |
| Conversion sites in `reflaxe.ocaml` | 141 functions in 54 files; `Obj.magic` 134,094 times in the generated compiler |
| Ordinary programs through `reflaxe.ocaml` with upstream Haxe | 16 programs: 7 correct, 1 silent wrong output, 6 OCaml build failures (all with `haxe` exit 0), 2 compile-time stops |
| Representation probes | 6 probes: 1 correct, 2 OCaml type errors, 2 silent wrong outputs, 1 unsupported diagnostic |
| `hxhx` on the 16 programs, current `main` (JavaScript) | 5 correct; the typer rejects 6 valid programs |
| `hxhx` module-level parse of 300 random standard-library files | 295 accepted (98.3%); 5 crash |
| `hxhx` type-checking its own `Main.hx` | fails at `Main.hx:369` (`value loop requires a resolved iterator protocol`) |
| `reflaxe.ocaml` hello world, emit only | 20.5 CPU-seconds (upstream `--interp`: 0.19 s) |
| Where hello-world compile time goes | at least a quarter of CPU samples in interpreted bitwise operations (SHA-256); under 3% in typing |
| `hxhx` self-compile on CI | emit 3,681 s, peak 10.1 GB; everything after the emit 81 s |
| Gate history on `main` | Gate 1 Lite: last green 2026-09-14. Gate 1: last green 2026-07-21. Stage0 smoke: 119 consecutive failures. Full1 gate: never green. |
| Core CI | 37 jobs, 818 job-minutes per full run, median 104 minutes |
| Beads | 805 open or in progress; 426 in progress with 0 live leases; 382 with commit evidence on `main`; 17 P0, all idle since 2026-10-06 or earlier |
| Rule and doc volume | `AGENTS.md` 1,045 lines; 161 Markdown files with 45,779 lines under `docs/` |

One gate diagnosis worth recording: Gate 1 Lite, Gate 2 "runci Macro", and the
weekly macro parity job are red for **one** reason. `tests/unit/src/unit/TestMain.hx`
line 122 iterates the result of the `UnitBuilder.generateSpec` expression macro,
which `hxhx` does not execute. Gate 1 Lite was green before the iterator diagnostic
was added in October. **Inference:** it passed by typing an unknown iterable
permissively. The current red is the more honest state.

## 8. Beads triage proposal (needs owner approval)

**Caution:** another agent identity (`codex-continuation-agent`) holds 270 of
the in-progress beads, and a Codex session is active in the primary checkout. Bulk
changes must be coordinated with that work first.

| Action | Rule | Approximate count |
|---|---|---|
| Unclaim | Every in-progress bead without a live lease returns to open. From then on, a lease expired for 48 hours unclaims automatically. | 426 |
| Verify and close | In-progress beads with a commit on `main` and no update for 14 days: run the regression the bead names on current `main`. Green closes it with the commit. Red reopens it with one line that states the remaining difference. Run this as one batch job. | 330 |
| Re-open as unlanded | In-progress beads with no commit on `main`. | 44 |
| Convert, then close | Stage3 OCaml emitter beads: keep each reproducer as a conformance program and close the per-path record. | about 197 |
| Defer (P4) | Non-JavaScript backend, M22, SDK, customization, dialect, and server-reuse beads. | about 195 |
| Group | Remaining leaves become children of a few root epics (parser parity, types and `unify`, macros, `reflaxe.ocaml` conversions, JavaScript lane). | about 369 |
| Reset P0 | P0 means "on the critical path this month and touched this week". | 17 to 5 or fewer |

The counts overlap and come partly from keyword rules, so they are sizes, not
exact totals.

### Ordered critical path

| Order | Outcome | Bead(s) |
|---|---|---|
| 1 | Bootstrap fixed, snapshot imported, self-compile check compiles OCaml | `haxe_ocaml-j091x` and a successor |
| 2 | Test observation fails closed on signal deaths | `haxe_ocaml-anhiz` |
| 3 | Tests that CI never runs are reached | `haxe_ocaml-wis3l`, `haxe_ocaml-k86ww` |
| 4 | Typed conversion authority in `reflaxe.ocaml` | `haxe_ocaml-9cqxj`, `haxe_ocaml-0uwin` |
| 5 | `reflaxe.ocaml` compile-cost budget | `haxe_ocaml-xsg6m`, `haxe_ocaml-r49eq` |
| 6 | Version identity and first-release scope | `haxe_ocaml-ftrhr`, `haxe_ocaml-s7jry` |
| 7 | Parse oracle and typed oracle | new |
| 8 | Strict checking by default; no placeholder success | new epic |
| 9 | `hxhx` type-checks its own sources | new |
| 10 | Structured types and one `unify` | new epic |
| 11 | `Context` bound to the real typer | `haxe_ocaml-9sj5p.6` |
| 12 | Init macros and compiler hooks | `haxe_ocaml-9sj5p.7` |
| 13 | `UnitBuilder.generateSpec` executes; three red gates turn green | `haxe_ocaml-9sj5p.8` |
| 14 | `reflaxe.ocaml` 1.0 for a declared scope | `haxe_ocaml-s7jry` |
| 15 | Upstream unit suite green on JavaScript (F2) | `haxe.ocaml-f1cl.3`, re-scoped |
| 16 | One OCaml lowering; delete the Stage3 emitter and `target/` | `haxe_ocaml-38gsp.1`, re-scoped |
| 17 | Two native generations with stage0 forbidden (F3) | `haxe_ocaml-38gsp.2` |
| 18 | Further Full1 targets, one at a time | `haxe.ocaml-f1cl` |

## 9. Owner decisions

The owner answered on 2026-11-16. D0 for the plan in section 6 is 2026-11-16.

| ID | Decision | Outcome |
|---|---|---|
| D1 | First product: `reflaxe.ocaml` with upstream Haxe 4.3.7, for a declared scope. | **Accepted.** |
| D2 | Nearer finish lines for `hxhx`: F1 frontend parity (parse and typed oracles), F2 upstream unit suite on JavaScript, F3 two native generations with stage0 forbidden. Full1 stays the long-term contract, unchanged. | **Accepted.** |
| D3 | The interface between the hosts and the one OCaml lowering: `haxe.macro.Type` typed AST, or the `target/` fact schema. | **Open until milestone B2.** `target/` is frozen now (accepted). Recommendation: `haxe.macro.Type`. |
| D4 | Defer the M22 pilot, SDK, customization, and variations until F2; freeze new work on non-JavaScript `hxhx` backends; fix compile cost directly first. | **Accepted** ("defer all of it"). |
| D5 | Frontend data models: evolve or re-base on the `haxe.macro` shapes. | **Open until milestone B2.** |
| D6 | Beads triage per section 8, coordinated with the Codex agent's claims. | **Accepted.** |
| D7 | Process reset: a short `AGENTS.md`, small pull requests merged daily (no routine consolidations), the 14-day rule for red checks, and archiving the Full1 release-candidate machinery until F2. | **Accepted.** |
| D8 | Macro executor: native plugins or a typed-tree interpreter. | **Open until `9sj5p.6` lands.** The executor must not depend on the Stage3 emitter at the hard cut. |
| Freeze | No new semantics in the Stage3 OCaml emitter and no new node kinds under `target/`, except fixes that keep the bootstrap and the macro-plugin path working. | **Accepted** ("freeze both"). |

## 10. What would change this verdict

- The typed oracle shows 60% or more of standard-library modules already
  identical. Then "evolve" is enough, and the frontend gap is smaller than
  measured here.
- The `target/` fact schema covers arithmetic, fields, construction, loops,
  closures, and instance calls within four weeks and compiles a 5,000-line program
  from both hosts. Then it is a credible unifier.
- The conformance matrix passes above 95% without a conversion authority. Then
  the conversion class is rarer than the probes suggest. Five of six probes failed.
- Verification of the stale in-progress beads closes fewer than 30% of them. Then
  the backlog is real unfinished work.
- A user needs a non-JavaScript `hxhx` target now. Then that one target joins F2.

README readiness bars are unchanged by this record. The goals and README framing
for D1, D2, and D4 change in a separate pull request.
