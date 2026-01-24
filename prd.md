PRD: reflaxe.ocaml (Haxe → OCaml target)
0. Glossary

PRD (Product Requirements Document): what we’re building, why, and how we’ll ship it in milestones.

AST (Abstract Syntax Tree): a structured representation of code.

IR (Intermediate Representation): an internal AST between Haxe and OCaml output.

DCE (Dead Code Elimination): removing unused code (Haxe compiler feature).

FFI (Foreign Function Interface): calling native OCaml from generated OCaml.

Stdlib (Standard Library): Haxe’s cross-platform standard library vs OCaml’s Stdlib.

1. Context and motivation
Why an OCaml target?

Developer value: compile Haxe to native OCaml for fast binaries and easy interop with OCaml’s ecosystem.

Strategic value: enable a realistic path to “Haxe-in-Haxe” by compiling a Haxe-written compiler back into OCaml (the language the current Haxe compiler is implemented in). This is explicitly the first long-term goal described in HaxeFoundation/haxe issue #6843.

Does “Haxe → OCaml” automatically mean “Haxe-in-Haxe”?

Not by itself.

 

An OCaml backend is a key enabling step (it becomes the “stage1 output format”), but Haxe-in-Haxe also requires:

a compiler implementation written in Haxe (manual rewrite or translation),

a bootstrap pipeline (stage0 → stage1 → stage2),

and enough runtime/stdlib/FFI to run the compiler (file IO, args, maps, etc.).

Issue #6843 outlines a concrete staged plan: first get the compiler written in Haxe generating OCaml code, with some parts (lexer/parser) left as extern/native OCaml initially.

Target baseline

Haxe version: 4.3.7 (bugfix release, May 9, 2025).

Reflaxe: use Reflaxe as the compiler framework (recommended install is reflaxe 4.0.0-beta).
Reflaxe-based projects commonly target “Haxe 4.3+”, so Haxe 4.3.7 is a reasonable compatibility target.

Prior art you shipped (Elixir target)

Your Elixir compiler repo shows patterns worth copying almost 1:1:

Early bootstrap macro that injects classpaths safely (compiler code and staged std overrides).

Compiler init macro that registers the compiler with ReflectCompiler.AddCompiler.

TypedExpr preprocessors to erase Haxe’s desugaring temps and keep idiomatic output.

Strong IR (ElixirAST) + Builder → Transformer → Printer pipeline.

Instance-based CompilationContext to avoid static cross-contamination.

Output iterator responsible for file naming + writing + sourcemaps + extra generated files.

This PRD follows those patterns, but adapts them to OCaml’s semantics and build tooling (dune/opam).

2. Product goals
G1 — A real OCaml target (not “pretty printing”)

Generate compilable .ml files (and optionally .mli).

Support Haxe programs beyond toy examples: modules, functions, enums, classes, arrays, exceptions, IO.

Integrate with OCaml tooling (at minimum: a dune project scaffold).

G2 — Two-tier experience: portability first, idioms available

You want both:

Portable Haxe code (that compiles across targets, including reflaxe.ocaml)

OCaml-idiomatic code paths (when devs opt-in)

So we will define two “surfaces”:

Portable surface: Haxe stdlib semantics preserved (even if output is less “pure OCaml”).

OCaml surface: an ocaml.* Haxe API layer giving access to native OCaml idioms (lists/options/results/labelled args/modules) with compiler support for emitting native constructs.

The compiler must allow mixing both in one program.

G3 — Bootstrapping path: Haxe-in-Haxe as the “killer app”

Deliverables must steadily move toward the #6843 plan:

OCaml target can compile a non-trivial Haxe codebase.

Provide an OCaml-interop story (externs) for existing OCaml libs (ExtLib etc.).

Provide ML-friendly primitives (lists/options) so translated compiler code remains clean.

Later: compile an early “Haxe compiler in Haxe” prototype to OCaml and run it.

Issue #6843 specifically calls out the need for:

“class representation similar to C”

extern access to ExtLib (PMap etc.)

proper immutable list support, including pattern matching shapes.

3. Non-goals (initially)

To keep milestones sane:

Full Haxe reflection parity (Type, Reflect) in milestone 1–2.

Perfect semantic equivalence for every edge case (e.g., exact 32-bit overflow semantics).

Full OCaml “type wizardry” support (GADTs) from Haxe syntax. The goal is interop and generation, not reproducing every OCaml type feature in Haxe’s type system.

4. Success criteria
“Target is real”

haxe -lib reflaxe.ocaml -D ocaml_output=out -main Main emits .ml.

dune build succeeds and produces an executable.

The executable runs and matches expected outputs for a growing conformance suite.

“Portable surface works”

Common Haxe stdlib usage compiles: Array, String, Map, Bytes, Sys, FileSystem, File.

“OCaml surface works”

ocaml.List, ocaml.Option, ocaml.Result interop with real OCaml lists/options/results in generated code.

Extern binding can call existing OCaml modules (e.g., ExtLib’s PMap).

“Bootstrapping is plausible”

A “mini compiler” subset project (in Haxe) can compile to OCaml and run.

Clear path to integrate ML2HX translation flow as described in #6843.

5. High-level architecture
5.1 Repository layout (mirrors your Elixir patterns)
reflaxe_ocaml/
  src/
    reflaxe/ocaml/
      CompilerBootstrap.hx     (macro)
      CompilerInit.hx          (macro)
      OcamlCompiler.hx         (GenericCompiler)
      CompilationContext.hx    (instance state)
      OcamlOutputIterator.hx
      preprocessor/
        TypedExprPreprocessor.hx   (infra temp elimination)
      ast/
        OcamlAST.hx
        OcamlASTBuilder.hx
        OcamlASTTransformer.hx
        OcamlASTPrinter.hx
        context/
        builders/
        transformers/
        naming/
        types/
      runtimegen/
        DuneProjectEmitter.hx
        RuntimeCopier.hx
  std/
    ocaml/                    (Haxe-visible OCaml APIs, externs, abstracts)
    _std/                     (Haxe stdlib overrides for this target)
    runtime/                  (OCaml .ml runtime support files to copy)
  haxe_libraries/
    reflaxe.ocaml.hxml
  extraParams.hxml
  haxelib.json
  test/

5.2 Compilation pipeline (same conceptual phases as Elixir)

TypedExpr preprocess

Remove Haxe-internal temps (_g, g1, etc.) introduced by desugaring.

Preserve high-level shapes that map cleanly to OCaml match, let, etc.

Builder (TypedExpr → OcamlAST)

Convert each TypedExpr node to a strongly-typed OCaml IR node.

Transformer passes (OcamlAST → OcamlAST)

Target-specific rewrites:

portable semantics (refs/mutation),

idiomatic rewrites (match/list/option sugar),

simplifications, alpha-renaming.

Printer (OcamlAST → string)

Pretty printing with stable formatting and precedence handling.

Output iterator

File naming, directory structure, optional package alias files.

Copy runtime .ml files into output.

Emit dune scaffolding (configurable).

6. Core design decisions (the “hard parts” called out explicitly)
6.1 Haxe packages → OCaml modules (namespacing)

OCaml modules are not inherently hierarchical by directory. We want readable output and collision-free compilation.

 

Plan: “flat modules + generated alias modules”

Every Haxe module path becomes a unique flat OCaml module name:

haxe.io.Path → Haxe_io_Path

Then we generate alias “package modules” that provide dot-path access:

Haxe module: module Io = Haxe_io

Haxe_io module: module Path = Haxe_io_Path

This gives you:

Internal uniqueness (Haxe_io_Path),

External readability (Haxe.Io.Path),

And requires no dune packing tricks.

Implementation

During onOutputComplete, build a package tree from emitted module names.

Emit additional alias .ml files as needed.

Provide a define: -D ocaml_emit_package_aliases=0/1 (default 1).

Edge cases

Name collisions with reserved words or existing modules: resolve with suffix _.

Two modules differing only in case: rare in Haxe packages but must be detected to support Windows FS (case-insensitive).

6.2 Mutability model (Haxe mutable-by-default vs OCaml immutable-by-default)

This is the single most important semantic mismatch.

 

Portable semantics baseline

Local vars and fields can be mutated in Haxe.

In OCaml:

Use let for immutable locals

Use ref for mutable locals (x := ..., !x)

Use mutable record fields for mutable fields (obj.field <- v)

Mutability inference (must-have)
In the Builder (or an early Transformer pass):

For each local variable:

If assigned after initialization → represent as RefVar.

Else → normal immutable binding.

For each captured variable mutated inside a closure → force ref.

This yields idiomatic code and correctness.

 

Why not “wrap captured vars in Array” (a common trick)?
It works, but looks cursed in OCaml. We’ll generate ref instead, which is the canonical OCaml idiom.

6.3 Class representation (“C-like” as issue #6843 suggests)

Issue #6843 suggests: represent classes like C (data structure for fields; methods take self as first arg).

 

Milestone approach

Early milestones: implement a conservative class model that covers:

static fields/functions,

instance fields,

instance methods,

constructors,

no inheritance initially (or limited).

Representation
For a Haxe class Foo:

type foo = {
  mutable x : int;
  mutable y : string;
}

let foo_new x y = { x; y }

let foo_bar (self: foo) (n:int) : int =
  self.x + n


Methods become functions: foo_bar self arg.

Field access uses record fields.

If we want more namespacing, we keep these inside module Foo (file already defines module).

Inheritance & interfaces (later)

Phase 1: disallow or minimal support (compile error if used).

Phase 2: embed parent record + manual upcast.

Phase 3 (optional): vtable-based dispatch for dynamic polymorphism.

6.4 switch and pattern matching

OCaml match is great, but Haxe switch has semantics that must be preserved:

order matters,

guards may exist,

Haxe patterns differ (especially for enums),

Haxe allows switch as expression.

Plan

Convert Haxe enum switch to OCaml match.

Convert primitive switch to chained if or match depending on pattern support.

Preserve “switch-as-expression” by emitting match ... with ... returning a value.

Must-do preprocessor
Like your Elixir compiler, erase Haxe’s infra vars around switch so we can compile directly:

Haxe internal: var _g = expr; switch(_g) ...

Desired: match expr with ...

6.5 Nullability: null vs option

OCaml doesn’t have null (in the normal type system). This is both a pain and a gift.

 

Policy

Map Haxe Null<T> to OCaml T option (idiomatic, safe).

Map Haxe non-nullable types to non-option.

Map Haxe Dynamic/unknown to Obj.t (or a custom dynamic runtime type).

Compiler responsibilities

Rewrite null literal:

if expected type is option → None

else (Dynamic) → runtime HxDyn.null (or Obj.magic 0, but don’t).

Rewrite x == null properly depending on x type.

6.6 Exceptions: Haxe can throw anything

Haxe: throw anyValue; catch(e:Dynamic) ...

 

OCaml: only exn can be raised/caught.

 

Plan

Define runtime exception:

exception Hx_throw of Obj.t


throw v → raise (Hx_throw (to_obj v))

catch(e:Dynamic) → with Hx_throw v -> ...

Typed catches (catch(e:SomeType)) become:

catch-all + runtime type test + rethrow, or

pattern match if it’s a known exception mapping.

6.7 OCaml interop (externs + idioms)

Need to call existing OCaml libs, per #6843 (ExtLib PMap).

 

Rules

Haxe extern class with @:native("PMap") maps to OCaml module PMap.

Static functions map to module functions.

Extern instance methods can map to functions taking self.

Labelled and optional arguments
OCaml has ~label: and ?opt: args. Haxe doesn’t.

 

We’ll support via metadata + compiler printing:

On extern function params: @:ocamlLabel("label")

On optional params: Haxe ?x:T emits ?x:T in OCaml if target is labelled; otherwise an option.

This is a later milestone, but it’s key for “native idioms”.

7. ocaml.* Haxe API surface (idioms without killing portability)
Guiding principle

Portable code doesn’t import ocaml.*.

OCaml-specific code lives behind #if ocaml or inside ocaml.* abstractions.

Generated OCaml can still be idiomatic for portable code, but the “OCaml surface” unlocks more.

7.1 MVP ocaml.* package

ocaml.List<T>

Provide a Haxe type that compiles to OCaml 'a list.

Support construction and pattern matching.

Implementation strategy

Provide Haxe enum OcamlList<T> { Nil; Cons(head:T, tail:OcamlList<T>); }

Annotate with @:ocamlNativeList

Compiler special-cases:

type emission: 'a list

Nil → []

Cons(h,t) → h :: t

pattern Cons(h,t) → h :: t

This hits the #6843 “list support” requirement without changing Haxe syntax (we cannot add :: to Haxe itself).

ocaml.Option<T> / ocaml.Result<Ok,Err>
Same strategy: compile to option and result and print Some/None, Ok/Error.

ocaml.Ref<T>
Abstract over T in Haxe, compiled to T ref in OCaml with ref, !, :=.

ocaml.Module extern helpers
Make extern module mapping ergonomic:

@:native("Stdlib") extern class Stdlib { ... }

__ocaml__ escape hatch
untyped __ocaml__("...") injects raw OCaml when needed (like your __elixir__ pattern).

7.2 Portability story

Everything in ocaml.* is “opt-in and non-portable”.

Portable apps can remain target-agnostic by avoiding these imports.

For shared libs, provide two layers:

mylib.core portable

mylib.ocaml ocaml-specific optimized bindings

8. Haxe stdlib support strategy
8.1 Use staged overrides like your Elixir target

std/_std/ contains Haxe files that override selected standard modules for this target.

They keep Haxe types/signatures stable, but implement via runtime calls or compiler intrinsics.

This pattern is proven in your Elixir compiler (std/_std/Type.hx delegating to a runtime implementation). We’ll replicate it for OCaml.

8.2 Runtime .ml modules

We ship OCaml runtime helpers inside the haxelib under std/runtime/, then copy them into the output directory.

 

Core runtime modules (initial set):

HxRuntime.ml: shared helpers, exceptions, dynamic boxing.

HxArray.ml: resizable array semantics for Haxe Array<T>.

HxString.ml: string helpers used by overrides (substr, split, etc.).

HxBytes.ml: bytes implementation for haxe.io.Bytes.

HxSys.ml: args/env/time/exit.

HxFile.ml / HxFileSystem.ml: implement sys.io.File and sys.FileSystem.

Later:

HxMap.ml: haxe.ds.Map semantics.

HxType.ml / HxReflect.ml: partial reflection support.

8.3 What to implement first (compiler bootstrap-driven)

If the killer app is Haxe-in-Haxe, prioritize the std surface the compiler needs:

Sys, FileSystem, File, Path, Bytes, StringTools,

arrays and maps,

regex maybe (EReg).

9. Build output (dune-first)
9.1 Default output

Emit .ml files to -D ocaml_output=<dir>

Copy runtime .ml files into <dir>/runtime/ or <dir>/hx/.

9.2 Generate dune scaffolding

Add -D ocaml_dune=1 (default 1 for convenience):

dune-project

dune file that builds:

a library for runtime,

and an executable for -main.

Configurable defines:

-D ocaml_dune_libraries=unix,str,extlib,...

-D ocaml_entry_module=Main (or inferred from Haxe -main)

For the haxe-in-haxe path, dune integration is especially relevant because the current Haxe compiler build uses OCaml tooling and libraries.

10. Haxe-in-Haxe bootstrapping plan (aligned to issue #6843)

Issue #6843’s plan in plain steps:

Create an OCaml backend (this project).

Convert the compiler code from OCaml → Haxe (ML2HX), keeping lexer/parser as extern OCaml initially.

Compile the Haxe compiler (now written in Haxe) back to OCaml and build it.

Practical pipeline (staged compiler bootstrapping)

Stage0: existing haxe binary (OCaml compiler).

Stage1 build: use Stage0 to compile haxe-compiler-in-haxe sources to OCaml via reflaxe.ocaml, then compile with ocamlopt/dune.

Stage1 run: run Stage1 compiler on its own sources (and on test suites).

Stage2: Stage1 compiles itself again; compare output and behavior.

Why OCaml target helps specifically

The existing compiler ecosystem (including some libs and build scripts) is already OCaml-oriented.

Keeping lexer/parser as native OCaml (initially) is easiest if your target can link to OCaml modules cleanly.

11. Milestones (implementation plan)

Each milestone includes deliverables + “done means”.

Milestone 0 — Project skeleton + Reflaxe wiring

Goals

New reflaxe target repo compiles and registers as a Haxelib.

Minimal “emit one .ml file” works.

Deliverables

CompilerBootstrap.hx: early classpath injection (pattern from your Elixir target).

CompilerInit.hx: registers compiler using ReflectCompiler.AddCompiler.

extraParams.hxml: auto-runs bootstrap + init when -lib reflaxe.ocaml is present (same pattern as your Elixir setup).

haxe_libraries/reflaxe.ocaml.hxml: local dev config.

Key options

fileOutputExtension: ".ml"

outputDirDefineName: "ocaml_output"

fileOutputType: FilePerModule

targetCodeInjectionName: "__ocaml__"

reserved keywords list for OCaml.

Done means

A trivial Haxe program emits at least one .ml file to the output dir.

Milestone 1 — OCaml IR + Printer (no semantics yet, just correctness)

Goals

Build the “ElixirAST equivalent”: OcamlAST + a printer that can render valid OCaml.

Deliverables

OcamlAST.hx: IR node definitions for:

constants, identifiers, let, fun, apply,

if, match, sequence, record, field access, assignment,

type decls, value decls.

OcamlASTPrinter.hx:

precedence-aware printing for expressions,

stable indentation,

module-level items printing.

Done means

Unit tests: given hand-constructed OcamlAST, printer outputs compilable OCaml snippets.

Milestone 2 — TypedExpr → OcamlAST Builder (expressions + functions)

Goals

Compile core expressions and function bodies from TypedExpr.

Deliverables

TypedExprPreprocessor.hx:

at least infra-temp elimination around switch and block temps.

OcamlASTBuilder.hx with modules similar to your Elixir builder split:

LiteralBuilder, VarBuilder, BinopBuilder, CallBuilder,

ControlFlowBuilder (if/while/for),

SwitchBuilder (to match),

BlockBuilder (sequence / let ... in).

CompilationContext.hx:

variable rename map,

mutability tracking (assigned vars),

current module name.

Done means

Can compile a small Haxe program with functions, arithmetic, if, while, switch, arrays (even stubbed).

Milestone 3 — Mutability inference + closures (correct semantics)

Goals

Correct handling of mutable locals and closure capture.

Deliverables

Builder/transform pass that:

detects reassignment and marks vars as ref.

rewrites reads/writes to !x / x := v.

Closure capture logic:

if an outer var is mutated inside closure, hoist it to ref.

Add tests for:

mutation in nested functions,

loops that mutate counters,

captures used by callbacks.

Done means

Generated OCaml behavior matches Haxe for these patterns.

Milestone 4 — Enums, pattern matching, and OCaml-native option/list/result

Goals

Make enums “feel OCaml” (variants), because this matters massively for compiler code.

Deliverables

Enum emission:

Haxe enums → OCaml variant types.

switch on enums → match.

Introduce ocaml.Option, ocaml.Result, ocaml.List Haxe API types (in std/ocaml/).

Compiler special-casing for those types to emit native OCaml option, result, 'a list.

Done means

You can write Haxe like:

switch (xs) {
  case Nil: ...
  case Cons(h, t): ...
}


and it emits OCaml with [] and ::.

This directly targets the #6843 “list support” requirement.

Milestone 5 — Classes (C-like representation) + minimal object model

Goals

Implement the “C-like” class strategy described in #6843.

Deliverables

Class emission:

record type for instance fields (type t = { mutable ... })

constructor function create or <class>_new

method functions method (self:t) args...

static fields as module lets

Method call lowering:

obj.foo(x) → Foo.foo obj x

Field access lowering:

obj.x → obj.x

obj.x = v → obj.x <- v

First cut: no inheritance; error out with a helpful message.

Done means

Real Haxe class-based programs compile and run in OCaml.

Milestone 6 — Stdlib overrides + runtime .ml (portable surface becomes real)

Goals

Make ordinary Haxe code using stdlib compile and run.

Deliverables

std/_std overrides for (minimum viable):

Array, String, haxe.io.Bytes, Sys, sys.io.File, sys.FileSystem

std/runtime/*.ml implementations for the above.

RuntimeCopier step in onOutputComplete to copy runtime files into output.

Done means

A portable Haxe program using:

file IO + args,

arrays + string tools,

maps (basic)
compiles to OCaml and runs correctly.

Milestone 7 — Extern OCaml interop (ExtLib, PMap) + labeled args (partial)

Goals

Unblock the haxe-in-haxe “compiler code wants ExtLib” requirement.

Deliverables

Extern mapping rules:

@:native("PMap") extern class PMap { ... } → calls PMap.add, etc.

Provide a starter extern set for ExtLib modules used by the compiler (at minimum PMap).

Add optional labelled arg support for extern functions via metadata:

@:ocamlLabel("foo") on parameters to emit ~foo:arg.

Done means

A Haxe sample that uses ExtLib via extern compiles and links.

Milestone 8 — OCaml module alias emission + dune scaffolding (polish for real projects)

Goals

Improve ergonomics of generated code and build.

Deliverables

Alias module generation (Haxe.Io.Path style).

Dune project emitter:

default executable and runtime library.

Configurable dune library deps.

Done means

dune build && dune exec works out of the box for generated output.

Milestone 9 — Haxe-in-Haxe prototype path (align to #6843)

Goals

Prove the bootstrapping loop is plausible.

Deliverables

A separate repo (or folder) haxe_in_haxe_proto/:

minimal compiler front-end in Haxe (even if tiny),

compiled to OCaml via reflaxe.ocaml,

runs and performs a small compilation task.

Plan for ML2HX integration:

define the “subset contract” ML2HX outputs (lists, options, maps, modules).

keep lexer/parser as extern OCaml modules initially (as #6843 suggests).

Done means

Stage0 Haxe builds a stage1 OCaml binary from Haxe sources, and stage1 can run a subset compilation pass.

12. Testing strategy (must be first-class)
12.1 Golden tests (snapshot)

For each Haxe input, snapshot the emitted .ml output.

Ensure formatting is stable (or run ocamlformat in CI and snapshot that).

12.2 Behavioral tests

Compile generated OCaml and run it; compare stdout/stderr.

12.3 “Compiler-shaped” tests

Pattern matching heavy code

Immutable lists/options/results

Maps and recursion

Large module graph

13. Key risks and mitigations

OCaml module naming / file layout pitfalls
Mitigation: flat modules + alias modules; detect collisions early.

Mutation correctness (especially closures)
Mitigation: implement mutability inference and closure-capture tracking early (milestone 3).

Stdlib surface area explosion
Mitigation: bootstrap-driven prioritization; staged overrides; runtime modules.

Interop complexity (labelled args, polymorphic variants)
Mitigation: start with externs + simple metadata; build richer macros later.

Bootstrapping scope creep
Mitigation: follow #6843: lexer/parser as extern OCaml initially; don’t rewrite everything at once.

14. Notes on feasibility and “best of both worlds”

You can realistically get:

Portable semantics by using runtime modules and conservative lowering.

Idiomatic OCaml by:

using native variants for enums,

emitting option/list/result when types are explicitly from ocaml.*,

choosing ref/mutable instead of weird boxing tricks,

and removing Haxe desugaring artifacts via preprocessors.

You won’t get “100% idiomatic OCaml” for arbitrary OO-heavy Haxe code without either:

restricting patterns, or

building a full vtable/object model that emulates Haxe’s OO semantics (which can still be clean-ish, but it will never look like hand-written OCaml).

That tradeoff is fine as long as:

portable code is correct,

and the ocaml.* surface gives devs an escape hatch to write “real OCaml” where it matters.

15. Optional references / prior art (non-authoritative)

There are community experiments around “Haxe to OCaml” (e.g., rainyt’s “ocaml-haxe” mentioned on the Haxe forums). This can be useful to skim for ideas, but this PRD assumes a fresh, Reflaxe-based implementation.

can you explaoin to me how the ocaml target would allow the haxe compile rto boostrap itelf in haxe?
Thought for 6m 41s

Bootstrapping is one of those compiler rites-of-passage where you build a ladder… using the ladder.

 

Here’s the core idea, in concrete “stage” terms.

What “bootstrap the Haxe compiler in Haxe” actually means

Today:

The Haxe compiler’s source code is written in OCaml.

You build it with an OCaml toolchain, and you get an executable haxe binary.

Bootstrapping (a.k.a. self-hosting) means:

The Haxe compiler’s source code is written in Haxe.

And you can produce a working haxe compiler binary from that Haxe source, using an existing compiler only for the initial jump-start.

The tricky part is: to compile Haxe source into anything, you need a Haxe compiler already. So you do it in stages.

Where an OCaml target fits: the “stage1” bridge

The Haxe issue you linked (#6843) describes the intended path explicitly:

“The first goal is to have the compiler written in Haxe and generating the corresponding OCaml code…”

That sentence is the whole game.

 

If we have a Haxe → OCaml backend, then:

We can write “Haxe compiler vNext” in Haxe.

Use the existing Haxe compiler (the current OCaml one) to compile that Haxe code to OCaml source.

Then use the OCaml compiler (ocamlopt/dune) to compile the generated OCaml into a native executable.

That executable is a Haxe compiler whose source is Haxe.

 

That’s the bootstrapping bridge.

The “stage0 → stage1 → stage2” pipeline (the standard self-hosting pattern)

Let’s name things:

Stage0 = the current official Haxe compiler executable (built from OCaml sources).

Stage1 = a new compiler executable built from Haxe sources (but compiled by stage0).

Stage2 = the same new compiler compiled by itself (stage1).

Flow:

(1) Stage0 exists today (OCaml implementation)
    OCaml sources --ocamlopt--> haxe(stage0)

(2) Build Stage1 using Stage0 + your OCaml backend
    Haxe compiler sources (written in Haxe)
      --haxe(stage0) + ocaml-target--> generated OCaml sources
      --ocamlopt/dune--> haxe(stage1)

(3) Prove self-hosting by building Stage2 with Stage1
    same Haxe compiler sources
      --haxe(stage1) + ocaml-target--> generated OCaml sources
      --ocamlopt/dune--> haxe(stage2)


If stage2 reliably builds and behaves the same as stage1 (or at least passes the full test suite), you’ve reached a “fixed point”: the compiler can rebuild itself.

 

That’s the classic bootstrap milestone used by C compilers, Rust, etc.

Why OCaml specifically (vs “just compile to C++/JS/…”)

Strictly speaking: an OCaml backend is not the only way to self-host Haxe. You could do “Haxe compiler in Haxe” and compile it to C++, or JavaScript, and ship that.

 

But OCaml is strategically special for Haxe because:

1) It matches the existing compiler ecosystem

The current Haxe build pipeline and dependencies are OCaml-native. Haxe’s own docs send you to OCaml build instructions.

 

So emitting OCaml keeps you “in the same world” for building, linking, CI, performance profiling, etc.

2) It allows incremental porting (huge practical win)

Issue #6843 suggests ML2HX (OCaml-to-Haxe translation) and explicitly says lexer/parsing can stay OCaml “externs” initially:

 

So you can do a hybrid compiler for a while:

most of the compiler logic in Haxe,

some pieces still in OCaml,

linked together because your output language is OCaml.

That hybrid story is much harder if you target, say, C++ or JS.

3) It’s aligned with the “first goal” stated in #6843

The issue calls out specific OCaml-backend requirements that are compiler-driven:

a “C-like” class/structure representation,

extern access to OCaml libs like ExtLib PMap,

real immutable list construction + pattern matching support.

Those aren’t random features; they’re the minimum set to make a Haxe-written compiler pleasant and feasible.

Important subtlety: the OCaml target doesn’t magically make the compiler exist in Haxe

The OCaml target is a necessary enabler, not the whole project.

 

You still need either:

a new compiler implementation written in Haxe, or

an automated translation (ML2HX) to convert existing OCaml compiler code into Haxe.

#6843 explicitly frames it as two efforts that meet in the middle:

“OCaml Haxe target (Haxe-to-OCaml)”

“Automated Haxe compiler OCaml-to-Haxe ML2HX”
…and then “Merge of both” to make it compile/run.

So: OCaml backend + compiler-in-Haxe source together make bootstrapping possible.

What “success” looks like for the OCaml target in bootstrap terms

From a bootstrap perspective, the OCaml backend only needs to support the subset of Haxe that the compiler uses.

 

And #6843 explicitly notes you shouldn’t try to support the whole Haxe language at first (reflection/dynamic-heavy features aren’t required for compiling the compiler).

 

So the backend’s initial “definition of done” can be:

compile the translated compiler code (Haxe) into OCaml,

compile that OCaml into a working binary,

run enough of the compiler to type/compile real code,

then iterate.

One-liner summary

The OCaml target provides a bridge so the existing OCaml-based Haxe compiler can compile a new Haxe-written compiler into OCaml, which the OCaml toolchain can then turn into a runnable haxe binary—allowing the compiler to eventually rebuild itself (stage1 → stage2) and become self-hosting.
