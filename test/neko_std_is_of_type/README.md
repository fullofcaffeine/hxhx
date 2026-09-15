# Neko standard type predicate

Run `haxe test/m14_neko_std_is_of_type_integration_test.hxml` from the repository root.

The fixture loads the installed Neko `Std` provider. The selected standard
`isOfType` declaration must use the same runtime predicate as ordinary `is`.
A type argument can come from a local variable or a function. Both arguments
must run once, from left to right. A namespaced user method keeps its behavior.

Both generated layouts must match the independent upstream output. This covers
nominal classes, Array, String, and null checks. Numeric type values and typed
exception conversion remain separate requirements.
