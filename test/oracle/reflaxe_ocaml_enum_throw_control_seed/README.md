# Direct enum throw control oracle

This fixture freezes how upstream Haxe 4.3.7 transports enum constructors
through `throw` and `catch`.

Run:

```bash
npm run test:reflaxe-ocaml:enum-throw-oracle
```

The same source runs through the Haxe interpreter, JavaScript, and Neko. It
checks constant and payload constructors, once-only payload evaluation,
propagation across a function call, exact enum catches, and `Dynamic` fallback.
The exact `Pair` catch proves that the original constructor and both payloads
survive transport. The separate `Dynamic` case proves only that a general catch
receives the thrown value. Enum reflection and casting from `Dynamic` are
separate conversion/runtime features and are not inferred from a passing throw
test.
The OCaml fixture reuses this source to prove that `reflaxe.ocaml` seals the
direct-constructor transport decision before it prints target syntax.
