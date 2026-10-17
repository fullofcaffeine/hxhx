# Boolean catch behavior

The complete `Main` program checks Boolean handlers against raw values and real
`haxe.ValueException` objects. It also checks inherited payload storage, rejected
payloads, exception identity, handler throws, and independent captured variables.
Success means exit code zero with no output.

Run the upstream C++ reference with Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_bool_catch_seed -main Main -cpp .tmp/bool-reference
.tmp/bool-reference/Main
```

`ReferenceProbe` prints the public observations in `probe.cpp.stdout`. Upstream
C++ has a significant ordering rule: a `ValueException` reaches the Boolean
handler's wrapper test before a later `Dynamic` handler. If its payload is not
Boolean, the original wrapper escapes the region. A raw String reaches the
`Dynamic` handler instead. A nested wrapper is not recursively unwrapped.

The candidate full command is `haxe test/m14_cpp_bool_catch_test.hxml`. Nested
wrapper construction still requires general object formatting in `Std.string`,
tracked by `haxe_ocaml-hcnk8`. Keep this requirement in the full exception suite.

`haxe test/m14_cpp_bool_catch_primitive_test.hxml` runs `PrimitiveMain`, which
calls the shared primitive assertions without constructing a nested wrapper.
It also checks exact catch-use ownership and executes generated code with forced
collection and address/undefined-behavior sanitizers at O0 and O2. This focused
gate supports iteration; it does not replace the complete program or the full
typed-exception suite.
