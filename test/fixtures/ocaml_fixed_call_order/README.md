# Capture the function before its arguments

The first argument replaces a mutable local function. The current call must still use the function selected before argument evaluation.
The next call must use the replacement. The second argument prints a marker to expose evaluation order.

Run `haxe test/m14_stage3_fixed_call_order_test.hxml` with the repository Haxe toolchain.
The test compares the fixed expectation with upstream Haxe and a real native executable.
The enum-equality fixture also checks ordinary argument order and collisions between authored local names and generated temporary names.
