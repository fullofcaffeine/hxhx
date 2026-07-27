# Function-value signature matrix oracle seed

This source freezes Haxe 4.3.7 behavior for represented callback signatures
that are broader than the original exact-`Int` and optional-`String` proofs.

The output makes callback production, argument evaluation, omission, callback
execution, nullable conversion, zero-argument calls, and effect-only `Void`
observable. `scripts/reflaxe-ocaml/run-function-value-signature-matrix-oracle.sh`
runs the same source through Haxe's interpreter, JavaScript, and Neko routes
and compares all three with `expected.stdout`.

This is behavior-oracle evidence only. The hxhx/reflaxe.ocaml implementation
must remain clean-room and may not copy upstream compiler code.
