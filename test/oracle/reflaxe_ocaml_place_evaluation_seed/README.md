# `reflaxe.ocaml` Place-Evaluation Oracle

This fixture freezes the observable order and result of assignment and update
expressions before the target lowering is changed. It deliberately lives under
`test/oracle/` because upstream Haxe 4.3.7 is currently the source of truth and
the OCaml target does not yet compile the complete fixture.

Run the three upstream routes with:

```bash
npm run test:reflaxe-ocaml:place-oracle
```

The interpreter and JavaScript routes agree on all 27 cases. Neko agrees on 26
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

Until the remaining compound/update place slices land, a failure from that
command is expected and must not be converted into an accepted snapshot.

`field_compound_rhs_mutates` also proves that an ordinary compound assignment
loads the old field value before evaluating a right-hand side that mutates the
same field. The final addition and store therefore use the original value and
overwrite the intervening mutation.

`static_compound_rhs_mutates` proves the same load-before-RHS contract for a
mutable static cell. The target must save the original ref-cell value before
the RHS temporarily overwrites that cell.

`array_compound_rhs_mutates` proves the same load-before-RHS contract for an
array element after the receiver and index have been established. The final
addition uses the original element value and overwrites the RHS mutation.
