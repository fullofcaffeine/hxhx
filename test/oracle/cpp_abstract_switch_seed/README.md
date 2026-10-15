# Switches over scalar abstracts

The program switches on user-defined abstracts backed by Int, Bool, String,
and an applied generic type. These abstracts allow inputs from their backing
type, but do not declare implicit conversions back to it. Pattern selection
must use their proven stored representation without inventing a conversion.

Runtime assertions check literal and alternative patterns, defaults, nullable
integer values, null strings, generic substitution, and input evaluation once.
A successful run exits without output.

```sh
haxe -cp test/oracle/cpp_abstract_switch_seed -main Main --interp
haxe test/m14_cpp_abstract_switch_test.hxml
npm run test:m14:cpp-numeric-erasure
```

The native test first checks upstream Haxe, then emits and runs the full C++
program. It checks source immutability and runs the generated source with forced
collection under address/undefined-behavior sanitizers at O0 and O2. The numeric
transport command includes this regression.

The existing storage-plan tests retain rejection of unsupported types, binding
patterns, mismatched scalar patterns, and duplicate defaults. This fixture does
not claim support for Dynamic, enum, record, or array pattern matching.
