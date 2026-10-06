# Throwing logical operands

The left operand records its effect before the selected right operand throws.
Negation and the enclosing branch must not finish after that exception.
The native observer checks the exact thrown String, then checks temporary-root
cleanup after unwinding. Only scalar program storage may survive collection.

Run the normal generated program and both O0/O2 sanitizer observers:

```sh
npm run test:m14:cpp-nullable-boolean
```

Compare the authored exception with upstream Haxe 4.3.7 and hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_nullable_logical_throw_seed -main Upstream -cpp .tmp/upstream-nullable-logical-throw
.tmp/upstream-nullable-logical-throw/Upstream
```

The upstream wrapper and native observer print nothing and exit zero on success.
Local Haxe typed catches remain tracked separately in haxe_ocaml-qrk0u.
