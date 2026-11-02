# reflaxe.ocaml `Math` rounding

`src/Main.hx` is the same program as `test/fixtures/stage3_math_rounding`.
This copy is compiled by the reflaxe.ocaml backend, which calls the same
runtime `Math` module. `expected.stdout` is the output of upstream Haxe 4.3.7
eval. The behavior, the eval rule, and the target differences are explained in
`test/fixtures/stage3_math_rounding/README.md` and on Bead
`haxe_ocaml-32vsc`.
