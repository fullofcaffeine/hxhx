# Enum result retained across an effect

`Reader.parse` runs one observable call, saves an enum result, runs another
observable call, and returns the saved value. Its caller prints `ok`. The
expected output is checked against upstream Haxe 4.3.7 and native OCaml.

Run from the repository root:

```sh
npm run test:reflaxe-ocaml:enum-local-result
```

The command requires the pinned Haxe/Reflaxe environment, OCaml, and Dune.
Each native generation has a five-minute deadline. The retained-result build
disables expression preprocessing to keep the same local shape as the full
compiler source build. The local-function build uses normal preprocessing.
The Core packaging test group runs this command through `npm test`.

The first check verifies the enum's native type identity, module naming,
registry copies, and program reset. It rejects nullable and generic types and
edited identity records. These checks describe the target type; they do not
prove that a particular call or local already contains that native value.

The next checks classify a small set of enum-producing bodies without changing
generated code. The set includes retained locals, guarded completion, explicit
throws, and multiple closed call dependencies. The checks compare real
preprocessed bodies with the initial classification. They use both expression
preprocessing modes and reversed declaration order. Method result admission
excludes casts, replacement, capture, cycles, foreign receivers, nullable
results, and generic variants. Changed final callees and stale program
revisions fail.
Repeated queries do not rescan bodies or dependency edges.

Runtime output alone does not prove type preservation. The command also checks
the inferred OCaml result type and rejects the known unsafe local conversion.
Review the generated `Reader.ml` when changing the representation implementation.

`EnumProducerMutationProbe` checks a separate local-function contract. An
unchanged function can use its own nullable-enum result proof. After direct or
captured assignment, the call must not reuse proof from the previous function.
The native executable must match upstream output for both enum and null results.
The call-plan fixture separately checks that mutation prevents proof reuse.

The replacement functions are declared locally. Passing an enum-returning
callback through a function argument exposes another conversion gap, tracked
in `haxe_ocaml-3fm6v`. This fixture does not claim that boundary works.

Task `haxe_ocaml-xkquu` owns this compiler contract. The fixture does not
establish full compiler or typed JSON acceptance.
