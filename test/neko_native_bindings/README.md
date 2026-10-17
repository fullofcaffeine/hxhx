# Native binding startup

Run `haxe test/m14_neko_native_binding_test.hxml` to compare this source with
upstream Neko and both native output layouts. The fixture uses real standard-library
providers. `expected.stdout` is independently checked against upstream.

Direct native-loader calls with literal arguments bind Dynamic fields before ordinary
initializers. Aliases preserve that selection. Function-typed fields, computed arguments,
string concatenation, and factory calls stay deferred. The ordinary native-loader
assignment still runs later, so it can replace an earlier write.

The upstream observer passes. Current native typing rejects a forward unannotated field
passed to the Dynamic probe parameter. This failure is retained under haxe_ocaml-lcshu;
do not add a field annotation to hide it. The independent selection-only test is
`haxe test/m14_neko_native_binding_plan_test.hxml`. It does not prove runtime startup.

README Goals status is unchanged; complete integration and release evidence remain required.
