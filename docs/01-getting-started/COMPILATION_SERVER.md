# Compilation servers: current support and safe setup

This guide explains Haxe's compilation server, how it relates to
`reflaxe.ocaml` and `hxhx`, and which combinations are safe today.

## The short answer

- A **compilation server** keeps one compiler process alive so later requests
  can reuse work such as parsed files and safely cached typed modules.
- Upstream Haxe supports this with `--wait` on the server and `--connect` on a
  client command. It is not enabled automatically.
- `reflaxe.ocaml` builds in this project currently start a fresh Haxe process
  for each normal build. This remains deliberate. The pinned Reflaxe candidate
  now reconstructs complete target-wide state and passes focused clean/cold/warm
  source-generation tests. Package build/watch now also preserve Dune state
  outside transactional generated source. The wider edit, memory, and
  compiler-scale timing matrix is not complete enough for a supported
  persistent Haxe-server workflow.
- Native `hxhx` now has its first in-memory reuse layer: successful requests
  can reuse exact source text, checked module-file lookup results, and parsed
  Haxe modules. Its opt-in report can also compare an initial set of
  typed-module dependencies and predict which modules a future cache would
  need to check again for the currently covered imports, types, calls, embedded
  constants, source origins, conditional-compilation choices, and generated
  declarations. It does not yet reuse type-checking, macros, target generation,
  or native build results, so it is still an experimental server rather than a
  complete incremental compiler.
- For safe iteration today, use fresh-Haxe `reflaxe.ocaml` generation plus
  Dune's incremental OCaml build, or build `hxhx` from the committed bootstrap
  snapshot. Use the documented fingerprint skip when the inputs are unchanged.

Server reuse will become a normal recommendation only after clean and warm
builds are proven equivalent and warm builds are measurably faster.

There is intentionally no recommended native `hxhx` server setup command for
production use yet. The experimental commands later in this guide are for
testing the implemented source/parser cache and comparing it with a clean
one-shot build; they are not a default project or editor configuration.

The accepted native architecture and evidence gates are recorded in
[`ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md`](../00-project/ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md).
The shorter living implementation contract is
[`NATIVE_INCREMENTAL_SERVER_ARCHITECTURE.md`](../00-project/NATIVE_INCREMENTAL_SERVER_ARCHITECTURE.md).
The native implementation sends stdio and socket requests through the same
Haxe decoder and compile-or-display dispatcher. This removes the old
socket-only placeholder that rejected ordinary compilation. Ordinary compiler
progress and diagnostics are collected by a request-owned output object and
returned to the correct client using Haxe's output/error protocol.

This is still an implementation test, not a recommended project workflow.
Server requests currently require `--hxhx-no-run` so output from the compiled
program cannot bypass the client response. Each request now has a cleanup list:
when the request ends, hxhx closes its macro session and clears request-specific
macro definitions and backend-plugin registrations before accepting the next
request. An opt-in `--hxhx-server-report` result identifies the request, reports
whether cleanup succeeded, measures named compiler phases and total time, and
shows source, module-lookup, and parser cache decisions. It also enables the
initial dependency observer: hxhx still type checks every module, then reports
which covered module facts changed and which callers would need to be checked
again if typed results were reusable.

Display remains a bring-up response. Explicit shutdown now works for both
native transports: the requesting client receives a confirmation, request
cleanup finishes, and only then does the server exit successfully. A client can
also give one request a deadline. The compiler checks that deadline between
major phases and while moving through modules, stops at the next safe check,
and still runs request cleanup. This is cooperative cancellation, not a forced
thread interruption. Cross-client cancellation remains deferred. The
implemented request lifecycle resets audited process-wide temporary state
before and after every request. Focused tests compare fresh-process,
cold-server, failure, and repeated-server output for JavaScript, PHP, and C++;
the full hxhx target suite passed before reuse was enabled. The first cache
tests now cover unchanged files, same-byte rewrites, edits, A-to-B-to-A changes,
failed parsing, cancellation, reset, changed defines, class-path shadowing, and
eviction. The broader typed-module, macro, plugin, display, target, and
performance matrix is still required before recommending the server as a
normal workflow.
Filesystem output now uses success-only publication: a server request writes to
private paths first, runs its normal cleanup, and replaces the requested output
only if the whole request succeeded. Later steps complete the remaining
lifecycle guarantees. The current source/module-lookup/parser layer publishes
entries only after successful cleanup. Later layers add typed-module, display,
plugin, and target reuse only after each one passes clean-versus-warm
correctness tests.

There are two connected implementation tracks. `haxe_ocaml-850ii.33` makes
upstream Haxe 4.3.7's already-incremental compiler feed complete, safe Reflaxe
target state. `haxe_ocaml-850ii.32` implements the compatible native hxhx
incremental compiler. The hosts keep separate compiler caches, but their
Reflaxe target/plugin boundary should converge on the same complete,
revisioned program and output-ownership contract.

### Reflaxe source publication and Dune build state

The focused upstream-Haxe server fixture uses:

```bash
haxe --connect 6000 build.hxml \
  -D ocaml_no_build \
  -D reflaxe_output_transaction
```

`reflaxe_output_transaction` means that source generation writes a complete
private sibling directory, validates target completion and
`_GeneratedFiles.json`, and only then replaces the public output directory. A
failed request leaves the previous public directory unchanged. The private path
is a write location only; it must not enter generated bytes or semantic
revision identities.

The package `build` and `watch` commands now use this source transaction. Native
work starts only after the candidate becomes the public tree. Dune receives the
public `out/` directory as its workspace root and keeps reusable compiled state
in the stable sibling `.out.reflaxe-ocaml-dune-build/`. Replacing generated
source therefore does not delete native cache state, and Dune metadata never
records the private candidate or backup path.

Publication is the source-generation commit point. If Dune later rejects the
published source, the package command fails and does not run an executable, but
the new public source remains. Rolling it back at that point would pretend that
Dune had not already observed it and could make the source tree disagree with
the diagnostic. The next build may reuse the stable Dune directory after the
native error is fixed; an explicit Dune clean is needed only for a deliberately
cold native rebuild.

The focused server fixture above still uses `ocaml_no_build` because it isolates
whole-program source correctness from native-build timing. This does not mean
normal package builds are non-transactional. It means source/server evidence
and Dune incremental evidence remain separate tests until the complete
compiler-scale server matrix is ready.

## What a compilation server does

A normal compiler command starts a process, reads the project, checks it,
generates output, and exits. A compilation server stays alive and receives more
commands over a local port or standard input.

Upstream Haxe can reuse:

- parsed source files that did not change;
- typed modules whose inputs and dependencies are still valid; and
- selected compiler lookup work.

It must invalidate that cached work when source files, dependencies, class
paths, defines, macros, or other relevant inputs change. A fast stale result is
a wrong build, not a successful optimization.

The official upstream overview is the
[Haxe completion-server manual](https://haxe.org/manual/cr-completion-server.html).

## Upstream Haxe setup for projects that support it

The server is opt-in. Starting `haxe` normally does not leave a compiler process
running.

In one terminal, start a server bound to a local port:

```bash
haxe --wait 6000
```

In another terminal, send the project's normal HXML command to it:

```bash
haxe --connect 6000 myproject.hxml
```

Add `--times` to the client command to compare clean and warm compiler phases.
Use `--cwd <project-directory>` when the client/server setup does not already
run relative to the project, because HXML files and class paths are commonly
relative.

Stop the foreground server with Ctrl-C. For scripts, editors, or shared
workstations, give each project/toolchain an intentional port and lifecycle
owner rather than leaving a process behind anonymously.

Do not apply this generic setup to `reflaxe.ocaml` target generation in the
current project release. The upstream server works, but Reflaxe's target-wide
warm-build state is the unsupported part.

## The two servers in this project

These are different products and should not be confused:

| Server | What runs | Current purpose | Incremental status |
| --- | --- | --- | --- |
| Upstream Haxe server | Haxe 4.3.7 started with `--wait` | Upstream compilation and editor/display requests | Haxe owns real parsed/typed module reuse. Warm Reflaxe target output is not yet supported here. |
| Native `hxhx` server | A compiled `hxhx` process | Protocol, compiler bring-up, and measured incremental-cache development | Exact source/module-lookup/parser reuse exists. Opt-in dependency observation now also covers imports, resolved types, ordinary/inline calls, embedded constants, source origins, conditional-compilation choices, and generated declarations, but typing and later compiler stages still rerun. |

**Transport** means how a request reaches a long-lived process. **Incremental
compilation** means the compiler also knows exactly which previous results are
safe to reuse and what must be rebuilt. The native `hxhx` work is not complete
until both parts work together.

### Current cache and dependency report

The in-development native server accepts `--hxhx-server-report` as a base or
request argument. It adds lines like these to that client's response:

```text
hxhx_server_report.request_id=3
hxhx_server_report.server_request=1
hxhx_server_report.semantic_cache=source-resolution-parser
hxhx_server_report.semantic_cache_hits=3
hxhx_server_report.semantic_cache_misses=0
hxhx_server_report.semantic_cache_entries=4
hxhx_server_report.semantic_cache_bytes_estimate=2142
hxhx_server_report.source_hits=1
hxhx_server_report.source_misses=0
hxhx_server_report.source_bytes_read=46
hxhx_server_report.resolution_hits=1
hxhx_server_report.resolution_misses=0
hxhx_server_report.parser_hits=1
hxhx_server_report.parser_misses=0
hxhx_server_report.cache_evictions=0
hxhx_server_report.dependency_observation=enabled
hxhx_server_report.dependency_previous_snapshot=1
hxhx_server_report.dependency_modules=2
hxhx_server_report.dependency_edges=3
hxhx_server_report.dependency_snapshot=display31-v1:4821:-120039371
hxhx_server_report.dependency_public_changes=0
hxhx_server_report.dependency_implementation_changes=1
hxhx_server_report.dependency_predicted_invalidations=1
hxhx_server_report.dependency_invalidation[0].module=Api
hxhx_server_report.dependency_invalidation[0].reason=implementation-changed:Api
hxhx_server_report.cache_miss_reason_count=0
hxhx_server_report.cancelled=0
hxhx_server_report.output_transaction=committed
hxhx_server_report.cleanup=ok
hxhx_server_report.phase_count=4
hxhx_server_report.phase[0].name=request-init
hxhx_server_report.phase[0].elapsed_ms=2
hxhx_server_report.elapsed_ms=123
```

This report is opt-in because elapsed time and internal lifecycle details are
diagnostic information, not normal compiler output. A **hit** means the current
request exactly matched an entry that a previous successful request published.
A **miss** means hxhx safely recomputed that work. Miss reasons include
`cold`, `source-changed`, `parser-input-changed`, `origin-shadowed`, and
`evicted`. These names explain performance; they do not change compiler
behavior.

The dependency fields are a rehearsal for typed-module caching. A **public
interface** is the part of a module another module can compile against, such as
a public function's argument and return types. An **implementation** is the
function body and other private work behind that interface. A **dependency
edge** records why one module used another, such as importing it or calling one
of its functions.

For example, changing only `Api.answer()`'s ordinary function body reports an
implementation change for `Api` but does not predict that a signature-only
caller must be type checked again. Changing `answer()`'s return type reports a
public-interface change and predicts that the caller must be checked again.
Changing an inline body affects only callers that actually use that inline
function, because the compiler may embed the body into those callers. A module
that only imports the provider does not need to be rechecked for that edit. The
current focused tests build both program versions from scratch and assert these
initial predictions. They do not yet independently derive the complete
affected-module set for every Haxe feature, and the
predictions do not currently skip typing.

The observer is not yet a complete typed-cache safety proof. Constants,
generated declarations, conditional-compilation choices, and selected source
origins now have focused observation coverage. The complete contract still
needs macro observations, feature/DCE state, static initialization,
target/profile behavior, and the full cross-feature edit matrix. Until those
cases pass clean-versus-warm comparison, hxhx must continue type checking every
module.

`haxe_ocaml-850ii.32.5` owns the later typed-module admission gate. It can begin
after its direct identity, request-state, dependency, differential, failure,
reset, memory, and performance prerequisites pass; it does not technically
wait for unrelated Full1 target rows. Completing it still cannot imply Full1
readiness.

Dependency observation runs only when `--hxhx-server-report` is present. This
keeps ordinary experimental requests from paying its current full-program
recording cost. The readable dependency fingerprint detects accidental report
nondeterminism, but it is not a cache key and cannot make a request reuse typed
work.

The current layer works as follows:

- hxhx reads each selected source file on every request and compares the exact
  path and content through a length-prefixed in-memory identity. It does not
  yet rely on filesystem timestamps or watchers to skip the read.
- Module lookup rechecks the requested exact filename at each relevant
  class-path position. A new higher-priority file, deletion, rename, or case
  change therefore changes the lookup result.
- Parsed modules are reused only when the logical file path, source after
  `#if` filtering, and parser configuration all match. hxhx checks that the
  stored parse tree was not accidentally changed before publishing or reusing
  it.
- Failed and cancelled requests publish nothing. `reset` discards every entry.
- Entries live only in the current process. A server restart is a cold cache.
- The default retained-size estimate is 64 MiB and can be changed with
  `HXHX_NATIVE_SERVER_SOURCE_CACHE_BYTES`. This bounds the cache's own estimate,
  not the whole compiler process's resident memory.

Type checking, macro execution, feature/DCE analysis, target generation, file
emission, Dune compilation, and linking still run normally. A parser hit is
therefore a real but deliberately limited improvement, not evidence that the
complete incremental compiler is ready.

Across two final local macOS runs of the generated OCaml bytecode compiler,
direct compiles took 11,134–12,196 ms, cold server compiles took
10,606–10,859 ms, first warm compiles took 3,654–3,773 ms, and the repeated
warm stability requests took 3,648–3,789 ms. Reset made the next request cold
again at 10,677–10,838 ms. These numbers show that the current parser cache has
a real effect on this fixture. They are not a cross-machine benchmark, a
TypeScript/Go comparison, or evidence that the unfinished server should be
enabled by default.

A **phase** is one named portion of the compiler request, such as setup,
parsing, typing, code generation, or cleanup. If the compiler enters the same
named phase more than once, the report combines those intervals. These timings
show where a request spends its time, so later work can demonstrate a real
end-to-end improvement instead of only reporting an internal cache hit.

### Experimental native setup

The native server is opt-in. Running `hxhx` normally starts one compiler
process for one command and does not leave a server behind.

For an experimental local socket server, start the exact `hxhx` binary you want
to test in one terminal:

```bash
hxhx --wait 6000
```

Send a compile request from another terminal. The current server route requires
`--hxhx-no-run`; run the produced program yourself after the request succeeds.

```bash
hxhx --connect 6000 \
  --hxhx-no-run \
  --hxhx-server-report \
  --hxhx-backend js-native \
  --js out/app.js \
  -cp src -main Main
```

Run the same command again to inspect warm parser reuse. Edit a file and repeat
the command to inspect the miss reason and verify the new output. To discard
all reusable entries without stopping the process:

```bash
hxhx --connect 6000 --hxhx-server-control reset
```

To stop it cleanly:

```bash
hxhx --connect 6000 --hxhx-server-control shutdown
```

`--wait stdio` exposes the same compiler owner through Haxe's length-framed
standard-input protocol. It is intended for an editor, build tool, or test
harness that implements the protocol; it is not an interactive shell command.
Socket and stdio requests are processed one at a time and share cache entries
only within that server process.

Use a dedicated loopback port and exact compiler/toolchain per project while
this remains experimental. There is no automatic background daemon, endpoint
discovery, health command, or default editor configuration yet. Keep a direct
one-shot command available as the comparison path when investigating a
suspected cache problem.

The current native transport accepts at most 64 MiB for one complete request,
including command-line arguments and any unsaved editor buffer. Stdio requests
whose length prefix is negative or above that limit receive a framed error and
the server exits because the byte stream cannot be safely resynchronized.
Socket clients that exceed the limit or disconnect before the required NUL
terminator receive an error; the server then accepts the next connection. No
parsing, typing, macro execution, or target output begins for a rejected frame.

### Current native request deadlines

The in-development native server accepts an hxhx-specific deadline for one
request. The value is a decimal number of milliseconds from `0` through
`86400000` (24 hours). For example, this gives a socket request five seconds:

```bash
hxhx --connect 6000 \
  --hxhx-server-timeout-ms 5000 \
  --hxhx-no-run --js out/app.js -main Main
```

The deadline option controls the server request and is removed before normal
compiler argument parsing. A value of `0` means the deadline has already
expired, so the request stops at its first safe check. This is useful for
testing the failure path:

```text
hxhx(stage3): request cancelled [deadline-exceeded] at request-dispatch
```

With `--hxhx-server-report`, the same response also includes:

```text
hxhx_server_report.cancelled=1
hxhx_server_report.cancellation_reason=deadline-exceeded
hxhx_server_report.cancellation_stage=request-dispatch
hxhx_server_report.cleanup=ok
```

“Cooperative” means hxhx asks whether it should continue at named boundaries
such as setup, parsing and resolution, typing, hooks, code generation, and
execution. It also checks while advancing through modules. It does not kill the
compiler thread in the middle of an operation. A macro, plugin, target, or
external tool that is already blocked may therefore continue until its own
timeout fires or it returns control to hxhx.

The current server handles compiler requests one at a time. While one request
is running, it cannot process a second client's “cancel this request” command.
This slice therefore provides a deadline supplied with the original request,
not interactive cross-client cancellation.

Request cleanup still runs, the deadline failure is returned only to that
client, and the server can accept another request. A request cancelled before
compilation creates no output. If a later deadline expires after code generation
has started, the generated files are still in the request's private staging
area. They are discarded during cleanup, so the last successful output remains
in place.

`--hxhx-server-timeout-ms` is not part of the upstream Haxe 4.3.7 protocol and
is not yet a recommended production interface.

### Current native success-only output publication

A long-lived compiler must not leave half of a failed build in the project's
real output directory. For example, JavaScript generation commonly produces
both `out/app.js` and `out/app.js.map`. If generation fails after writing the
first file, replacing only that file would mix a new program with an old source
map.

Native server requests therefore use this order:

1. Resolve the output paths requested by the client.
2. Give the target private sibling paths on the same filesystem.
3. Generate the target files there while the previous successful output stays
   untouched.
4. Check the request deadline and finish macro, plugin, and other request
   cleanup.
5. Replace the requested files only when every earlier step succeeded. On a
   compiler error, cancellation, or cleanup error, delete the private files.

This is called an **output transaction** in the code. Here, “transaction” means
that hxhx owns the prepare, publish, rollback, and cleanup sequence; it does not
mean that every operating system can replace several unrelated files in one
indivisible instruction. Directory-based target output is moved as one staged
directory. A standalone output file and its sidecars are replaced with backups
and rollback on an ordinary publication failure. A process or machine crash in
the middle of several filesystem renames still needs separate recovery design
and evidence.

With `--hxhx-server-report`, the output state is one of:

```text
hxhx_server_report.output_transaction=not_started
hxhx_server_report.output_transaction=committed
hxhx_server_report.output_transaction=aborted
```

`not_started` means the request stopped before target output was prepared.
`committed` means staged output replaced the requested paths after successful
cleanup. `aborted` means staging was prepared but discarded, so prior output
was retained. The focused JavaScript fixture proves the main file and source
map move together, a later missing-module request preserves their prior bytes,
and no private staging or backup path remains.

This is still an implementation milestone, not a claim that every target has
passed clean-process versus server-output equivalence. That broader matrix
remains a gate before the native server becomes a recommended workflow.

### Current native shutdown control

The in-development native server has hxhx-specific reset and shutdown requests.
Reset removes source, module-lookup, and parser entries but keeps the process
available:

```bash
hxhx --connect 6000 --hxhx-server-control reset
```

The client receives:

```text
hxhx_server_control.reset=ok
```

For a socket server listening on port 6000, stop the process with:

```bash
hxhx --connect 6000 --hxhx-server-control shutdown
```

The client receives this confirmation before the server exits:

```text
hxhx_server_control.shutdown=ok
```

This ordering matters because a shutdown command should not make the client
guess whether the server received it. hxhx first closes the current request,
including its registered cleanup work. If cleanup fails, the request fails and
the server stays alive so the failure is visible instead of being hidden by an
exit. The transport consumes that stop decision once and exits only when the
matching response was delivered, so a disconnected shutdown client cannot make
a later unrelated connection stop the server. An unknown control name also
fails without stopping the server.

`--hxhx-server-control` is an hxhx extension, not part of the Haxe 4.3.7
compiler-server protocol. This is still an implementation/testing interface,
not a recommendation to enable the native server for normal projects. Endpoint
discovery, interactive cross-client cancellation, and automatic stale-server
recovery remain unfinished.

If the requested TCP port already belongs to another process, hxhx now returns
a readable `wait socket failed` diagnostic and leaves that process and listener
alone. It does not kill by port number or process name. This protects a live
owner; it is not yet the future PID/start-identity/nonce registry needed for
automatic server discovery and stale-record cleanup.

## Current scenario guide

| What you are doing | Recommended workflow today | Server enabled by default? |
| --- | --- | --- |
| Build a normal app with upstream Haxe and a non-Reflaxe target | Follow upstream Haxe's `--wait`/`--connect` guidance if the target and macros support it. | No |
| Build OCaml with upstream Haxe plus `reflaxe.ocaml` | Use `build` or `watch` for the fresh default. To reuse upstream Haxe's frontend, start a local Haxe 4.3.7 server and add `--connect <port>`. | No; reuse is explicit |
| Rebuild `hxhx` from committed OCaml snapshots | Run `bash scripts/hxhx/build-hxhx.sh`; no stage0 Haxe server is needed. | No |
| Rebuild `hxhx` from stage0 source | Run with `HXHX_FORCE_STAGE0=1`. Add `HAXE_CONNECT=<port>` or `HXHX_STAGE0_USE_REPO_SERVER=1` only when you deliberately want the supported warm route. | No; reuse is explicit |
| Regenerate committed `hxhx` bootstrap sources | Use the fresh default, or add `--use-repo-server` for an explicitly warm generation sequence. `--skip-if-unchanged` remains useful in either mode. | No; reuse is explicit |
| Measure native `hxhx` source/parser reuse locally | Use the experimental socket commands above, keep `--hxhx-no-run`, inspect `--hxhx-server-report`, and compare with a direct one-shot build. | No |
| Use native `hxhx` for editor/display experiments | Use only the explicitly documented test lane; display recovery and typed-result caching are not implemented. | No |
| Build an `hxhx` plugin or target | Use the current one-shot build/test commands. Plugin/target cache reuse is not a shipped contract. | No |

## Supported `reflaxe.ocaml` application workflow

For an installed project with `build.hxml`, the default remains a fresh Haxe
process for each build:

```bash
haxelib run reflaxe.ocaml build
haxelib run reflaxe.ocaml watch --run .out.reflaxe-ocaml-dune-build/default/out.exe
```

To reuse upstream Haxe's parsed and typed modules, start a local Haxe 4.3.7
server in one terminal:

```bash
haxe --wait 6000
```

Then select it explicitly from another terminal:

```bash
haxelib run reflaxe.ocaml build --connect 6000
haxelib run reflaxe.ocaml watch --connect 6000 \
  --run .out.reflaxe-ocaml-dune-build/default/out.exe
```

The package accepts only an unqualified port, `localhost:<port>`, or
`127.0.0.1:<port>`. The Haxe protocol is not an authenticated internet service,
so the supported authoring command does not connect to remote hosts. The user
owns the external server process: the package sends requests to it but does not
start, reset, or stop it. Stop and restart that Haxe process when you need a
cold server state; omit `--connect` for a fresh-process comparison.

In both modes, the watcher detects project changes, waits for a stable batch,
and runs the result only after source publication and the native build succeed.
`out/` is the complete Reflaxe-owned generated tree;
`.out.reflaxe-ocaml-dune-build/` is Dune-owned disposable build state. Identical
publication reuses compiled modules. An implementation-only leaf edit rebuilds
that module and relinks the executable without unnecessarily recompiling a
dependent whose OCaml interface did not change.

On a warm request, upstream Haxe may type only the affected modules. Reflaxe
nevertheless reconstructs the complete current program before
`reflaxe.ocaml` generates files. Here, **complete program** means every retained
type and its final post-filter body, not merely the latest batch Haxe happened
to retype. The target then validates and publishes one complete source tree, so
a deleted, moved, shadowed, or configuration-dependent module cannot survive
only because an older file remained on disk.

See `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md` for project
setup and `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md` for the current
product boundary.

## Supported `hxhx` development workflow

The normal build uses committed generated OCaml sources and does not invoke an
upstream Haxe server:

```bash
bash scripts/hxhx/build-hxhx.sh
```

For an intentional fresh source rebuild:

```bash
HAXE_BIN=/absolute/path/to/haxe \
HXHX_FORCE_STAGE0=1 \
HXHX_STAGE0_PROGRESS=1 \
bash scripts/hxhx/build-hxhx.sh
```

For repeated stage0 source builds, either supply an already-running local
server or let the repository helper own one:

```bash
HAXE_CONNECT=6000 \
HXHX_FORCE_STAGE0=1 \
bash scripts/hxhx/build-hxhx.sh

HXHX_STAGE0_USE_REPO_SERVER=1 \
HXHX_STAGE0_KEEP_REPO_SERVER=1 \
HXHX_FORCE_STAGE0=1 \
bash scripts/hxhx/build-hxhx.sh
```

For bootstrap regeneration, the equivalent helper-owned route is:

```bash
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
  --skip-if-unchanged --incremental --use-repo-server \
  --keep-repo-server --no-verify
```

The repository helper owns only the server it started for this checkout and
verifies the launcher and worker process tree before cleanup. An explicit
`HAXE_CONNECT` endpoint remains user-owned. Fresh source generation remains the
default and the comparison/recovery route.

## What changed after the original warm failure

An unchanged measured `hxhx` source build showed the opportunity and the bug:

| Request | Result |
| --- | --- |
| First request | Completed in 833.30 seconds and built `out.bc`. |
| Immediate request through the same Haxe server | Reached target finalization in 30.37 seconds, but failed because complete generated-module/runtime ownership was missing. |

Haxe correctly reused its own parsing and typing work. Reflaxe then supplied a
partial rebuild view, while `reflaxe.ocaml` still had to produce target-wide
information such as runtime selection, type registries, build files, reports,
and the complete generated-file set. Guessing or keeping arbitrary old files
could silently preserve deleted or configuration-dependent output.

The corrected lifecycle now uses Haxe's complete generation membership, copies
the final retained bodies after Haxe's built-in filters, validates one complete
target request, and publishes generated source transactionally. The real
Haxe 4.3.7 regression matrix compares fresh and warm results after unchanged,
implementation, public-signature, add/delete/move/shadow, define/profile, DCE,
build-macro, failure, A-to-B-to-A, and server-restart sequences.

This makes the upstream-Haxe/Reflaxe route an explicit supported opt-in. It is
not yet the default because compiler-scale latency and memory evidence still
need to show that the full developer loop benefits on representative projects.
The fix is tracked by `haxe_ocaml-850ii.33`. Native `hxhx` incremental
compilation remains separate under `haxe_ocaml-850ii.32`.

## Repository-owned server lifecycle

The repository helper safely owns one upstream Haxe server process tree:

```bash
bash scripts/hxhx/haxe-server.sh start
bash scripts/hxhx/haxe-server.sh status
bash scripts/hxhx/haxe-server.sh owned-pids
bash scripts/hxhx/haxe-server.sh stop
```

It chooses a deterministic repository-local port unless
`HXHX_HAXE_SERVER_PORT` is set. It records the launcher and verified children,
because a Lix/Node launcher may start a separate native Haxe process that does
the real work.

Use `stop` followed by `start` to discard the upstream server's in-memory
frontend cache. Do not delete its state directory while it is running.

## Editors and display clients

Upstream Haxe editors commonly use the completion server because it can reuse
parsed and typed modules. That editor use does not automatically make a
Reflaxe target generation request safe: completion/display and whole-program
target output have different state requirements.

Native `hxhx` display and protocol tests cover selected bring-up paths. The
experimental setup above is suitable for measuring ordinary compile requests,
but display still returns a bring-up response and does not publish typed editor
state. Until the display acceptance matrix passes, configure production editors
around upstream Haxe.

The native setup is documented so contributors can test it without guessing;
it is not enabled by default or recommended for production projects. Plugin and
macro realm isolation, typed-module reuse, endpoint discovery, health/status,
and clean-build comparison tooling remain unfinished shipping gates.

The performance goal is stronger than “the cache reported a hit.” On
representative projects, the complete edit-to-diagnostics and
edit-to-runnable-result loop should be competitive with, and where the
workloads permit, better than mature TypeScript incremental and Go build-cache
workflows. Measurements must separate hxhx front-end reuse, target generation,
file writes, Dune compilation/linking, and program load so a fast internal
phase cannot hide a slow developer workflow.

## CI, containers, and remote development

- Prefer fresh compiler processes for one-shot CI jobs. A job that performs a
  measured sequence of builds may use the explicit server route, but must own
  startup, shutdown, and a fresh-process comparison.
- Do not share a server port or cache directory between unrelated projects,
  Haxe versions, standard libraries, target profiles, or plugin versions.
- Bind development servers to loopback unless remote access is deliberately
  secured. The compiler protocol is not an internet-facing service.
- Stop owned servers before deleting their state directory or replacing the
  compiler executable.
- In short-lived containers, a server often adds startup and memory cost
  without receiving enough requests to repay it.
- In a long-lived remote workspace, measure warm latency and memory using the
  exact project/toolchain before enabling a future supported server mode.

## Memory and process ownership

The measured cold `hxhx` source generation observed approximately 6.5 GB of
resident memory in the upstream server process tree. This is a large compiler
workload, not a recommended minimum for ordinary applications.

Check and stop only the repository-owned server with:

```bash
bash scripts/hxhx/haxe-server.sh status
bash scripts/hxhx/haxe-server.sh owned-pids
bash scripts/hxhx/haxe-server.sh stop
```

Avoid broad process-name cleanup on a shared machine. It can terminate another
project, editor, user, or agent's compiler.

## Troubleshooting

### A server request fails

First rerun without `--connect` (or without the repository-server option). If
the fresh request also fails, diagnose the source/target error normally. If
only the warm request fails, preserve the smallest edit sequence and compare
its generated tree, diagnostics, and executable output with the fresh route.
Stop and restart the owned server before retrying; do not retain or hand-edit
old generated files to make the request pass.

### The server is still running

Run the helper's `status`, `owned-pids`, and `stop` commands. If `status` says
`not-running`, do not search for and kill arbitrary Haxe processes; they may
belong to another project.

### A build is slow

First confirm whether the cost is Haxe/Reflaxe generation, Dune compilation,
linking, or running the program. Use the progress/timing commands in
`docs/01-getting-started/TESTING.md`. Prefer a native Haxe executable over a
launcher when measurements show wrapper overhead, and use fingerprint skips
for truly unchanged bootstrap inputs.

For package `build` and `watch`, verify that generated source is in `out/` and
Dune state is in `.out.reflaxe-ocaml-dune-build/`. A reappearing `out/_build/`
usually means the project invoked Dune directly without the package-owned
transactional path. Reset only Dune state with:

```bash
dune clean --root out --build-dir .out.reflaxe-ocaml-dune-build
```

This command does not remove generated source. Deleting or regenerating `out/`
does not remove Dune state; use both actions explicitly only when a fully cold
source-and-native comparison is intended.

### The executable is not under `out/_build`

That is expected for transactional package builds. For the default `out`
directory, run
`.out.reflaxe-ocaml-dune-build/default/out.exe`. The generated Dune files stay
in `out/`; only compiled objects and executables live in the external Dune
directory.

### A warm experiment generates fewer files or different reports

Treat it as a correctness failure. Do not copy missing files from an older
directory or add an unknown module to an allowlist. Record the clean/warm file
trees, target reports, exact toolchain, definitions, and first differing
module, then continue under `haxe_ocaml-850ii.33`.

## What must be true before server reuse becomes a default

The project will not enable server reuse by default until tests prove:

- unchanged and small-edit warm builds are materially faster;
- clean and warm diagnostics, generated files, reports, native behavior, and
  public interfaces agree;
- edits, additions, deletions, moves, class-path/define changes, macros,
  plugins, targets, and failed requests invalidate the right work;
- stale output is removed transactionally;
- memory is bounded and inspectable;
- reset, cancellation, shutdown, editor, CI, and multi-project scenarios are
  documented and tested; and
- stock Haxe/Reflaxe and native `hxhx` adapters use one compatible target-state
  contract rather than two target implementations.

These requirements are product work, not optional documentation polish.
