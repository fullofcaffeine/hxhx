Run `haxe test/m14_ocaml_string_field_update_integration_test.hxml`.
The existing Int field-update command also includes this observer.

Upstream Haxe 4.3.7 and native OCaml must produce the same `expected.stdout`.
The first builder appends String, Int, and Bool values through one generic method.
The second builder uses concrete parameter types for the same values.

The effectful receiver must run once before the right operand. That operand
overwrites the field, so the final `seedR` proves the update captured the old
value first. Both compound expressions must return their written value.
The final observations verify the actual stored field after each update.

The observer keeps the generic Boolean expectation intact. A field-update repair
does not satisfy this contract if a generic Boolean becomes integer text.
