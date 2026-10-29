# Parameterless enum keys in native C++ Maps

Run `haxe test/m14_cpp_managed_enum_map_test.hxml` from the repository root.

The fixture checks repeated-key replacement, missing keys, static initialization,
comprehensions, and the distinction between EnumValueMap, IntMap, and ObjectMap.
Upstream Haxe and the normal C++ target must match the independently written output.
The native observer forces collection before every allocation under address and
undefined-behavior sanitizers at both optimization levels.

This route admits ordinary nongeneric enums only when every constructor has no
parameters. The exact enum descriptor validates each key before its constructor
index selects storage. Native code performs checked physical access; Haxe owns
the representation decision. Map values retain their normal traced edges.

The descriptor regression rejects foreign and copied descriptors. It also rejects
ordinal-only storage for an enum with any payload constructor. Structural enum
key comparison remains tracked by `haxe_ocaml-60jwu`, including nested payloads,
generic substitution, and null/error behavior. This fixture does not prove full
EnumValueMap provider parity or change README goal estimates.
