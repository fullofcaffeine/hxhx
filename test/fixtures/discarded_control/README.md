# Discarded block results

Run `haxe test/m14_discarded_control_test.hxml` from the repository root.
The test compares this program with upstream Haxe, then executes candidate
JavaScript and native OCaml output. It also checks the JavaScript syntax fixture.

The expected output proves ordered effects, a consumed block value, early returns,
untaken branches, loop breaks, and loop continuations through `untyped` blocks.
Parentheses must not turn a discarded block into a value consumer. The test checks
that lowering is repeatable and that emission preserves the authored typed tree.

This fixture does not establish full standard-library or target compatibility.
