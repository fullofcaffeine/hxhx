# Ordinary object identity

This program compares aliases, distinct objects with equal fields, base and
derived references, and null values stored in class variables. Two allocating
operands must run once each, from left to right. The first object must survive
collection while the second operand runs. Successful execution writes no output.

```sh
haxe -cp test/oracle/cpp_instance_equality_seed -main Main --interp
npm run test:m14:cpp-instance-equality
```

The native test uses normal source generation and checks the resulting program.
It also forces collection before every allocation under AddressSanitizer and
UndefinedBehaviorSanitizer at `-O0` and `-O2`. The observer requires no temporary
roots or objects after execution. Scalar and Dynamic operands cannot select
ordinary class comparison.

The compiler compares allocation identity after checking compatible class types.
Class declaration handles retain their separate descriptor comparison. Enum,
interface, native, and abstract representations need their own comparison plans.
The generic callback fixture also exercises this path with captured and returned
objects. Review and integration remain tracked in `haxe_ocaml-c8nat`.
README Goals readiness remains unchanged.
