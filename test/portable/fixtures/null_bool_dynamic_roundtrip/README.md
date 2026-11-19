# `Null<Bool>` values that go into `Dynamic` and come back

Since `Null<Bool>` values entering `Dynamic` carry the Boolean tag (`HxRuntime.box_bool`),
every reader must accept the tag. The fixture reads such a value back into `Null<Bool>`, casts
a Dynamic `false` to `Null<Bool>`, and compares a Dynamic with a `Null<Bool>` (`d == nb`); all
must print what upstream Haxe 4.3.7 prints. Before the fix, the value came back still tagged,
so `back == true` was false and `d == nb` compared a tagged and a plain Boolean
(`haxe_ocaml-9cqxj`, found by an independent review of PR #212).

The fixture also compares a `Map<String, Dynamic>` value with `true` (`map.get(k) == true`).
The inlined `get` leaves an unbound type variable, which the comparison did not treat as
Dynamic, so it used OCaml's structural `=` against the tagged Boolean (`haxe_ocaml-9cqxj.6`,
wrong on main for plain Booleans too).

Run `PORTABLE_FIXTURE_ALLOWLIST=null_bool_dynamic_roundtrip bash scripts/test-portable.sh`.
