# Null primitive moves

A `Null<Int>`, `Null<Float>`, or `Null<Bool>` that moves into a non-null `Int`, `Float`, or `Bool` gives the default value (`0`, `0.0`, `false`) when it is null. This is the static-target rule decided on 2026-11-17 (`haxe_ocaml-9cqxj`); JVM, Java, C#, and C++ behave this way.

The fixture covers the moves that do not go through a call or local-storage plan: assignment and local initializer, `Null<Int>` to `Float`, arithmetic and Boolean operands on a value, and a branch join. Function results and operands on planned locals follow in the later steps of `haxe_ocaml-9cqxj.2`.

`haxe --interp` is a dynamic target: it prints `null` and stops at `null + 1`, so `test.sh` compares only the first line, which holds no null.
