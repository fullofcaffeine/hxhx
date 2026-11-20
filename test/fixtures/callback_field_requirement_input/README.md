# Callback field requirement input

A callback whose untyped input only reads fields (`function(h) return h.name == wanted`) takes its type from the other arguments of a generic call such as `Lambda.exists(headers, ...)`, as in Haxe 4.3.7.

Run `node_modules/.bin/haxe test/m14_callback_field_requirement_input_test.hxml`. The test compares types and types the full program; it does not run native output, because frozen Stage3 cannot compile these `Lambda` callbacks (haxe_ocaml-zkr73).
