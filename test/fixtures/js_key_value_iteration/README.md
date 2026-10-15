# JavaScript key/value iteration

Run `haxe test/m14_js_stmt_emitter_key_value_for_integration_test.hxml`.
The authored fixture runs with upstream and candidate JavaScript, using real Map, StringMap,
Array, and Std declarations. It checks the original label/value pairs, string keys including
01, a map key snapshot during insertion, numeric array keys, and live array length during append.
Extractors.hx preserves the original nested enum and object patterns as authored runtime checks,
including both OR alternatives and unmatched inputs. Its real Std.string call also exercises
provider initialization before the String and Array type checks.
The enclosing test retains the separate legacy callback-adapter runtime check and diagnostic probes.
Generated-loop temporary names are not a runtime contract.
