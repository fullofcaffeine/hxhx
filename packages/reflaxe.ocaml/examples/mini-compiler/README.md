# mini-compiler

A tiny expression lexer/parser/evaluator used as an **acceptance test** for the OCaml target.

It intentionally exercises:

- `String` scanning + slicing
- enums + pattern matching
- recursion
- `haxe.io.Bytes` (portable surface)
- exceptions for assertions

Build (from this directory):

```bash
haxe build.hxml -D ocaml_build=native
./out/_build/default/out.exe
```

