# Value conversion table

`ValueConversionTableTest` checks `reflaxe.ocaml.lowered.OcamlValueConversion`, the one
table that decides how a value moves between two storage forms (carriers) in OCaml
(`haxe_ocaml-9cqxj`). It checks the carrier of each listed Haxe type, and the conversion
for each listed pair of types, including pairs that the table does not list yet.

The check runs at compile time in a macro, because the table reads typed Haxe types.

Run `npm run test:reflaxe-ocaml:value-conversion`. It prints
`VALUE_CONVERSION_TABLE:PASS` and the number of checked carriers and pairs.
