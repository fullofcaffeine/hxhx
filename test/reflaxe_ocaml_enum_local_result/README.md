# Enum result retained across an effect

`Reader.parse` saves an enum result, prints `checked`, and returns the saved
value. Its caller prints `ok`. The expected output is checked against upstream
Haxe 4.3.7 and the compiled native OCaml executable.

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

Runtime output alone does not prove type preservation. The command also checks
the inferred OCaml result type and rejects the known unsafe local conversion.
Review the generated `Reader.ml` when changing the representation implementation.

This regression currently fails on the erased result type. Task
`haxe_ocaml-xkquu` owns the compiler repair and required test-group integration.
The fixture does not establish full compiler or typed JSON acceptance.
