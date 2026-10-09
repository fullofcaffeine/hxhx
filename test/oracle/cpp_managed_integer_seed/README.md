# Managed counter and integer operations

Run upstream Haxe 4.3.7 with:

```sh
haxe -cp test/oracle/cpp_managed_integer_seed -main Main --interp
```

Compare its output with `expected.stdout`. The cases specify recursive counter
state, signed 32-bit wraparound, postfix results, and left-to-right call effects.
The managed closure ABI test checks generated bodies against these expectations
with native sanitizers. Its callbacks force collection between operand effects.

These checks support the managed-body component. They do not establish normal
C++ target parity; haxe_ocaml-9jezt still owns the full target integration.
