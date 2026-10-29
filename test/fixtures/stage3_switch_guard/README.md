# Conditional switch cases

Run `haxe test/m14_stage3_switch_guard_test.hxml` from the repository root.
The existing `test:m14:hih-forin` command also runs this regression in CI.

Haxe evaluates a case guard only after the pattern matches. If the guard is
false, the next case can match the same input. The input itself runs once.
Within one OR pattern, a false guard also retries the next matching alternative.
Each attempt creates fresh bindings. A saved closure retains the value from
its own attempt after another alternative matches.
Values extracted by structural matching also survive a rejected guard. The
mutation case distinguishes these observations from later reads of the array.

`Main.hx` exercises repeated patterns, ordered side effects, enum payloads,
array and record bindings, captured variables, nested OR patterns, nested switches,
guard-local declarations, and `return`, `break`, and `continue`. Boolean values
also reach guards through Dynamic and a declared abstract conversion.

The test compares upstream Haxe, native OCaml, and JavaScript with the same
independently written `expected.stdout`. It checks invalid guard rejection,
source reconstruction, revision changes, and repeated lowering. Target output
must not mutate the original typed function bodies.

These checks do not establish complete switch extractor support or full Haxe
equivalence. The separate DateTools dependency test remains required.

`haxe test/m14_guarded_pattern_plan_test.hxml` checks the shared decision plan
against the independently observed extraction rules. It also rejects mismatched
enum payload facts. This diagnostic check supplements native execution.
