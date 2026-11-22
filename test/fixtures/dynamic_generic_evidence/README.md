# Dynamic generic evidence

A generic method called with Dynamic arguments (`make<T>(e:Enum<T>, ...)` with an `Enum<Dynamic>`) leaves `T` unbound in Haxe 4.3.7, but the call is valid and its result can go into an `Array<Dynamic>`. `haxe.Unserializer` calls `unserializeEnum` this way.

Run `node_modules/.bin/haxe test/m14_dynamic_generic_evidence_test.hxml`. The test compares types and types the full program; it does not run native output, because frozen Stage3 does not pass an enum as a first-class value (haxe_ocaml-lw12o).
