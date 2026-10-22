# JavaScript switch expressions

Run `haxe test/m14_js_switch_expression_runtime_test.hxml` from the repository root.
The fixture runs identical source through upstream Haxe and the local JavaScript
backend. Both programs must finish successfully. The catch body prints failure
then observer, and the outer handler verifies the final rethrow. Upstream adds
source positions to those trace lines. The candidate currently omits them.

These are the switch expressions from the older raw-emitter fixture, supplied
with ordinary typed declarations and runtime inputs. Assertions cover literals,
alternatives, defaults, captures, nested enum and object patterns, arrays,
guards, the supported parseInt and slice extractors, throw and rethrow, and empty
cases. General extension/function extractors have a separate strict reproducer
in `../js_general_extractors`, owned by `haxe_ocaml-l0oh8`.

The integer parser also runs through ordinary calls and extractor bindings.
Eighteen upstream-backed cases cover null, invalid input, signs, whitespace,
prefixes, and suffixes. An input counter detects repeated evaluation. This
bounded JavaScript contract is owned by `haxe_ocaml-gkvnk`.

Full trace callback replacement and position formatting remain under
`haxe_ocaml-hgtz2`. This fixture checks the original ordered effects without
claiming logging parity. The required `test:m14:js-expr-switch` command also
retains all original macro quotation assertions and rejects unlowered control.
The quotation cases share this program's provider loading and native execution.
