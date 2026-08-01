# Testing product-surface scorecards

These scorecards prevent a passing test in one part of the repository from
being reported as proof for a different product. For example, a successful
`hxhx` bootstrap says that one compiler stage can run; it does not prove that
the standalone Haxe-to-OCaml target passes the official Haxe target suite.

A **product surface** is one independently useful thing a user can rely on. A
**scorecard** names the claim for that surface, the tests that observe it, and
the remaining gaps. The checked source of truth is
[`TESTING_PRODUCT_SURFACES.json`](./TESTING_PRODUCT_SURFACES.json). CI rejects
missing surfaces, unclassified examples, and QA routing rules that do not name
their semantic owner—the part of the system whose behavior the rule protects.

## Current scorecards

| Surface ID | What a passing result may support | Current state | It must not borrow |
| --- | --- | --- | --- |
| `reflaxe-ocaml-backend` | Haxe source is lowered to buildable OCaml with the expected runtime behavior. This is the only scorecard that may use official Haxe target qualification. | Partial | `hxhx` bootstrap, plugin loading, or an example on a different route. |
| `ocaml-native-runtime` | Declared `ocaml.*` libraries and repository runtime modules behave as documented. | Partial | General backend conformance or compiler bootstrap success. |
| `hxhx-compiler-bootstrap` | The `hxhx` parser, typer, macro, server, target, plugin, and bootstrap paths perform the behavior named by their tests. | Partial | Standalone target qualification or reproducibility that was not compared. |
| `bootstrap-reproducibility` | Successive compiler stages have the declared semantic and normalized-artifact relationship. | Experimental | A final executable that ran without comparing the earlier stages. |
| `package-downstream-examples` | Each maintained example performs the compile, build, or run behavior stated by its tier and command. | Partial | Any broader backend, runtime, or bootstrap claim not exercised by that example. |

The JSON scorecard lists the focused owner, real vertical path, full backstop,
latest retained proof, and open risks for each row. A green command advances
only the rows named by that command's evidence record.

On 2026-07-31, `npm run test:examples` built and ran the evaluated OCaml
examples it reached, then stopped in `hxhx-target-ocaml-stage3` on a typed-local
declaration replay mismatch in `haxe.EntryPoint`. The failure belongs to the
`hxhx-compiler-bootstrap`/Stage3 route. It does not invalidate the earlier
standalone example results, and those earlier results do not make the whole
example scorecard green. Bead `haxe_ocaml-7qbih` owns the focused regression
and fix.

## Bootstrap stages and independent oracles

Bootstrap asks whether a compiler can produce and agree with a successor. Each
stage therefore has a separate scorecard:

| Stage | Plain meaning | Protected claim | Independent oracle |
| --- | --- | --- | --- |
| `stage0` | The already-installed upstream Haxe compiler used to start the build. | Its exact identity and accepted behavior are known. It is an input, not evidence that `hxhx` implemented anything. | Pinned upstream Haxe 4.3.7 identity and upstream behavior/suite results. |
| `stage1` | The first native `hxhx` executable built using stage0. | It completes only the explicitly named stage0-forbidden workflows. | Upstream accepted behavior plus manually authored command, diagnostic, and runtime expectations. |
| `stage2` | The successor compiler built by stage1. | It agrees with stage1 on declared observable behavior and normalized stable artifacts. | Semantic command/output comparison plus the explicitly declared stable generated-source inventory. |

The comparison ignores allowed nondeterminism such as timings, temporary
paths, Dune build metadata, process IDs, and native linker output bytes. Byte
comparison is used only where byte identity is the actual contract. The
current `stage2-repro` check deliberately hashes its stable generated `.ml`
set, but that narrow shim-era check does not claim reproducible executables or
complete two-generation native self-promotion.

Two architecture-level tracer bullets remain distinct:

1. Haxe input → standalone `reflaxe.ocaml` → Dune build → executable behavior.
2. Bootstrap input → next-stage `hxhx` compiler → semantic and normalized
   artifact comparison with the preceding stage.

One cannot replace the other.

## Example tiers

Examples use one of three tiers:

- `flagship-application`: a representative application through its complete
  advertised build and runtime boundary;
- `capability-showcase`: a narrow real feature path, compiled and run when it
  claims runtime behavior; or
- `compile-only-snippet`: a source-shape example that claims only successful
  compilation.

The current checked inventory contains capability showcases and no qualified
flagship application. This is an honest gap, not a reason to relabel a small
fixture. The example guard verifies that every maintained example has a tier,
product surface, claim, and executable command.

## Representative behavior-first dry run

Bead `haxe_ocaml-w32h3.17` is the retained real regression used to exercise the
workflow rather than inventing a process-only code change.

- **Scenario:** portable evidence fixtures should reach the validator they say
  they test after direct enum throws joined the control model.
- **Red evidence:** generated programs built and ran, but focused fixture
  checks failed for the intended contract gap: stale schema 43 versus 47,
  overly broad runtime-reason counting, and corruption fixtures that stopped
  at an outer digest mismatch.
- **Independent oracle:** the reviewed lowering-report schema and validator
  ownership, not values regenerated by the failing fixture.
- **Lowest faithful test:** focused report/inspector fixtures diagnose each
  contract. The portable build-and-run corpus remains the vertical proof—the
  **double lock** that keeps the real Haxe → OCaml → Dune → executable boundary.
- **Status:** open. This strategy work records the scenario and ownership; it
  does not pretend the semantic regression is fixed.

## High-risk review rule

Compiler representation, runtime, ABI, package publication, security,
migration, and public-claim changes need a review pass distinct from the
implementation pass. The reviewer must challenge oracle independence,
negative cases, mocked boundaries, affected-test selection, cross-scorecard
claim leakage, and any claim broader than the executed observer. The active
Bead records the findings and dispositions; a green CI summary alone is not a
completion argument.

## 2026-07-31 convergence audit

The consolidated-testing v3 delta was applied only where the repository had a
real gap. Existing infrastructure was preserved.

| Conclusion | Before this change | Disposition |
| --- | --- | --- |
| Behavior scenarios and pre-fix red evidence | Partial and scattered across Beads. | Added the durable workflow and one real regression dry run. |
| Independent oracle/provenance | Strong upstream/provenance policy, but not a routine test-authoring step. | Added an explicit required step; no implementation-generated answer is accepted as its own oracle. |
| Tracer bullet and lowest faithful layer | Used in practice but not named as a contract. | Added two architecture tracer bullets and the focused-plus-real-boundary double lock. |
| Product-surface scorecards | Absent. | Added five independently checked surfaces plus separate stage0/stage1/stage2 records. |
| Executable example tiers | Examples built and ran, but their claims were not machine classified. | Classified all maintained examples; no flagship label was invented. |
| R0–R5 feedback rings and affected routing | Already implemented with fail-safe full backstops. | Preserved; rules now also report semantic owners and product surfaces without changing their tier. |
| Flake, retry, quarantine, cache, and release evidence | Already governed by existing policies and exact-candidate receipts. | Preserved; no duplicate policy or new test volume was added. |
| High-risk independent review | Already required through thinking labels and second-pass rules. | Connected explicitly to test sensitivity and cross-scorecard claim review. |

The new scorecard guard measured 0.22 seconds cold and 0.20 seconds warm on
this checkout. The existing example-coverage guard measured 0.23 seconds
before and 0.13 seconds after; QA routing measured 1.38 seconds before and 1.16
seconds after. Those sub-second differences are ordinary measurement noise.
The important result is that the PR topology, full backstops, and previously
reported required-tests critical path (45m10s before the earlier consolidation,
23m21s after it) did not change.
