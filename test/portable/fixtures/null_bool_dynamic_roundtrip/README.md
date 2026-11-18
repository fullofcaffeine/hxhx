# `Null<Bool>` values that go into `Dynamic` and come back

Since `Null<Bool>` values entering `Dynamic` carry the Boolean tag (`HxRuntime.box_bool`),
every reader must accept the tag. The fixture reads such a value back into `Null<Bool>`, casts
a Dynamic `false` to `Null<Bool>`, and compares a Dynamic with a `Null<Bool>` (`d == nb`); all
must print what upstream Haxe 4.3.7 prints. Before the fix, the value came back still tagged,
so `back == true` was false and `d == nb` compared a tagged and a plain Boolean
(`haxe_ocaml-9cqxj`, found by an independent review of PR #212).

Comparing a Dynamic map value with a Bool (`map.get(k) == true`) is still wrong natively, for
plain and nullable Booleans; it is tracked in `haxe_ocaml-9cqxj.6` and is not in this fixture.

Run `PORTABLE_FIXTURE_ALLOWLIST=null_bool_dynamic_roundtrip bash scripts/test-portable.sh`.
