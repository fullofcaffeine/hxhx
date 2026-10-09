# Managed source Map.get

Run `haxe test/m14_cpp_managed_map_get_test.hxml` from the repository root.
The test compares an independent output expectation with upstream Haxe 4.3.7,
then uses real providers and normal CppTargetCore emission to build and run C++.

The source checks receiver-before-key effects, discarded results, missing
entries, nullable Int/Bool/String output, and anonymous-object key identity.
Named-class keys preserve allocation identity despite equal field contents.
Repeated keys replace values, fresh instances miss, and a comprehension uses
the same key representation. Map family tests distinguish these maps from
IntMap and distinguish the key instances themselves from ObjectMap.
It also uses Map.get in a field initializer and a closure that captures a map.
Copied or mutated call markers, a foreign owner, and an unrelated method named
get must not authorize the native Map binding.

The native observer forces collection before every allocation and checks the
persistent provider graph. Both `-O0` and `-O2` use address and undefined behavior
sanitizers. Generated source is included without edits.

This fixture does not complete the original Map acceptance. Enum key storage
and the complete original runtime-type contract remain required. Other Map methods, general
instance calls, and the full native exception-conversion contract remain open.
Upstream expectations here use the interpreter; release parity still requires
the relevant upstream target suites.
