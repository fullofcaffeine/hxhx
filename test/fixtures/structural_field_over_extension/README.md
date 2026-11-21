# Structural field over extension

A structure's own method field wins over a static extension of the same name, as in Haxe 4.3.7: with `using Lambda;`, `access.has("x")` calls the structure's `has`.

Run `node_modules/.bin/haxe test/m14_structural_field_over_extension_test.hxml`.
