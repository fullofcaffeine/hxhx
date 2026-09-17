# Enum result retained across an effect

`Reader.parse` runs one observable call, saves an enum result, runs another
observable call, and returns the saved value. Its caller prints `ok`. The
expected output is checked against upstream Haxe 4.3.7 and native OCaml.

Run from the repository root:

```sh
bash test/reflaxe_ocaml_enum_local_result/test.sh
```

The command requires the pinned Haxe/Reflaxe environment, OCaml, and Dune.
Native generation has a five-minute deadline. Expression preprocessing is
disabled to retain the same local shape as the full compiler source build.

The first check verifies the enum's native type identity, module naming,
registry copies, and program reset. It rejects nullable and generic types and
edited identity records. These checks describe the target type; they do not
prove that a particular call or local already contains that native value.

The next checks classify a small set of enum-producing bodies without changing
generated code. The set includes retained locals, guarded completion, explicit
throws, and multiple closed call dependencies. The checks compare real
preprocessed bodies with the initial classification. They use both expression
preprocessing modes and reversed declaration order. Casts, replacement,
capture, cycles, foreign receivers, nullable results, and generic variants stay
outside this contract. Changed final callees and stale program revisions fail.
Repeated queries do not rescan bodies or dependency edges.

Runtime output alone does not prove type preservation. The command also checks
the inferred OCaml result type and rejects the known unsafe local conversion.
Review the generated `Reader.ml` when changing the representation implementation.

Task `haxe_ocaml-xkquu` owns this compiler contract. The fixture does not
establish full compiler or typed JSON acceptance.
