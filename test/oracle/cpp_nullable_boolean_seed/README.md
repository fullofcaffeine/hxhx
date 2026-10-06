# Nullable Boolean conditions

Null selects the false branch of a native condition. False and true retain their
ordinary behavior. Reading a condition must not change the nullable source.

The assertions cover ternaries, if/else, while, do/while, and negation. Effect
counters check condition evaluation and selected-branch execution. Upstream
Haxe 4.3.7 with hxcpp 4.3.2 passes the same authored assertions.

The logical-condition table covers all nine pairs of null, false, and true.
It checks left-to-right effects and short-circuit evaluation through direct
calls and callbacks. Skipped operands must not throw. A selected throwing
operand must stop evaluation, and an early return inside negation must still
exit its function. Nested Int, String, and Dynamic operands remain rejected,
including operands that would be skipped at runtime.

```sh
npm run test:m14:cpp-nullable-boolean
```

This command also runs the optional-constructor fixture. Both generated
applications run under forced collection with O0/O2 AddressSanitizer and
UndefinedBehaviorSanitizer builds. Only one program storage object may remain
after collection, with zero temporary roots.

To reproduce the upstream native assertion check:

```sh
haxe -cp test/oracle/cpp_nullable_boolean_seed -main Main -cpp .tmp/upstream-nullable-boolean
.tmp/upstream-nullable-boolean/Main
```

Success prints nothing and exits zero. The upstream comparison requires Haxe
4.3.7 and hxcpp 4.3.2. The optional-constructor harness accepts an
HXHX_UPSTREAM_HAXE override and otherwise uses the repository's compiler wrapper.

Nullable logical values from `&&` and `||` remain separate unfinished work under
haxe_ocaml-nu9yi. These condition checks do not establish their value semantics
or complete constructor default handling.
