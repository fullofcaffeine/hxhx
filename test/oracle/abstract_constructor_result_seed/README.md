# Abstract constructor results

This program constructs six abstract values and reads their initialized contents.
It checks omitted, Void, abstract, Int, and String result annotations, plus a generic abstract.
Upstream Haxe 4.3.7 accepts these annotations without making the constructor body return a value.
The declared construction result remains the abstract type.

Run the upstream behavior check from the repository root:

```sh
haxe -cp test/oracle/abstract_constructor_result_seed/src --run Main
```

Run the candidate contract with `haxe test/m14_abstract_constructor_result_test.hxml`.
It loads the real dependency closure and checks exact constructor results, Void body completion, and rejection of a value-returning constructor.
The generic case requires the actual Array declaration and preserves its owner binder under String and Int substitution.
It then requires a native C++ executable with the complete expected output.
Native target failures remain failures; shared typing success alone does not close `haxe_ocaml-5f9jq`.

The complete six-case program now passes native execution with the real
standard-library dependency closure. Its output is `7`, `11`, `13`, `17`, `19`,
and `word`. The generic constructor and its `read()` method retain the same
authored bodies while native storage applies the exact String argument.

Run `npm run test:m14:cpp-constructor-applications` for additional ownership and
native storage checks. Two applications of one constructor preserve Int and
String values through a captured local and nested function. The native observer
checks both optimization levels with sanitizers and collection before every
allocation. It also checks the original generic constructor's String-array
representation and storage cleanup. See
[`cpp_constructor_application_seed`](../cpp_constructor_application_seed/README.md).

The original typed-catch workload remains a separate required check under
`haxe_ocaml-qrk0u`. It now reaches an unsupported extern-constructor boundary.
Passing this fixture does not establish complete generic, exception, or target compatibility.

`PrimitiveConstructorEffectsMain` distinguishes authored construction from argument passthrough.
The constructor transforms 7 into 15, evaluates the input once, and records two body effects.
Upstream Haxe 4.3.7 prints `15`, `1`, and `2`:

```sh
haxe -cp test/oracle/abstract_constructor_result_seed/src -main PrimitiveConstructorEffectsMain --interp
haxe test/m14_primitive_constructor_effects_test.hxml
```

The older emitter produced `7`, `1`, and `2`, losing the constructor's value
transformation. An earlier focused run loaded real providers and rejected
abstract construction before native publication with
`managed instance storage cannot represent an enum or abstract`.
The receiver-cell and direct abstract-method implementations get past those
checks. Initializer emission now uses the completed field type already published
by the shared compiler. The original program passes native execution with `15`,
`1`, and `2`, while its static fields remain unannotated. Shared field-type
publication and its wider acceptance remain tracked under `haxe_ocaml-lcshu`.

`ConstructorOrderMain` adds two effectful arguments and records each constructor phase.
Its expected result is 25, followed by `left;right;body;assigned;step;step;done;`.
This distinguishes argument order from body effects and requires the authored loop to execute.
The same native command runs these programs and reports each failure.
The candidate now consumes the ordinary loop's exact typed control facts. The
unchanged ordering program passes native execution with its expected result and
event sequence. Broader loop acceptance and integration remain tracked under
`haxe_ocaml-86u4u`.

`ReceiverValueMain` compares an explicit cast of the constructed Int backing with
an authored instance-method read. It requires `15`, `argument;body;assigned;`,
and `15` on separate lines. Upstream interpreter and native C++ both match this
expectation. The candidate native test also matches it. Its independent observer
uses collection before every allocation and AddressSanitizer/UndefinedBehaviorSanitizer
at `-O0` and `-O2`. Escaping abstract receiver captures and unassigned paths remain
separate requirements.

The runner also checks that direct method linkage rejects unregistered and
foreign-program calls. Run those ownership checks alone with
`haxe test/m14_cpp_managed_instance_method_test.hxml`.

For a focused rerun, set `HXHX_M14_SMOKE_GROUP` to
`PrimitiveConstructorEffectsMain`, `ConstructorOrderMain`, or `ReceiverValueMain`.
With the variable unset, all three programs run. Unknown names fail explicitly. The runner uses the
same production dependency loader for either selection; it does not replace
standard-library declarations with synthetic providers.

```sh
haxe -cp test/oracle/abstract_constructor_result_seed/src -main ConstructorOrderMain --interp
```
