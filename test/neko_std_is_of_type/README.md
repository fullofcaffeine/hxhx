# Neko standard type predicate

Run `haxe test/m14_neko_std_is_of_type_integration_test.hxml` from the repository root.

The fixture loads the installed Neko `Std` provider. The selected standard
`isOfType` declaration must use the same runtime predicate as ordinary `is`.
A type argument can come from a local variable or a function. Both arguments
must run once, from left to right. A namespaced user method keeps its behavior.

Both generated layouts must match the independent upstream output. This covers
nominal classes, Array, String, and null checks. Numeric type values and typed
exception conversion remain separate requirements.

The same source and expected output are also consumed by
`haxe test/m14_cpp_runtime_class_value_test.hxml`. That runner loads real C++
providers and requires native execution. Its separate class-lookup fixture checks
canonical names, repeated identity, and missing-class lookup. The C++ contracts
remain unfinished under `haxe_ocaml-sp2zl`; Neko success does not prove C++ support.
