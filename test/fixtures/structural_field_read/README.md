# Retain types when reading structural fields

Shared typing must retain Boolean, nested integer, Dynamic, and nullable field
types. The program reads fields before and after mutation and checks null-safe
access. Its expected output comes from ordinary Haxe behavior.

Run `haxe test/m14_structural_field_read_typing_test.hxml` from the repository
root. The test checks exact shared types, rejects a missing required field in
strict mode, and compares upstream execution with emitted JavaScript.

This validates shared typing. Native OCaml object allocation and typed field
storage remain separate acceptance requirements under `haxe_ocaml-05q72`.
