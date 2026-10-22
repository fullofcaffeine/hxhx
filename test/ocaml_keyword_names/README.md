# OCaml keyword names

Valid Haxe methods and locals named `effect` must compile on OCaml versions that reserve this word.
The fixture also uses `effect_` and `hx_effect` to detect collisions after name escaping.
All methods and local values must retain their distinct results.

Run `npm exec -- haxe test/m14_ocaml_keyword_names_integration_test.hxml` from the repository root.
This selects the repository Haxe wrapper for the test and its child compiler process.
The test compares an authored expectation with upstream Haxe and native executables from both current hxhx source and standalone reflaxe.ocaml.
Failures retain generated files under `.tmp/ocaml_keyword_names_*`.

This focused check does not prove a standalone hxhx build or full Haxe compatibility.
