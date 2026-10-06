# Named calls with omitted parameters

Run this test from the repository root:

```sh
haxe test/m14_named_call_omission_test.hxml
```

The source declares `take(value:Int = 4, tail:String)` and calls
`take("tail")`. The String must reach `tail`, while `value` receives its default.
The same behavior is checked for instance and extension calls. Trailing
omissions, supplied zero, supplied false, and nullable inputs have separate controls.
Receiver and argument effects must occur once, in source order.

The harness first runs upstream Haxe, then emits, compiles, and runs native C++.
It also runs O0/O2 AddressSanitizer and UndefinedBehaviorSanitizer observers with
forced garbage collection. Set `HXHX_UPSTREAM_HAXE` to select upstream Haxe explicitly.

For an independent upstream native comparison, use Haxe 4.3.7 with hxcpp 4.3.2:

```sh
haxe -cp test/oracle/named_call_omission_seed -main Main -cpp out/named-omission
./out/named-omission/Main
```

Success produces no output. A wrong value or evaluation order throws a diagnostic.

The neighboring `m14_named_call_binding_test.hxml` rejects stale operand types,
changed result types, and bindings borrowed from another declaration. The
`m14_nested_generic_call_inference_test.hxml` checks omitted parameters before
nested generic results, including aliases and conflicting type requirements.

This fixture does not establish full rest/spread support, all generic native
method applications, or the imported-call regression in the bootstrapped native
compiler. Those acceptance requirements remain under `haxe_ocaml-pxkle` and
its related tasks. README Goals readiness is unchanged.
