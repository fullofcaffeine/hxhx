# Managed C++ Map type tests

Run `haxe test/m14_cpp_managed_map_type_test.hxml` from the repository root.
The test first checks the independently written output against upstream Haxe
4.3.7. It then types the same source with real standard-library providers,
emits through the normal managed C++ target, compiles, and executes it.

The fixture covers Int, String, and anonymous-object Map families, mismatched target families,
a null Map field, an unrelated Array, and an effectful tested operand.
Both matching and mismatching tests must evaluate that operand once. Arrow
entries evaluate their key before their value. The printed order and final
counter check these effects independently of generated source spelling.

This is a focused regression. Named-class and enum Map key storage, class values,
erased-value type tests, and the full original Map acceptance remain separate
requirements. Passing this fixture does not establish full C++ readiness.

A separate native observer includes the generated program without editing it.
It forces collection before every allocation and runs with address and undefined
behavior sanitizers at `-O0` and `-O2`. After execution, no temporary roots remain.
The real provider closure retains exactly eight nodes: static storage, one
shared escape-character array, and six nullary enum values. The observer checks
that fixture maps and temporary arrays do not remain in that persistent graph.
