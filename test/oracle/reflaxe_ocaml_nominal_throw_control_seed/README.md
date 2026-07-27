# Monomorphic class throw/catch oracle seed

This fixture records how upstream Haxe 4.3.7 routes one closed user-class value
through `throw`, exact class catches, `Dynamic`, and a rethrow across a function
call. The output proves that the earlier `Int` catch does not intercept the
class, a catch receives the same mutable object, a rethrow preserves its field
mutation, and null skips the class catch and reaches `Dynamic`.

The runner compiles the same source independently through the interpreter,
JavaScript, and Neko. This is behavior-oracle evidence only: the
`reflaxe.ocaml` implementation remains clean-room and does not copy upstream
compiler code.

Run it with:

```bash
npm run test:reflaxe-ocaml:nominal-throw-oracle
```
