# Project macro modules: first safe native loading path

Status: implemented and verified for `haxe_ocaml-vhk47.3`
Risk level: `thinking:xhigh`
Decision date: 2026-07-14

## The user problem

A Haxe project can define a macro such as `projectmacro.ProjectMacro.message()`.
That function runs while the project is being compiled and returns Haxe code that
replaces the call in the finished program.

`hxhx` already runs a small set of built-in macros in two ways:

- **in-process**: the macro runs inside `hxhx`;
- **external host**: the macro runs inside the reusable `hxhx-macro-host`
  process.

Before this slice, neither path loaded an ordinary project's Haxe-authored
macro. The implemented proof now runs one real project macro in both modes
without asking the installed upstream `haxe` compiler (stage0) to do the work.

## Decision in plain language

Keep the reusable macro host generic. Compile project macro code into a small,
separate OCaml plugin, then load that plugin into either macro runtime.

The path will be:

1. The project macro is written in Haxe.
2. The current `hxhx` candidate compiles that Haxe source with its normal Stage3
   emitter.
3. Stage3 writes a tiny generated plugin entrypoint that registers one exact
   macro expression and its Haxe handler.
4. Dune builds the same generated output as bytecode (`.cma`) and native
   (`.cmxs`) OCaml plugins.
5. A receipt records which compiler candidate built it, its plugin ID, its ABI
   versions, the expression it provides, and its SHA-256 file digest.
6. Before loading, both macro modes validate the same receipt and file.
7. The compiler replaces the macro call with the expression text returned by
   the loaded Haxe handler.

The generic host is built once and reused. Only the small project module changes
when project macro code changes.

## Why this uses the existing native-module boundary

The repo already has a narrow loading boundary:

- `NativeMacroModuleDynlink` loads an OCaml plugin;
- `NativeMacroModuleHost` stores exact expression handlers;
- `NativeMacroModuleHostAbi` rejects incompatible or malformed
  registrations;
- the RPC host already exposes `macro.loadNativeModule` and
  `macro.runNativeExpr`.

Using that boundary is smaller and safer than building a second macro host for
every project. It also lets the in-process and external-host modes execute the
same generated plugin instead of maintaining two translations of the macro.

## What the architecture probe found

The pre-implementation probe used only throwaway files under `.tmp/`; no
generated OCaml was edited or committed.

- Upstream Haxe plus `reflaxe.ocaml` generated the expected Haxe handler, but a
  normal "run the Haxe main" plugin linked common runtime modules already loaded
  by the host. OCaml correctly rejected the duplicate modules.
- Adding a module prefix exposed an existing prefixing gap in a referenced
  runtime module, so prefixing the entire generated program is not a safe local
  solution.
- Filtering common modules still left the generic run-main entrypoint depending
  on unrelated runtime registry code.
- Stage3's existing provider-plugin entrypoint avoided those collisions because
  it linked only code reachable from a tiny explicit registration call.
- A Stage3-generated project module loaded successfully, but its current generic
  plugin entrypoint registered no macro expression. That is the one missing
  connection this slice will add.

This evidence points to a minimal generated registration entrypoint. It does not
justify a broad `@:native` redesign, a new compiler IR, or copying the upstream
macro implementation.

## The bounded Stage3 entrypoint

Stage3 plugin output accepts one explicit project-macro registration for this
pilot:

- plugin ID;
- exact expression text, for example
  `projectmacro.ProjectMacro.message()`;
- Haxe handler path, for example
  `projectmacro.ProjectMacroNative.nativeExpansion`.

The generated OCaml entrypoint does only this conceptual work:

```text
register(plugin ID, exact expression, call generated Haxe handler)
```

It must not run the project's Haxe `main`, link an entire second copy of the
runtime, use reflection, or edit generated `.ml` after emission. The existing
backend-provider registration mode and the new macro registration mode are
mutually exclusive so one plugin has one clear job.

This first slice intentionally supports one no-argument handler returning Haxe
expression text. More arguments, macro hooks, and the full `haxe.macro` runtime
surface require later evidence and separate beads.

## One Haxe fixture, two kinds of proof

The repo-owned fixture keeps the expected value in Haxe source:

- in an upstream macro context, `message()` returns a real `haxe.macro.Expr`;
- in the promoted native module, `nativeExpansion()` returns equivalent Haxe
  expression text.

Upstream Haxe 4.3.7 is used only as a black-box behavior oracle. Its compiler
source and tests are not copied. The focused app must produce the same runtime
output through:

- upstream Haxe 4.3.7;
- native `hxhx` with the in-process macro runtime;
- native `hxhx` with the reusable external macro host.

## Receipt and trust checks

The environment variable `HXHX_NATIVE_MACRO_MODULE_RECEIPT` selects an optional
JSON receipt. The receipt is data, not executable code. Its first schema records:

- schema name;
- compiler-candidate commit;
- plugin ID;
- native macro ABI version;
- macro API version;
- exact expressions provided;
- bytecode and native plugin paths and SHA-256 digests.

Both runtime modes use the same validator. Loading stops with a clear error when:

- the receipt or plugin file is missing;
- the schema or ABI version is unsupported;
- the current candidate commit is absent or different;
- the plugin path escapes the receipt directory;
- the digest for the selected bytecode/native artifact differs from the actual
  file;
- the plugin registers a different or duplicate expression;
- the expression would override an existing built-in/generated handler.

This is build provenance and integrity checking, not cryptographic signing. A
future public package format may add signatures, multiple modules, or embedded
candidate identity; this focused path must not pretend to provide those yet.

## Dispatch rules

Expression lookup remains deterministic:

1. built-in/generated handlers keep their existing priority;
2. an exact expression registered by the validated project module may run;
3. anything else fails as unregistered for expression expansion.

There is no substring match, reflection fallback, or silent stage0 fallback.
Loading a project module must not change the behavior of macros it did not
register.

## Source ownership

The four existing Haxe wrappers for the native-module ABI are shared compiler
infrastructure, not macro-host application code. Move them, without changing
their package names or behavior, from `packages/hxhx-macro-host/src` to
`packages/hxhx-core/src`. Both `hxhx` and `hxhx-macro-host` already include the
core classpath.

Tracked OCaml snapshots may change only by running the official regeneration
scripts. Direct edits to generated files such as
`packages/hxhx/out/*.ml`, `packages/hxhx/bootstrap_out/*.ml`, or
`packages/hxhx-macro-host/bootstrap_out/*.ml` are forbidden.

## Validation and evidence

The focused runner must:

1. build `hxhx` and the generic macro host with stage0 forbidden;
2. generate the plugin from Haxe through that `hxhx` candidate;
3. build both plugin forms from the generated OCaml without modifying it;
4. write and validate the receipt;
5. compile and run the fixture app through both macro runtime modes;
6. run the upstream Haxe 4.3.7 oracle separately;
7. prove missing, changed-digest, wrong-candidate, wrong-ABI, and unregistered
   expression failures;
8. leave an artifact summary that identifies the candidate and digest.

The weekly macro parity workflow has a separate project-macro job.
`FULL1_MACRO_PARITY:PASS` is emitted only when the existing two-mode matrix and
this project-macro job all pass.

## Stop rules

Stop this implementation and open a follow-up design bead if any of these become
necessary:

- editing generated OCaml by hand;
- copying or translating upstream compiler/test code;
- rebuilding the generic macro host once per project;
- accepting modules without candidate, ABI, and digest checks;
- adding broad reflection-based macro dispatch;
- changing general macro AST semantics or multiple backend layers;
- growing the pilot into a package manager or multi-module dependency solver.

## Second-pass review

The second pass checked the proposal against the Full1 release, provenance,
bootstrap, and architecture rules.

- **Behavior:** upstream Haxe remains the oracle; the fixture is repo-owned.
- **Provenance:** implementation is behavior-driven and Haxe-authored; no
  upstream implementation/test material enters the repo.
- **Bootstrap:** plugin generation, host build, and app compile all have an
  explicit stage0-forbidden path.
- **Artifact identity:** candidate, ABI, expression list, path containment, and
  SHA-256 are checked before activation.
- **Architecture:** the generic host, project module, and compiler frontend keep
  separate responsibilities; the existing dynlink ABI is reused.
- **Generated code:** only official Stage3 emission and regeneration are allowed.
- **Scope:** one exact no-argument expression macro is enough to prove the seam;
  it is not Full1 macro closure by itself.
- **User claims:** this improves Full1 evidence plumbing but does not yet raise a
  README production-readiness percentage.

External GPT 5.5 Pro escalation was deliberately not used for this slice. The
architecture probe produced a bounded, existing ABI seam with clear invariants
and stop rules. The earlier whole-repository GPT review supports explicit
macro/plugin artifact boundaries, but it is not treated as implementation or
oracle evidence.

Decision: the bounded path above is accepted. Focused evidence and the strict
aggregate are both green, so `haxe_ocaml-vhk47.3` may close.

## Verification result

Exact-commit Macro Runtime Parity run `29349360051` passed at
`3806c61195cb9788b0db9521a869208792ae3247`.

In plain language, the clean Linux runner:

1. built the current `hxhx` candidate and reusable macro host with stage0
   forbidden;
2. generated one repo-owned Haxe macro as bytecode and native OCaml plugins;
3. checked the candidate, ABI, expression, paths, and file digests in its
   receipt;
4. loaded and ran the macro in both native runtime modes;
5. passed the wrong-candidate, wrong-ABI, changed-digest, changed-expression,
   missing-artifact, and missing-receipt checks;
6. kept both established macro-runtime jobs green; and
7. emitted `PROJECT_MACRO_MODULE:PASS` and `FULL1_MACRO_PARITY:PASS`.

The project evidence is artifact `8317497905`, digest
`sha256:aa3c83f4b56e9cba8c1dd661e0319928447ccbd56620f298b778cc1a42248766`.
The aggregate summary is artifact `8317500638`, digest
`sha256:b294cbc5c7b9383cf9d4fb1494cc0ae0ecd4570253f0bc601e7165573b78d839`.

This is a first loading-path proof, not complete support for every project
macro. The README production-readiness bars remain unchanged because Full1
still needs native eval, strict suite/target, performance, and release-candidate
evidence.
