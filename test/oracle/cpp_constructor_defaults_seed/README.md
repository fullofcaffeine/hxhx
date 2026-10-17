# Constructor defaults

Run `npm run test:m14:cpp-constructor-defaults` from the repository root.
The fixture checks omitted inputs, nullable inputs, supplied values, evaluation
order, parent construction, static method defaults, and captured parameters.
Zero and false must remain supplied values. Chained inline constants work in
defaults and ordinary body reads.

The test runs upstream Haxe assertions, emits and executes native C++, then
runs O0/O2 AddressSanitizer and UndefinedBehaviorSanitizer observers with forced
collection. Set `HXHX_UPSTREAM_HAXE` to select the upstream compiler explicitly.

To verify the upstream C++ behavior, use Haxe 4.3.7 with hxcpp 4.3.2:

```sh
haxe -cp test/oracle/cpp_constructor_defaults_seed -main Main -cpp out/defaults
./out/defaults/Main
```

The program succeeds without output. A failed expectation throws a diagnostic.
Haxe's static targets reject a literal null passed to a concrete scalar default
parameter. This fixture uses explicitly nullable variables for that case;
those inputs select defaults on upstream C++ too.

Projection checks cover literal-null rejection for bare Int and Bool defaults.
They also check question-mark parameters, nullable parameters, and nullable variables.
This does not establish Float, extension-call, or complete callable-value admission.

The command also runs the named-call binding and omission regressions.
`take("tail")` must skip the first parameter in
`take(value:Int = 4, tail:String)`. The compiler retains this mapping through
selection, inference, conversions, and target projection. Static, instance, and
extension cases have native execution and O0/O2 sanitizer coverage.
See [the named-call fixture](../named_call_omission_seed/README.md).
The original imported-call acceptance in the bootstrapped native compiler
remains open under `haxe_ocaml-pxkle`.

This fixture does not establish complete constructor compatibility, instance
field initialization, exception runtime behavior, or native compiler bootstrap.
README Goals readiness is unchanged.
