# External Macro-Host Lifecycle Decision

Status: implemented and verified for the selected aggregate; first project-macro loading proof also verified

Owning bead: `haxe_ocaml-vhk47.1`

Completed project-macro follow-up: `haxe_ocaml-vhk47.3`

## The short version

An external macro run involves two different things:

1. a **macro-host executable**, which is a program built on disk; and
2. a **macro-host process**, which is one running copy of that program.

The weekly external-host job will build one executable before running its macro
checks. Each compiler invocation may start a fresh process from that same
executable, but it must not rebuild the executable.

This is the smallest lifecycle that fits the current architecture:

- the workflow owns preparing and identifying the executable;
- `MacroHostClient` owns starting a fresh process and checking the protocol;
- unit, runci, and display checks reuse the exact same executable digest;
- release evidence disables lazy host building and forbids stage0;
- a nested host build is a hard error instead of a recursive build;
- the in-process job remains separate and does not use this artifact.

## Why this decision is sound

The committed macro-host snapshot is part of the candidate commit. Building it
with Dune while stage0 is forbidden therefore gives us a candidate-bound build
input. A receipt must additionally record:

- the exact commit;
- the committed macro-host snapshot tree;
- the resulting executable path and SHA-256 digest;
- a successful protocol handshake;
- and that stage0 was forbidden during preparation and use.

Exact-commit GitHub run `29334023225` reused one such host across the selected
unit, runci, display, and protocol checks. Both the external-host and in-process
jobs passed. The external receipt records candidate commit
`6436974b5b92b0a313b04a1df6f4dbf6c1bdc9be`, committed snapshot tree
`3b03e32c32d2e8fd91115a0191828723a7d2abca`, executable SHA-256
`8072225980e686c73f0a69477eb5a5b2ad9953f005fd685cb422a8258f9e2a19`,
protocol version `1`, stage0 forbidden, and lazy auto-build disabled.

The downloaded Linux executable's digest matches that receipt. Its protocol
probe ran on the Linux CI runner, where the executable was built, and the
receipt was revalidated before every selected workload. A macOS checkout can
inspect the receipt and digest but cannot execute that Linux binary directly.

The 2026-07-12 whole-repository GPT-5.6 Pro review independently supported the
explicit external/in-process macro boundary and required same-candidate,
artifact-backed evidence. It did not choose this detailed lifecycle. This page
is the required `thinking:xhigh` second pass over that review, the focused
probe, the workflow, both compiler auto-build call sites, the host build script,
and the current release contracts.

## What this proves—and what it does not

The passing external-host aggregate proves that one
candidate-bound, stage0-free host artifact can serve the selected upstream unit,
runci, display, and protocol workloads.

It does **not** yet prove:

- that the current Haxe source can regenerate the committed host snapshot
  without stage0;
- that arbitrary existing project macros, arguments, hooks, and the complete
  `haxe.macro` API are supported;
- that all Full1 macro/eval evidence is green;
- or that `hxhx` is ready for a Full1 release.

The first project-defined Haxe macro child is complete under
`haxe_ocaml-vhk47.3`. Exact-commit run `29349360051` generated one repo-owned
no-argument macro as a separate authenticated plugin, loaded it through both
native modes, and kept the reusable host separate. That proves the module path;
broader macro-language coverage remains with the parent Full1 macro/eval lane.

## Ownership boundaries

### The weekly workflow

The workflow builds or obtains the executable before any external-host
workload. It writes the receipt, exports the path, disables lazy auto-build, and
validates the receipt before later checks.

For now the external matrix job builds its own host instead of downloading it
from a separate producer job. There is only one consumer job, so a separate
upload/download handoff would add another failure boundary without improving
identity. The receipt is still suitable for later promotion to a shared
producer when multiple jobs need the same artifact.

### `build-hxhx-macro-host.sh`

The build script owns the distinction between a top-level host build and a
nested request. It exports a build-depth marker before launching any compiler.
A second request fails immediately with a clear recursion error.

The script's dynamic Stage3 and stage0 development products remain unchanged in
this slice. They are not accepted as release evidence merely because they share
the same command name.

### `Stage3MacroHostSupport` and `Stage3Compiler`

Both compiler auto-build call sites remain development conveniences. In release
evidence they see a configured executable and disabled auto-build, so neither
owns artifact preparation. If a development build does recurse, both routes
reach the same guarded build script and fail at the same boundary.

### `MacroHostClient`

The client continues to resolve the configured or sibling executable and start
a fresh process for one compilation. Process lifetime is deliberately separate
from artifact lifetime: reusing a file does not mean sharing macro state between
unrelated compilations.

## Environment-variable roles

- `HXHX_MACRO_RUNTIME_MODE` is user/compiler configuration.
- `HXHX_MACRO_HOST_EXE` identifies the prepared executable used by one external
  evidence job.
- `HXHX_FORBID_STAGE0=1` is a release-evidence policy input.
- `HXHX_MACRO_HOST_AUTO_BUILD` is development convenience only and must be `0`
  in release evidence.
- `HXHX_MACRO_HOST_BUILD_DEPTH` is an internal recursion guard, not a user-facing
  way to select a host.
- the receipt path and recorded digest are evidence inputs; later steps validate
  them instead of trusting the environment path by itself.

## Hard failures

The external evidence job must fail when:

- no executable was prepared;
- the receipt belongs to another commit or snapshot tree;
- the checkout changed after preparation;
- the executable is missing, non-executable, or has a different digest;
- the host cannot complete the expected protocol handshake;
- stage0 is allowed for preparation or workload execution;
- lazy auto-build is enabled in the evidence path;
- or a macro-host build requests another macro-host build.

An in-process success cannot replace an external-host failure, and a focused
fixture cannot replace the real aggregate.

## Implementation slices

1. Add the candidate-host receipt writer/validator and negative fixtures.
2. Add the shared recursion guard and prove a nested build fails before toolchain
   or compiler work begins.
3. Make the unit runner require stage0 only when it truly needs development
   auto-build.
4. Prepare one host in the external workflow job, validate it before each
   workload, and keep the in-process job independent.
5. Correct the blocker/status docs, run the exact local aggregate, then require
   a fresh same-commit GitHub aggregate before closing the lifecycle bead.

Each slice can be rolled back without changing macro semantics. No generated
OCaml file is edited by hand for this lifecycle change.

## Stop conditions

Pause and reopen the architecture decision if any selected workload actually
requires a project-specific class to be compiled into the host, if the generic
snapshot cannot complete the real CI protocol handshake, or if the only route
to green would permit stage0 or weaken a required macro check. Those outcomes
belong to the project-macro or semantic parity work, not to workflow plumbing.
