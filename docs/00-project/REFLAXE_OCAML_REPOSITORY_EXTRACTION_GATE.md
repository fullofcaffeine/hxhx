# `reflaxe.ocaml` Repository Extraction Gate

Status: accepted planning decision on 2026-07-18

Owner: `haxe_ocaml-ipm6h`

Future rehearsal owner: `haxe_ocaml-ko5le`

Related product owners: `haxe_ocaml-s7jry`, `haxe_ocaml-38gsp`,
`haxe_ocaml-bomhr`, and `haxe_ocaml-850ii`

This document decides when `reflaxe.ocaml` should move from this monorepo into
its own repository and how `hxhx` should continue testing it afterward. It is a
repository and release boundary decision, not a claim that either product is
more production-ready today.

## Decision

Keep `reflaxe.ocaml` in this monorepo for now, while preparing it for a clean
future extraction.

Perform the physical split only when:

1. every extraction-readiness gate in this document is green; and
2. at least one measured product or maintenance trigger shows that separate
   repositories now cost less than continued monorepo coordination.

After the split, `hxhx` remains a first-class downstream QA and end-to-end
consumer of `reflaxe.ocaml`. It consumes immutable, versioned artifacts by
exact identity. It does not become the only correctness proof or force every
small `reflaxe.ocaml` change through the full `hxhx` release suite.

This is the current state:

```text
PREPARE_FOR_EXTRACTION; DO_NOT_SPLIT_YET
```

An arbitrary calendar date, a version number, or `hxhx` Full 1.0 completion by
itself is not an extraction trigger.

## Why `hxhx` should remain a downstream QA workload

Compiling and running `hxhx` exercises unusually demanding target behavior:

- a large Haxe-authored compiler codebase;
- complex generated OCaml and target runtime use;
- native bootstrap and stage0-free rebuilds;
- the native macro host;
- plugin and builtin target packaging;
- compiler-server lifecycle and process cleanup;
- incremental build, cache, and developer-loop performance.

That makes `hxhx` one of the best real-world stress tests for
`reflaxe.ocaml`. A regression that does not appear in a tiny example may still
surface while compiling the compiler, loading a plugin, or rebuilding the
macro host.

It is not sufficient on its own. Standalone target correctness must still be
proved with stock Haxe 4.3.7, focused target/runtime tests, public examples,
clean package installation, supported-host evidence, and upstream behavior
oracles where parity matters. `hxhx` tests a major consumer; it does not define
all valid Haxe programs or every supported `reflaxe.ocaml` use case.

## Current coupling that makes an immediate split premature

The standalone package boundary is already real: this repository builds a
deterministic source ZIP, installs it in a disposable haxelib repository, and
proves the same artifact on Ubuntu and macOS. That is important extraction
preparation.

The source tree still has material cross-package coupling, however. The
2026-07-18 audit found these categories:

| Coupling | Current example | Required extraction outcome |
| --- | --- | --- |
| Package resolution | `haxe_libraries/reflaxe.ocaml.hxml` points directly at `packages/reflaxe.ocaml` | Release and candidate lanes resolve an installed artifact; a sibling-checkout override remains an explicit local convenience only. |
| Bootstrap builds | `hxhx` and the macro host build through `-lib reflaxe.ocaml`; regeneration fingerprints package source and runtime trees | Bootstrap inputs name an exact package or artifact digest and remain reproducible without a `reflaxe.ocaml` source directory beside `hxhx`. |
| Runtime and native host seams | `hxhx` host declarations are implemented by OCaml runtime modules currently stored under `packages/reflaxe.ocaml/std/runtime` | Every cross-repository runtime/host ABI has one declared owner, a version, compatibility checks, and independent tests. |
| Native OCaml emission | `hxhx-core` can copy or locate the in-tree OCaml runtime | Emission receives a resolved runtime artifact or installation root; it does not discover another repository by relative path. |
| Distribution assembly | the `hxhx` distribution currently copies `reflaxe.ocaml` source from this checkout | A distribution embeds an exact released package with version, digest, license, and provenance metadata. |
| Tests and examples | root scripts jointly inventory and execute `reflaxe.ocaml` and `hxhx` examples | Each repository owns a complete local test inventory; cross-product tests consume published candidate artifacts. |
| Release/version automation | root and package versions are currently synchronized and release scripts live together | `reflaxe.ocaml` owns its release version, changelog, package build, signing/provenance, and rollback independently. |
| Native plugin/target contracts | M22 plans one stock-Haxe/`hxhx` plugin ABI and reusable target core | Each shared schema or ABI has exactly one versioned source of truth and generated or packaged consumers, not two handwritten copies. |

These links are not all architectural defects. Direct workspace paths are fast
and convenient while both products change together. They become defects only
if a claimed independent release or cross-repository proof still depends on
them.

## Required extraction gates

All gates below must pass on one recorded extraction candidate.

### E1. Standalone product ownership

The future `reflaxe.ocaml` repository can, from a clean clone:

- install its declared Haxe, Reflaxe, OCaml, Dune, and test dependencies;
- run focused compiler, runtime, stdlib, example, formatting, and documentation
  checks;
- build the release-shaped haxelib package reproducibly;
- install, compile, native-build, and run an external application with stock
  Haxe 4.3.7;
- produce the declared supported-host and performance evidence; and
- explain unsupported surfaces without linking readers back to required
  monorepo-only files.

The existing package-install matrix is strong partial evidence, not the whole
gate: its scripts, workflow, version, and product documentation still live in
the combined repository.

### E2. One-way product dependency

`reflaxe.ocaml` does not import `hxhx` parser, resolver, typer, macro lifecycle,
diagnostic, or private backend records. Host-specific adapters may implement a
published contract at the edge, but the target and runtime remain independently
usable with stock Haxe.

`hxhx` may depend on a released or candidate `reflaxe.ocaml` artifact for
bootstrap, native compilation, target promotion, or distribution assembly.
That direction is expected. It must be explicit and pinned.

### E3. Versioned cross-repository contracts

Every boundary actually used across the split has:

- a named owner;
- a semantic version or schema/ABI version;
- machine-readable compatibility metadata;
- deterministic unsupported-version diagnostics;
- a conformance fixture on both sides; and
- a migration rule under the repository hard-cutover policy.

This includes the source package shape, runtime bundle identity, native host
ABIs, plugin manifest and payload identity, backend program/facts schema when
applicable, and toolchain fingerprints. M22 decides the final home of its
shared plugin ABI; extraction must not create duplicate handwritten owners in
the meantime.

### E4. Artifact-mode `hxhx` consumption

A required `hxhx` compatibility lane must work from a checkout that does not
contain `packages/reflaxe.ocaml`. It must download or install one immutable
candidate, verify its digest and provenance, and use that same artifact for
the selected bootstrap, runtime, plugin, or target workload.

Local sibling-checkout development may remain available for speed, but it is
an explicit override and never release evidence. CI must be able to detect and
reject accidental resolution from a neighboring checkout or `haxelib dev`.

### E5. Independent release and rollback

`reflaxe.ocaml` owns its version, release notes, support matrix, artifacts,
provenance, and publication permissions. A `reflaxe.ocaml` release does not
publish `hxhx`, and an `hxhx` release does not silently construct an unreleased
target package from source.

`hxhx` records an exact accepted `reflaxe.ocaml` version and digest. Rollback is
a reviewed pin change to the last green immutable artifact, not a copied source
patch or rewritten release tag.

### E6. Coordinated-change rehearsal

Before the physical split, perform at least one two-repository rehearsal:

1. build an immutable `reflaxe.ocaml` candidate with source and artifact
   digests;
2. validate it in the standalone matrix;
3. run the focused `hxhx` contract lane against that exact candidate;
4. run the broader release-candidate E2E tier when the changed surface requires
   it;
5. produce a machine-readable compatibility receipt; and
6. prove that `hxhx` can repin the prior artifact if the candidate is rejected.

Breaking changes do not require a permanent compatibility layer. The producer
publishes an immutable candidate, paired changes validate against it, and each
consumer hard-cuts its pin only after the pair is green. Old released artifacts
remain available for rollback.

### E7. Independent developer experience

Normal `reflaxe.ocaml` target work must not require rebuilding `hxhx`. The
future repository provides focused watch/build/test commands, cache identity,
generated-OCaml inspection, cleanup, and phase timings.

Normal `hxhx` compiler work must not fetch a moving `reflaxe.ocaml` branch. It
uses the lock or an explicit candidate override. A documented paired-checkout
workflow may optimize coordinated development without becoming a hidden
correctness dependency.

Measure the representative loops before and after a split rehearsal. Do not
accept a repository boundary that makes common work materially slower without
a justified ownership or release benefit.

### E8. History, licensing, issue, and documentation migration

The extracted history contains only intended project content and preserves MIT
provenance. The move has an audited file manifest, license/notice set, secret
and machine-local-path scan, release-tag policy, issue migration map, link
redirect plan, and named maintainers.

The `hxhx` repository retains integration documentation, but standalone target
guides, examples, support declarations, and release instructions move to their
owning repository. Neither project requires readers to infer which copy is
authoritative.

## Product or maintenance trigger

Passing E1-E8 makes extraction safe; it does not make it worthwhile. At least
one of these must also be demonstrated:

- `reflaxe.ocaml` has an independent release cadence, maintainer group, user
  community, or issue stream that is being constrained by the monorepo;
- measured `hxhx` bootstrap, Full1, or unrelated target churn materially slows
  standalone `reflaxe.ocaml` changes or releases;
- combined CI, repository size, permissions, or release automation creates a
  recurring and measured maintenance cost that the split removes; or
- external consumers need stable independent versioning and contribution
  ownership that the package alone cannot provide cleanly.

If all technical gates pass but none of these conditions exists, remaining in
the monorepo is still the better engineering choice.

## Post-split QA tiers

The split must preserve strong integration evidence without serializing every
edit behind the largest suite.

| Tier | Owner and cadence | What it proves |
| --- | --- | --- |
| Q0: focused target loop | `reflaxe.ocaml`, every relevant change | Fast compiler/runtime unit tests, generated-code shape, examples, formatting, and deterministic failures. |
| Q1: standalone package matrix | `reflaxe.ocaml`, required before release | One immutable package installs and builds external applications with stock Haxe on every declared host/toolchain. This is the primary product gate. |
| Q2: focused `hxhx` contract canary | cross-repository, required for touched shared contracts and release candidates | The exact candidate works for a bounded compiler build, runtime/ABI preflight, macro-host or plugin smoke, and emits a compatibility receipt. |
| Q3: full `hxhx` consumer E2E | scheduled, relevant high-risk changes, and release candidates | Large self-compile/bootstrap, native target, plugin/builtin, macro-host, cleanup, and performance workload remains healthy. |
| Q4: `hxhx` Full1/release suites | `hxhx` repository | Proves `hxhx` compatibility and release claims. It may expose a `reflaxe.ocaml` regression, but it is not automatically a gate for every target release. |

Q2 and Q3 use the exact candidate artifact, never an unrecorded branch checkout.
Failures name the producer source SHA, artifact digest, consumer SHA, contract
versions, toolchain, and failing tier.

## Ownership after extraction

The intended boundary is:

| `reflaxe.ocaml` repository owns | `hxhx` repository owns |
| --- | --- |
| Reflaxe target source and lowering | Haxe parser, resolver, typer, macros, diagnostics, and compiler lifecycle |
| OCaml target runtime and target stdlib overrides | Host implementation of supported backend/plugin/compiler services |
| Generated OCaml quality, Dune layouts, native target packaging | `hxhx` CLI, builtin activation, distribution, and Full1 evidence |
| Standalone examples, package tests, releases, support matrix, and performance | The pinned dependency, compatibility canaries, and large downstream E2E workload |

A shared ABI or schema has one source of truth chosen by its architecture owner.
The other repository consumes a generated or packaged form. A physical split
must never turn one semantic target core into two independently edited copies.

`hxhx` distributions may embed the pinned target package or runtime when that
is part of the declared product. The distribution manifest records the source
version, digest, license, and compatibility result.

## Extraction sequence

### Phase A: logical extraction inside the monorepo

- give `reflaxe.ocaml` independent version and release inputs;
- move standalone scripts, fixtures, docs, and workflow logic behind a
  package-owned command surface;
- replace production-significant relative paths with resolved package/runtime
  artifact inputs;
- add the artifact-mode `hxhx` canary while retaining an explicit fast workspace
  override; and
- inventory every remaining cross-package path as development-only, generated,
  or a blocker.

### Phase B: clean-room split rehearsal

- export the intended tracked history and file manifest to a temporary clean
  repository;
- run E1-E8 without access to the monorepo source tree;
- run Q0-Q3 with immutable candidate artifacts;
- compare common-loop latency and diagnose regressions; and
- perform the pin rollback drill.

### Phase C: authoritative move

- create the new private repository from the approved history and provenance
  manifest;
- make it the only writable source of `reflaxe.ocaml` target/runtime code;
- publish the accepted candidate or release artifact;
- update `hxhx` to the exact pin and external source links;
- remove the old tracked package source and obsolete release code rather than
  maintaining a mirror; and
- move or cross-link issues and documentation according to ownership.

### Phase D: post-split stabilization

- keep Q2 green for compatible changes and Q3 current on its declared cadence;
- automate dependency-update pull requests with artifact and compatibility
  receipts;
- review false coupling, flaky external orchestration, and latency after the
  first releases; and
- retain a documented rollback pin until the new boundary has sustained green
  evidence.

The default integration is a versioned package/artifact plus deterministic
fetching. Do not use a Git subtree or submodule as the production dependency:
that would preserve source-tree coordination while adding repository overhead.

## Stop conditions

Stop and redesign the extraction if any of these becomes necessary:

- required `hxhx` evidence still reads a sibling `reflaxe.ocaml` source path;
- `reflaxe.ocaml` cannot release or test without an `hxhx` checkout;
- the split creates two handwritten owners for target semantics, runtime ABI,
  or plugin schemas;
- every target pull request must wait for a multi-hour `hxhx` Full1 run;
- a moving branch, mutable artifact, `haxelib dev`, submodule, or subtree is the
  release dependency;
- coordinated changes cannot be tested by immutable candidate and exact pin;
- rollback requires rewriting a release or copying source between repositories;
- the filtered history or licensing/provenance audit is incomplete; or
- common development loops regress materially with no accepted product benefit.

## Reconsideration record

The extraction owner should review this gate at the standalone target release
candidate, at the M22 shared native ABI cutover, or when a measured trigger
appears. Each review records:

- E1-E8 as pass, fail, or not applicable with evidence;
- the product/maintenance trigger and measured cost;
- Q0-Q3 candidate identities and outcomes;
- before/after developer-loop timings;
- the keep/split decision and rollback owner; and
- whether README Goal 1 or North Star readiness changed.

This decision adds planning clarity only. README Goals progress bars and
current production-readiness claims remain unchanged.
