# Native hxhx incremental server architecture

Status: implemented source/module-lookup/parser layer; experimental user route.

This is the living implementation contract for `haxe_ocaml-850ii.32`. The
independent design review and its wider roadmap remain in
[`ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md`](ORACLE_CHECKPOINT_NATIVE_INCREMENTAL_SERVER_2026_07_22.md).

## Practical outcome today

One native `hxhx --wait` process can handle several compile requests. Every
request receives fresh diagnostics, macro state, typing state, target builders,
and output staging. Successful requests can currently reuse three read-only
results:

1. exact source text identified by file path and complete content;
2. the result of checking an exact Haxe module filename against ordered class
   paths; and
3. the parsed Haxe module produced from the source that remains after `#if`
   filtering.

A **cache entry** is one stored result from a previous successful request. A
**revision** is a deterministic identity for all inputs that make that result
valid. It can be a digest, but this process-local cache currently keeps the
complete input so a hash collision cannot produce a false match. A result is
**immutable** here when later compiler code may read it but must not change it.

This is not yet a complete incremental compiler. Type checking, macros,
whole-program analysis, target generation, and native building still rerun.

## Small mental model

```text
socket or stdio request
  -> one request dispatcher
  -> fresh CompilationRequestContext
  -> request-owned CompilerSourceProvider
       -> validate/reuse source text
       -> recheck and validate/reuse module lookup
  -> validate/reuse parsed module
  -> fresh resolver, typer, macro session, target builder
  -> successful cleanup
  -> validate new read-only cache entries
  -> publish generated output
  -> publish new read-only cache entries
```

The long-lived cache stores data. It does not decide Haxe typing, macro, or
target behavior. `Stage3Compiler` remains the one compiler owner.

## Ownership

| Part | Owns | Does not own |
| --- | --- | --- |
| `Stage3WaitServer` | One cache catalog for the lifetime of one wait process | Cache keys or compiler behavior |
| `CompilationServerRequestDispatcher` | Creating one fresh request and selecting compile, display, reset, or shutdown | Parsing, typing, or target policy |
| `CompilationRequestContext` | Request output, deadlines, cleanup, source-provider lifetime, output transaction | Long-lived parser or typer state |
| `CompilerSourceProvider` | The request API for lookup, reads, parsing, reporting, and success-only publication | Haxe dependency or target semantics |
| `CompilerSourceResolver` | Exact-case lookup order and the observations that prove its answer | Cache storage |
| `CompilationServerSourceCache` | In-memory entries, hit/miss facts, staged publication, reset, and estimated-size eviction | Mutable request compiler state |
| `ResolverStage` and `ModuleLoader` | Which modules the current request needs | Persistent storage or eviction |
| `ParserStage` | Turning filtered source into the Haxe parser model | Cross-request publication |

`CompilerSourceProvider` is one concrete Haxe class with typed callbacks. The
direct compiler connects those callbacks to ordinary filesystem and parser
operations; a server request connects them to its validated cache view. This
shape is intentional: the current Reflaxe OCaml interface representation is not
safe when an implementing class also stores data fields, because the two
generated OCaml records disagree about where method values live. Typed
callbacks preserve one provider API without giving cache code compiler
ownership. A small native probe and the complete public server fixture cover
both callback arrangements.

## Exact identities

### Source text

The key includes:

- the normalized absolute logical file path; and
- the complete source content read by the parser.

hxhx currently reads the file on every request. A timestamp is only filesystem
metadata and does not prove content equality. Rewriting a file with equal bytes
therefore remains a hit; changing bytes is a miss.

The in-memory key stores the length before every value. For example,
`["ab", "c"]` and `["a", "bc"]` remain different even when a value contains a
separator. This keeps the first cache collision-free without running a
pure-Haxe cryptographic hash for every module lookup. The original SHA-256
version was correct but made generated OCaml bytecode spend almost all request
CPU in boxed 32-bit hash operations. A future persistent cache will need a
measured native hashing adapter plus collision validation; these process-local
strings are not a disk format.

### Module lookup

The lookup question is a Haxe module path such as `pack.Mod.SubType`. The
resolver checks direct files first and then Haxe's secondary-type fallback:

```text
pack/Mod/SubType.hx
pack/Mod.hx
```

For each ordered class-path position examined, the exact revision records whether the
required exact filename is missing, is not a file, or selects a file. The
selected absolute path is recorded when one wins. This detects:

- a new file in an earlier class path;
- deletion or rename of the selected file;
- filename-case changes; and
- class-path precedence changes that select a different source.

Unrelated filenames do not invalidate the answer. Request-private empty
generated-source directories also do not create false misses merely because
their temporary directory name changed.

The filesystem observation is still performed before a lookup hit is accepted.
Watchers or directory-generation hints may later avoid that work, but only if
overflow, uncertainty, and restart fall back to exact observation.

### Parsed module

The parser key includes:

- normalized logical file path;
- source after the current request applies conditional compilation;
- a parser schema label;
- the compiled parser frontend; and
- parser-selection environment flags that may change inside one process.

This means a `-D` change can reuse equal on-disk bytes while correctly missing
the parsed-module cache when it changes the active `#if` branch.

The parser model contains arrays that Haxe types cannot make deeply read-only.
hxhx therefore records a deterministic structural description after parsing,
checks it again before publication, and checks it on every reuse. A changed tree
fails the request instead of becoming a stale hit.

## Publication and failure behavior

New results stay private to the request while compilation runs. The request
validates them after compiler work and registered cleanup succeed, commits its
generated output, and only then publishes the reusable entries.

The following publish nothing:

- source or type errors;
- malformed input;
- cancellation or deadline expiry;
- macro, plugin, target, or cleanup failure; and
- a parser-tree integrity mismatch.

Generated target files follow the separate output transaction. Parser-tree
integrity is checked before target output replacement. Cache entries become
visible only after the output transaction succeeds, so an output-publication
failure discards the request's candidate entries. Existing good cache entries
and generated output remain intact.

Requests are currently serialized. Eviction therefore runs between requests,
after no request is borrowing a parser object.

## Memory and reset

The cache uses deterministic least-recently-used eviction against a retained
size estimate. The default estimate budget is 64 MiB and can be configured with
`HXHX_NATIVE_SERVER_SOURCE_CACHE_BYTES`.

This is not a total-process memory limit. Parser object sizes are estimated, and
the compiler, OCaml runtime, macros, targets, and generated output can retain
additional memory. Exact retained-memory measurement and long-run server budgets
remain later acceptance work.

Reset clears all reusable entries without stopping the server:

```bash
hxhx --connect 6000 --hxhx-server-control reset
```

Restarting the process is always cold. No persistent on-disk compiler cache is
implemented.

## Required behavior tests

`npm run test:m14:compilation-server-source-cache` covers:

- cold and unchanged warm requests;
- rewriting equal bytes;
- A-to-B-to-A source edits;
- malformed requests followed by recovery;
- explicit reset;
- parser input changed by `-D`;
- cancellation before compiler work;
- parser-tree mutation rejection;
- exact filename case and secondary-type fallback;
- a source file created after an earlier miss in the same request;
- higher-priority class-path shadowing, rename, and restoration;
- generated JavaScript changing with the winning source and returning to the
  previous bytes when the previous source wins again; and
- forced eviction followed by correct recomputation.

Bootstrap regeneration, the generated OCaml build, and the public socket/stdio
fixture pass for this implementation. The wider hxhx target suite remains a
critical-phase closure gate rather than an every-edit inner-loop command.

## Performance contract

The product goal is the complete edit-to-diagnostics and edit-to-runnable-result
loop, not the largest possible hit counter. TypeScript incremental compilation
and Go build/test caching are comparison baselines; hxhx should be competitive
or better on representative Haxe compiler, plugin, target, and application
workloads where its architecture permits.

Measurements must separate:

- request and source probing;
- module discovery and parsing;
- typing and macro work;
- target planning and generation;
- unchanged-file writes;
- Dune compile/link reuse; and
- executable load/start.

Across two final local macOS OCaml-bytecode fixture runs, the direct request
took 11,134–12,196 ms, a cold server request took 10,606–10,859 ms, the first
warm request took 3,654–3,773 ms, and the repeated warm stability requests took
3,648–3,789 ms. Reset returned the next request to 10,677–10,838 ms. This is
report-only evidence from one tiny fixture, not a TypeScript/Go comparison or a
shipping threshold. It proves that parser reuse is observable; typed-module
and dependency-graph reuse is still expected to deliver the larger
representative-workload win.

## Next layers and hard boundaries

The next planned steps are dependency-edge observation and sealed typed-module
reuse. A **sealed typed module** means a completed, validated type-checking
result that later requests can read but not mutate. It needs deterministic
public-API, implementation, body, configuration, macro, and dependency
revisions before admission.

Macros, compiler transforms, native plugins, target plans, display recovery,
parallel requests, and persistent storage remain outside this first cache.
Uncertainty is always a miss. No later layer may make the printer, transport, or
cache catalog a second owner of Haxe behavior.

## Related tracks

- `haxe_ocaml-850ii.32`: native hxhx server and cache.
- `haxe_ocaml-850ii.33`: safely use upstream Haxe 4.3.7's existing compilation
  server with complete Reflaxe target state.

The two hosts keep separate compiler caches. They should eventually provide the
same complete, revisioned target/plugin input to Reflaxe-based compilers.
