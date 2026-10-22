# Int64 addition

Run `haxe test/m14_cpp_int64_add_int_integration_test.hxml` from the repository root.

The test loads the real Haxe Int64 and Sys providers and preserves the original
nine output cases, including signed overflow. Contract independently checks
that each operand runs exactly once, from left to right, in both operator orders.
Upstream Haxe eval and native execution must produce the original output.

The prepared program must select two `add` and 11 `addInt` calls in Main and
Contract. Native O0 and O2 builds repeat the behavior checks with address and
undefined-behavior sanitizers and collection at every allocation. Original
typed function bodies must remain unchanged.

Earlier generated-text assertions required the old handwritten 64-bit carrier
helper and its unsigned arithmetic. The current backend executes the authored
provider. Exact overflow behavior and sanitizers replace those obsolete helper
text assertions; selected typed calls prove provider use. This test does not
establish general Int64 or target readiness.
