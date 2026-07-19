# `reflaxe.ocaml` Place-Evaluation Oracle

This fixture freezes the observable order and result of assignment and update
expressions before the target lowering is changed. It deliberately lives under
`test/oracle/` because upstream Haxe 4.3.7 is currently the source of truth and
the OCaml target does not yet compile the complete fixture.

Run the three upstream routes with:

```bash
npm run test:reflaxe-ocaml:place-oracle
```

The interpreter and JavaScript routes agree on all 24 cases. Neko agrees on 23
cases, but evaluates the index before the receiver for a simple array
assignment. The accepted OCaml contract follows the interpreter and JavaScript
source order for that one disputed case. `expected.neko.stdout` preserves the
Neko result so this difference remains visible.

`PlaceHolder.property` intentionally has a setter whose stored value and return
value differ. This proves that assignment results cannot be reconstructed by
reading the place after the write:

- simple and compound property assignment return the setter result;
- prefix update returns the setter result;
- postfix update returns the value read before the setter call.

The target-side reproduction command is:

```bash
cd test/oracle/reflaxe_ocaml_place_evaluation_seed
haxe reflaxe.hxml
dune build --root out
```

Until the first typed place/evaluation slice lands, a failure from that command
is expected and must not be converted into an accepted snapshot.
