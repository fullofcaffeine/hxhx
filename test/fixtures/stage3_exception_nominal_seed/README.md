This program requires class identity to survive Dynamic storage and a base-class catch.
Run `haxe test/m14_stage3_nominal_exception_integration_test.hxml` from the repository root.
Upstream Haxe and native Stage3 must print base, child, alias, and interface.
The original base/child rethrow remains the first observation. The program also
checks constructor effects, initialized fields, catch aliases, and interfaces
inherited through a parent class. Both catch bindings must retain the original
object, and parent construction must preserve the most-derived descriptor.

The separate `m14_nominal_carrier_runtime_test.hxml` checks private descriptor
storage, forgery rejection, and garbage-collection lifetime. Numeric catches
and native exception conversion remain unfinished under haxe_ocaml-k93zp.
