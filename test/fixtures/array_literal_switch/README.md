# Array literal switch

A switch on an array literal matches position by position, as in Haxe 4.3.7: `switch ([shape, paint])` with `case [Circle(r), Solid(c)]` binds each element with its own type.

Run `node_modules/.bin/haxe test/m14_array_literal_switch_test.hxml`. The `labels` case uses an `Int` element: a `Bool` literal pattern in this position does not match natively yet (haxe_ocaml-vae80).
