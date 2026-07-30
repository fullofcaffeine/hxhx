# Mixed-shape enum reflection oracle

This fixture freezes how upstream Haxe 4.3.7 reports enum constructors when
declarations with and without payloads are interleaved.

Run:

```bash
npm run test:reflaxe-ocaml:enum-reflection-oracle
```

Haxe constructor indices follow declaration order. Native OCaml represents
constant constructors and payload constructors with two separate tag
sequences, so those tag numbers cannot be used as Haxe indices. The fixture
checks the public constructor name, index, parameters, declaration-order list,
and factory APIs through both typed and `Dynamic` values.
