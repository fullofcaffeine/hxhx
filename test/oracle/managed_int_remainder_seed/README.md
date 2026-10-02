# Upstream Int remainder observations

This program observes Haxe 4.3.7 remainder behavior before the managed C++ emitter supports the operation.
Function parameters keep the operands outside constant folding.
The cases cover operand signs, minimum Int modulo minus one, and two zero-divisor inputs.

The three saved results come from Eval, Neko 2.4.0, and hxcpp 4.3.2 on macOS ARM.
Ordinary operands and the minimum-Int case agree across these runs.
For zero divisors, Eval produces NaN despite the Int result annotation.
Neko throws `Invalid operation (%)`, while hxcpp throws `Mod by 0 Error.`.
The exception message observer uses an ordinary `haxe.Exception` catch.
It does not establish the underlying thrown value's runtime type or identity.

Run the Eval observer from the repository root:

```sh
haxe -cp test/oracle/managed_int_remainder_seed -main Main --interp
```

Run the Neko observer:

```sh
mkdir -p .tmp/managed-int-remainder-oracle
haxe -cp test/oracle/managed_int_remainder_seed -main Main -neko .tmp/managed-int-remainder-oracle/main.n
neko .tmp/managed-int-remainder-oracle/main.n
```

For C++, use Haxe 4.3.7 and an isolated haxelib repository with hxcpp 4.3.2.
The setup follows the [native startup observer](../../fixtures/cpp_static_startup_oracle/README.md).
Compile this source directory with `-main Main -cpp <output>` and run the resulting `Main` binary.
Place the output within that isolated haxelib repository so the native build can resolve hxcpp.
Compare stdout with the corresponding `expected.*.stdout` file.

These observations guide `haxe_ocaml-6gjt1`; they do not prove managed C++ support.
The full map fixture retains its original remainder expression and currently fails generation.
Exact operand evaluation order, thrown-value identity, and managed native execution remain required.
The managed source-exception prerequisite is `haxe_ocaml-qrk0u`.
The numeric review gate applies before compiler behavior changes.
README Goals status remains unchanged.
