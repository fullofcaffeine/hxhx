# Compilation servers: current support and safe setup

This guide explains Haxe's compilation server, how it relates to
`reflaxe.ocaml` and `hxhx`, and which combinations are safe today.

## The short answer

- A **compilation server** keeps one compiler process alive so later requests
  can reuse work such as parsed files and safely cached typed modules.
- Upstream Haxe supports this with `--wait` on the server and `--connect` on a
  client command. It is not enabled automatically.
- `reflaxe.ocaml` builds in this project currently start a fresh Haxe process
  for each normal build. This is deliberate: an unchanged warm-server request
  was much faster, but it lost complete target-wide state and stopped before
  producing a valid OCaml build.
- Native `hxhx` accepts some `--wait`/`--connect` shapes, but it does not yet
  provide a complete incremental compiler. Keeping a process open is not the
  same as safely reusing parsing and typing.
- For safe iteration today, use fresh-Haxe `reflaxe.ocaml` generation plus
  Dune's incremental OCaml build, or build `hxhx` from the committed bootstrap
  snapshot. Use the documented fingerprint skip when the inputs are unchanged.

Server reuse will become a normal recommendation only after clean and warm
builds are proven equivalent and warm builds are measurably faster.

The accepted native architecture and evidence gates are recorded in
[`ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md`](../00-project/ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md).
The first implementation sub-slice now sends stdio and socket requests through
the same Haxe decoder and compile-or-display dispatcher. This removes the old
socket-only placeholder that rejected ordinary compilation. It deliberately
adds no semantic cache. Ordinary compiler progress and diagnostics are now
collected by a request-owned output object and returned to the correct client
using Haxe's output/error protocol. A native test sends a successful compile,
a missing-module failure, and another successful compile to one server; all
three clients receive their own result and the server process stays silent.

This is still an implementation test, not a recommended project workflow.
Server requests currently require `--hxhx-no-run` so output from the compiled
program cannot bypass the client response. Each request now has a cleanup list:
when the request ends, hxhx closes its macro session and clears request-specific
macro definitions and backend-plugin registrations before accepting the next
request. An opt-in `--hxhx-server-report` result identifies the request, reports
whether cleanup succeeded, measures elapsed time, and explicitly says that the
semantic cache is disabled with zero entries and zero hits.

Display remains a bring-up response, and cancellation, shutdown, a complete
audit of all mutable compiler state, transactional file output, and
clean-process equivalence are not finished. Later steps add those lifecycle
guarantees, then reusable source, parser, typed-module, display, plugin, and
target facts only after each layer passes clean-versus-warm correctness tests.

There are two connected implementation tracks. `haxe_ocaml-850ii.33` makes
upstream Haxe 4.3.7's already-incremental compiler feed complete, safe Reflaxe
target state. `haxe_ocaml-850ii.32` implements the compatible native hxhx
incremental compiler. The hosts keep separate compiler caches, but their
Reflaxe target/plugin boundary should converge on the same complete,
revisioned program and output-ownership contract.

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
| Native `hxhx` server | A compiled `hxhx` process | Protocol, display, and compiler bring-up | Transport exists in selected lanes, but complete dependency-aware compiler reuse is not delivered yet. |

**Transport** means how a request reaches a long-lived process. **Incremental
compilation** means the compiler also knows exactly which previous results are
safe to reuse and what must be rebuilt. The native `hxhx` work is not complete
until both parts work together.

### Current no-cache diagnostic report

The in-development native server accepts `--hxhx-server-report` as a base or
request argument. It adds lines like these to that client's response:

```text
hxhx_server_report.request_id=3
hxhx_server_report.server_request=1
hxhx_server_report.semantic_cache=disabled
hxhx_server_report.semantic_cache_hits=0
hxhx_server_report.semantic_cache_entries=0
hxhx_server_report.cleanup=ok
hxhx_server_report.elapsed_ms=123
```

This report is opt-in because elapsed time and internal lifecycle details are
diagnostic information, not normal compiler output. At this stage, a report of
zero hits is the expected correct result: hxhx deliberately reparses and
rechecks every request until cache identities and invalidation rules are proven.
The report must not be read as evidence that incremental compilation is ready.

## Current scenario guide

| What you are doing | Recommended workflow today | Server enabled by default? |
| --- | --- | --- |
| Build a normal app with upstream Haxe and a non-Reflaxe target | Follow upstream Haxe's `--wait`/`--connect` guidance if the target and macros support it. | No |
| Build OCaml with upstream Haxe plus `reflaxe.ocaml` | Use `haxelib run reflaxe.ocaml build` or `watch`; each source-generation batch starts fresh. | No |
| Rebuild `hxhx` from committed OCaml snapshots | Run `bash scripts/hxhx/build-hxhx.sh`; no stage0 Haxe server is needed. | No |
| Force a fresh stage0 source rebuild of `hxhx` | Run with `HXHX_FORCE_STAGE0=1` and no `HAXE_CONNECT`/repo-server flag. | No |
| Regenerate committed `hxhx` bootstrap sources | Use a clean or incremental output directory without server reuse; use `--skip-if-unchanged` where applicable. | No |
| Use native `hxhx` for editor/display experiments | Use only the explicitly documented test lane; do not infer full compile-cache support. | No |
| Build an `hxhx` plugin or target | Use the current one-shot build/test commands. Plugin/target cache reuse is not a shipped contract. | No |
| Reproduce the known Reflaxe warm-cache failure | Maintainers may use the diagnostic override described below in an isolated test. | Never automatically |

## Safe `reflaxe.ocaml` application workflow

For an installed project with `build.hxml`:

```bash
haxelib run reflaxe.ocaml build
haxelib run reflaxe.ocaml watch --run out/_build/default/out.exe
```

The watcher detects project changes, starts a fresh Haxe process for each
stable batch, and runs the result only after generation and the native build
succeed. Reflaxe avoids rewriting unchanged generated files, and Dune reuses
valid OCaml compilation artifacts. This keeps useful incremental behavior
without relying on incomplete long-lived target state.

See `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md` for project
setup and `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md` for the current
product boundary.

## Safe `hxhx` development workflow

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

For bootstrap regeneration, skipping unchanged inputs is safer and faster than
an incomplete warm target rebuild:

```bash
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh \
  --skip-if-unchanged --incremental --no-verify
```

Do not add `--use-repo-server`, `HXHX_STAGE0_USE_REPO_SERVER=1`, or
`HAXE_CONNECT` to these Reflaxe-backed workflows today. The scripts reject that
combination before deleting or generating target output.

## Why warm Reflaxe output is blocked

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

The failure is tracked by `haxe_ocaml-850ii.33`. Native `hxhx` incremental
compilation is tracked separately by `haxe_ocaml-850ii.32`.

## Maintainer-only server lifecycle diagnostics

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

The following override exists only so focused lifecycle tests can reproduce and
measure the incomplete path:

```bash
HXHX_ALLOW_INCOMPLETE_REFLAXE_SERVER_REUSE=1
```

Output produced with that override is not correctness, release, bootstrap, or
performance evidence. Do not put the override in project HXML files, shell
profiles, CI secrets, or editor settings.

## Editors and display clients

Upstream Haxe editors commonly use the completion server because it can reuse
parsed and typed modules. That editor use does not automatically make a
Reflaxe target generation request safe: completion/display and whole-program
target output have different state requirements.

Native `hxhx` display and protocol tests cover selected bring-up paths. Until
the native incremental-server acceptance matrix passes, configure production
editors around upstream Haxe and treat `hxhx` server use as an explicit test.

There is intentionally no recommended native `hxhx` server setup command for
ordinary project compilation yet. Once implemented, this guide will document
whether it is enabled by default, its `--wait`/`--connect` compatibility,
project configuration, plugin/target behavior, reset and inspection commands,
and clean-build comparison. A test-only protocol command is not presented as a
user workflow.

The performance goal is stronger than “the cache reported a hit.” On
representative projects, the complete edit-to-diagnostics and
edit-to-runnable-result loop should be competitive with, and where the
workloads permit, better than mature TypeScript incremental and Go build-cache
workflows. Measurements must separate hxhx front-end reuse, target generation,
file writes, Dune compilation/linking, and program load so a fast internal
phase cannot hide a slow developer workflow.

## CI, containers, and remote development

- Prefer fresh compiler processes in CI until warm equivalence is a required
  gate. CI should value reproducibility over a process-local cache.
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

### A script says server reuse is disabled

Remove `HAXE_CONNECT`, `HXHX_STAGE0_USE_REPO_SERVER`,
`HXHX_STAGE0_KEEP_REPO_SERVER`, `--use-repo-server`, or
`--keep-repo-server`. Run the direct source build or committed-snapshot build.

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
