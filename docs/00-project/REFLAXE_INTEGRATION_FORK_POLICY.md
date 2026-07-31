# Reflaxe Integration Fork Policy

## Outcome

This project maintains `fullofcaffeine/reflaxe` as its Reflaxe integration
fork. The fork can improve and extend the framework, but every change remains
reviewable, target-neutral, reproducible, and compatible with the wider
Reflaxe compiler family.

For now, framework pull requests are opened only against the fork. Do not open
or update pull requests in `SomeRanDev/reflaxe` unless the product owner changes
that policy.

`reflaxe.ocaml` and `hxhx` are important integration clients, not the semantic
owners of Reflaxe. An incident in either project may reveal a framework defect
and provide end-to-end evidence. The resulting framework API or fix must not
contain OCaml-specific types, helper names, representation choices, target
policies, or lifecycle assumptions.

## Repositories And Branch Ownership

| Role | Repository | Contract |
| --- | --- | --- |
| Upstream observation | `SomeRanDev/reflaxe` | Read and periodically synchronize; no PRs for now. |
| Maintained fork | `fullofcaffeine/reflaxe` | All framework branches, PRs, releases, and fork CI. |
| Integration consumer | `fullofcaffeine/hxhx` / this checkout | Pins an immutable reviewed fork commit and content digest. |

Never write through a shared sibling checkout. Use a clean Reflaxe worktree and
task branch, preserve the primary checkout state, push only the task branch,
and land through a fork PR.

## Upstream Synchronization

Check upstream:

- before beginning any Reflaxe fork change;
- before advancing the Reflaxe commit pinned by this repository;
- before a fork release or package evidence run;
- at least weekly while the fork is active.

Record the live upstream and fork `main` commit IDs. When they differ:

1. create a `sync/upstream-YYYYMMDD` branch from fork `main`;
2. incorporate the upstream commits without rewriting fork `main` history;
3. inventory upstream changes and identify overlaps with the fork delta;
4. resolve conflicts according to documented behavior, not merely textual
   convenience;
5. open a fork PR describing the old fork base, new upstream base, conflicts,
   resolutions, behavior risks, and exact tests;
6. run the Reflaxe suite plus risk-routed compatibility clients;
7. merge only after the fork PR has visible passing evidence.

A fast-forwardable history is helpful but not sufficient. A successful Git
merge does not prove compiler behavior or API compatibility.

## Required Pull-Request Record

Every change, including maintenance and CI changes, gets its own fork PR. The
body starts with explicit **Why**, **What**, and **How** sections, then records:

1. **Outcome:** what a Reflaxe compiler author can now rely on.
2. **Problem:** concrete old behavior and why it was wrong or limiting.
3. **Context:** the incident, request, or Bead that exposed the need.
4. **Design:** why this framework seam is the correct owner.
5. **Upstream relationship:** whether upstream lacks, differs from, or has
   since superseded the change.
6. **Family compatibility:** why the change is target-neutral and how existing
   Reflaxe compilers remain valid or migrate deliberately.
7. **Behavior changes:** generated output, lifecycle, API, diagnostics, cache,
   or performance differences that reviewers should expect.
8. **Verification:** exact Haxe versions, Reflaxe tests, compatibility clients,
   negative tests, and CI run links.
9. **Risks and rollback:** known hazards and the last known-good fork commit.
10. **Deferred scope:** what the PR intentionally does not claim.

Every behavior-changing PR also includes:

- a minimal Haxe snippet that reproduces the old behavior;
- before/after generated snippets for each target language used as compatibility
  evidence, with simplified examples labeled as such;
- the exact diagnostic and compiler phase when the old path fails before any
  target source can be emitted, instead of an invented target-language result.

The snippets are review evidence, not decoration: they should make the source
semantic contract and the practical generated-code consequence understandable
without requiring the reviewer to reconstruct either from internal Haxe AST
names.

The commit and PR body include this provenance form, specialized to the actual
incident:

```text
hxhx-agent created this because <plain-language incident and reason>.
```

Do not use a PR description that is only a filename list. The practical old
and new behavior comes first; internal names support that explanation.

### Plain-language review contract

Write for a Haxe developer who understands ordinary application code but has
not studied Reflaxe's internals. A technically correct phrase is not sufficient
when its meaning depends on local context.

- Define compiler-specific terms on first use, even when the individual words
  look familiar. For example, a **semantic decision** is a decision about what
  the Haxe program does, such as evaluation order or the value returned by
  postfix `++`. A **semantic artifact** is a stored record of that decision,
  such as metadata on a typed expression or a validated lowering plan.
- Explain a **preprocessor** as a compiler step that rewrites already
  type-checked Haxe expressions before target code is generated. Explain a
  **body revision** as an identity for one exact version of a function body,
  used to reject a plan built for older code.
- Expand compound shorthand into ordered actions. Do not write phrases such as
  "atomic early-protection/final-plan cutover" without saying that the target
  first marks the vulnerable expression, lets declared generic rewrites run,
  builds and validates the final target plan, switches generation to that plan,
  and removes the previous competing route in the same reviewed change.
- Use a before/problem/after example and connect Haxe source to real generated
  target code or to the real pre-emission diagnostic. Do not invent target code
  when compilation stopped earlier.
- Link a useful reference: the relevant public Haxe API, the Reflaxe source
  contract, an architecture document, or a focused test. Internal type and pass
  names belong after the plain-language model, not in place of it.

The first-read test is simple: a capable Haxe developer new to this repository
must understand why the change matters and what will behave differently before
they need to follow an internal symbol link.

## Framework Neutrality

Fork changes may introduce stronger lifecycle, identity, traversal, plugin,
diagnostic, caching, and validation facilities. They should benefit any
Reflaxe target that needs the capability.

The following are prohibited in the generic framework:

- `reflaxe.ocaml` metadata names or carrier rules;
- OCaml AST, runtime, module, representation, or ABI policy;
- `hxhx` private compiler objects or target-specific semantic decisions;
- a fallback that silently changes one target's language behavior;
- an API whose only meaningful implementation is one target's workaround.

Target-specific policy stays in its target repository. When one target is the
only initial client, the fork PR must still use a target-neutral vocabulary,
include generic framework tests, and state the reuse contract for other
targets.

## Verification Tiers

Use the narrowest tier that proves the change, then broaden according to risk:

1. **Framework unit/regression:** required for every behavior change.
2. **Reflaxe test compiler:** required for framework API and preprocessing
   changes on the declared Haxe matrix.
3. **Family compatibility client:** required when an API, typed-expression
   lifecycle, traversal, cache, or generated shape changes.
4. **`reflaxe.ocaml` canary:** required when that target exposed the incident;
   keep it focused during ordinary iteration.
5. **Heavy `hxhx` or package E2E:** reserved for pin advances, bootstrap/plugin
   integration, release candidates, and other critical lifecycle boundaries.

The heavy clients are high-value QA, not per-commit unit tests. Their cost must
not turn routine Reflaxe development into a full `hxhx` rebuild.

CI must show a scheduled run and its conclusion. No run, a skipped required
job, or an unapproved workflow is not green evidence. The fork keeps an
explicit manual-dispatch route for recovery and provenance checks.

## Pinning, Delta Inventory, And Rollback

This repository records:

- the exact fork commit;
- a path-independent SHA-256 digest of the downloaded Reflaxe source tree;
- the resolved provider and classpath;
- whether required framework capabilities are present;
- the Reflaxe identity in package/CI receipts.

Version text such as `4.0.0-beta` is descriptive, not an immutable identity.
The Git commit and content digest are the lock.

Maintain a fork-delta inventory through merged fork PRs and periodic sync PRs.
Before advancing the consumer pin, identify the last known-good pin and retain
enough evidence to restore it. Rollback changes the immutable pin and digest in
one reviewed slice; it never silently falls back to a local Haxelib cache.

## Current Baseline

On 2026-07-20, upstream and fork `main` were first synchronized at
`73a983112e039daad46b37912ab238df6bf0cf53`. The fork then merged:

- fork PR #1: lazy function field type resolution;
- fork PR #2: sound side-effect, `continue`, and semantic-envelope preservation
  in pure-expression cleanup.

The fork then merged PR #3 to preserve nested block results. The hxhx consumer
remains intentionally pinned to that behavior baseline,
`bfadffb8926e378a4ce8be4b5f66e53b2a9af216`, with content digest
`c8c6e9ee2eaa5e4df27a0bd5d3a4e0190befb36677b3a5390470bb8c14368a44`.
The complete `reflaxe.ocaml` portable corpus and hosted Linux/macOS package
matrix passed on those exact framework bytes.

Fork governance then advanced independently:

- PR #4 restored PR/main/manual test evidence, made generated-project jobs test
  the checked-out fork, and made typed optimizer assertions legal on both old
  and latest Haxe;
- PR #5 made Haxelib publication manual and explicitly confirmed;
- PR #6 made the not-yet-enabled fork Pages deployment manual and explicitly
  confirmed;
- PR #7 added the fork-native evidence template required for future PRs.

The fork then added target-neutral lifecycle and scalability repairs:

- PR #8 introduced revisioned function-body input and explicit contracts for
  compiler steps that preserve, replace, or invalidate target-owned analysis;
- PR #9 rewrote the fork's change-record guidance for capable newcomers;
- PR #10 avoided recalculating complete function-body fingerprints after every
  compiler step when the body had not changed;
- PR #12 kept those fingerprints stable when unrelated compiler work changed
  process-wide local-variable numbers; and
- PR #13 made pure-expression cleanup use an explicit work list, so a generated
  function with tens of thousands of sequential expressions no longer exhausts
  the host call stack;
- PR #14 gave locals deterministic lexical identities across clean and warm
  Haxe requests;
- PR #15 made every target callback receive the complete current program; and
- PR #16 added opt-in, target-neutral publication of one validated generated
  directory instead of exposing files while generation is still fallible; and
- PR #17 added an explicit target hook after that directory becomes public, so
  external builders never have to infer lifecycle order from global Haxe
  callback registration; and
- the target-reuse fingerprint candidate records the final target-selected
  program as immutable plain-value revisions, gives targets an exact
  fail-closed reuse probe, and introduces a miss-only preparation hook without
  skipping any target work; and
- the target-reuse catalog candidate adds one bounded process-local owner in
  the reusable macro-interpreter realm, with copied opaque bytes, leases,
  least-recently-used eviction, reset, quarantine, and redacted counters. It
  does not yet authorize a target cache hit.

As of 2026-07-31, upstream `SomeRanDev/reflaxe` remains at
`73a983112e039daad46b37912ab238df6bf0cf53` and fork `main` remains at
`6922422448a5a0c1f8249f0682ecd4b239ebf325`. The `hxhx` consumer pins stacked
candidate fork commit `105957964cdfe958f3f14bfee64b395e69dd253f`, published on branch
`hxhx-agent/target-reuse-fingerprint`, with
path-independent content digest
`3bc59e3304d5fa5486bd2b26098c809192c2d68def1ba648c84ad0df93611020`.
The last repository-validated rollback pin is
`e833fec65203964d40287483e6f951d6bbaf949d` with digest
`58cc28d20249b7f9d64b4090e41d4dd1fc2da8103f25b21311b9532564e36712`;
restoring both values together is the bounded rollback.

Fork PR #19 makes Haxe 4.3.7's all-null abstract resolve-hook placeholder an
explicit fingerprint fact. A missing hook, the exact host placeholder, and a
normal field now produce different identities. Any partially populated field,
or the placeholder in an operator/cast slot, blocks target reuse instead of
authorizing an incomplete key. The fingerprint schema advanced so cache entries
made before this distinction cannot match the new interpretation.

Fork PR #20 handles a separate Haxe 4 compiler-server limitation. A class
annotated with `@:rtti` can receive a different compiler-generated `__rtti`
string on a repeated unchanged request. Because that string changes generated
target files, Reflaxe now marks the request ineligible for exact target replay
and reports the specific source-authority blocker. Compilation still proceeds
normally; only reuse of an older generated bundle is forbidden.

PR #17 removes a package-only lifecycle race. Repository-local builds loaded
the Reflaxe framework before the OCaml target, but installed Haxelib builds
could register those callbacks in the opposite order. The target's extra
`onAfterGenerate` callback could therefore run before source publication and
observe no pending native build. `BaseCompiler.onOutputPublished()` now runs
directly after the framework commits the complete tree. `reflaxe.ocaml`
overrides that hook to start Dune from the stable public root; it no longer
depends on process-global callback order. The fork regression proves the hook
sees the public path and leaves generated files unchanged.

The pinned stack also preserves an earlier local declaration when the
program reads that value before assigning the local again. This includes reads
inside another variable's initializer and inside a nested block. Without that
check, the target-neutral cleanup could turn this valid sequence:

```haxe
var value:Null<Int> = null;
var rendered = Std.string(value);
value = 1;
```

into a target program that still read `value` for `rendered` but no longer
defined its initial `null` value. The fork regression covers both lexical
shapes, and the `null_primitives` portable fixture proves the initial nullable
values and later assignments compile, build, and run through OCaml.

The previous pinned patch prevents Reflaxe's generic alias-removal pass from replacing a
reference snapshot with a local that can later point at a different object. For
example, `var alias = values; values = replacement;` keeps `alias` bound to the
original array. Direct-write analysis uses typed local identities across the
whole function; element and field mutation still permit the existing
optimization because they do not redirect a local binding.

That patch has a repository-owned review record in `haxe_ocaml-9bome.4`, passes
the fork's macro, program-revision, server-revision, and runtime-build checks,
and passes the complete 76-fixture `reflaxe.ocaml` portable corpus. It is pinned
by immutable commit and digest while the fork pull-request lifecycle remains
separate; the branch name is only a discovery aid and does not participate in
dependency identity.

PR #14 makes local-variable evidence stable across clean Haxe processes. Haxe's
macro API gives each typed local a temporary numeric ID; unrelated compiler
work can change that number without changing the user's program. Reflaxe now
replaces the number with a function-owned lexical identity before computing
function revisions or publishing target plans. It also validates the complete
versioned identity shape, so a target cannot accidentally publish a numeric host
ID converted to text.

The pinned PR #14 candidate passes the fork's semantic lifecycle and
cross-request program-revision checks plus reflaxe.ocaml's focused storage,
representation, call, and generated-program checks. Its remote review remains a
separate prerequisite; this pin supplies exact integration evidence and does
not claim that the fork change is merged upstream.

PR #15 fixes the next warm-server correctness boundary. Haxe's compilation
server may reuse most typed modules, but a target still needs the complete
current program. Reflaxe now captures Haxe's complete declaration list, waits
until Haxe has finished DCE and body rewrites, and then regenerates one complete
target program. The older rebuilt-class filter and partial output manifest are
gone. The capture also restores source declaration order within each Haxe
module because the complete callback can otherwise present secondary types in
a different order from the earlier typed-module callback. This preserves
upstream Haxe's front-end reuse and the target's fail-closed storage checks
without claiming target-level delta generation.

The PR #15 framework regression compares complete target trees across a clean
process, a cold server request, an unchanged warm request, a body edit, and an
A → B → A restoration. It is target-neutral and intentionally leaves
add/delete/move/shadow cases, private output transactions, compiler-scale
timing, and supported default enablement to `haxe_ocaml-850ii.33`.

PR #16 closes the next failure boundary. A target that owns its complete output
directory can generate into a private sibling, finish target-specific work, and
publish only after Reflaxe validates the typed `_GeneratedFiles.json` receipt.
An ordinary failure discards the candidate and keeps the previous public tree.
Recognizable interruptions before and after each directory move are recovered;
malformed, foreign, or ambiguous marker state fails closed.

The final PR #16 candidate also cleans up private state when transaction
initialization itself fails before the first marker is durable. Transactional
write paths reject both slash and backslash parent traversal, so a target
cannot escape the directory it asked Reflaxe to publish on either path style.

The standalone OCaml target first enabled this only for the focused server
experiment. The package one-shot and watch routes now use the same transaction:
after Reflaxe publishes the complete generated directory, a later target
callback runs Dune against that public path. Dune owns reusable state in the
stable sibling `.<output>.reflaxe-ocaml-dune-build`, so source replacement does
not discard native artifacts or leak a candidate path into Dune metadata.
Transactional inferred-`.mli` generation remains rejected until interfaces can
be produced without mutating source after publication.

The earlier fork changes through PR #13 each landed through their own reviewed
pull request. PR #13's six required checks passed, and that framework baseline
was used for a successful current-source hxhx build and its focused
stage0-forbidden upstream macro workload. Ordinary fork pushes still schedule
no Haxelib publication or Pages deployment.

This policy changes dependency governance, not product readiness. README Goals
and North Star progress remain unchanged until supported behavior and release
evidence materially improve.
