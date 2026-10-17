# Opaque values compared with class instances

Run `npm run test:m14:cpp-any-instance-equality` from the repository root.
This test checks the native identity behavior used by `haxe.Exception.native`
with plain `Token` and `Other` classes. It loads the real `Any` declaration.

An opaque value that holds the same instance compares equal in either operand
order. A different allocation, unrelated instance, or primitive value compares
unequal. Two null values compare equal. The final assertion checks that the left
operand runs once before the right operand. These assertions remain active when
the native observer forces garbage collection at every managed allocation.

The fixture also checks inherited references and a custom opaque abstract.
An explicit abstract equality operator must take precedence over reference
comparison. Shared typed-body checks verify that the compiler selects that call.
Two allocating operands must remain alive until the comparison finishes.

The native observer runs at `-O0` and `-O2` with ASan/UBSan. After execution, only
the program's static storage may remain alive; operand roots must be gone.
The Haxe driver also checks that shared lowering retains ordinary equality and
that the backend rejects unsupported operand categories and ordering operators.
The observer also calls the authored comparison with either operand set to
throw. A left failure skips the right operand; a right failure follows one left
evaluation. Both paths must release temporary instances and retain the thrown value.

Use upstream Haxe 4.3.7 with hxcpp 4.3.2 for the independent reference:

```sh
haxe -cp test/oracle/cpp_any_instance_equality_seed -main Main -cpp .tmp/any-instance-upstream
.tmp/any-instance-upstream/Main > .tmp/any-instance-upstream.stdout
diff -u test/oracle/cpp_any_instance_equality_seed/expected.stdout .tmp/any-instance-upstream.stdout

haxe -cp test/oracle/cpp_any_instance_equality_seed -main FailureOracle -cpp .tmp/any-instance-upstream
.tmp/any-instance-upstream/FailureOracle
```

The expected output is empty. A failed assertion throws and produces a nonzero
exit status. Apply the repository's background scheduling rules to native builds
on an interactive host.

This fixture belongs to `haxe_ocaml-snya5`. It does not establish general
equality between two opaque values, numeric coercion, or full exception support.
The candidate observer uses native catches. `FailureOracle` separately checks
the throw timing through upstream Haxe catches.
