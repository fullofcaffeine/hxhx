# Arrow return destination

The arrow block returns 7 to its caller. It must not return from main.
Upstream execution succeeds without output.

```sh
haxe -cp test/oracle/source_arrow_return_seed -main Main --interp
haxe test/m14_source_arrow_return_test.hxml
```

The shared candidate projection now preserves the nested return destination.
ArrowExecution.hx also checks expression, block, nested and early-return arrows
through upstream execution and native C++ generation:

```sh
haxe -cp test/oracle/source_arrow_return_seed -main ArrowExecution --interp
haxe test/m14_source_arrow_syntax_test.hxml
haxe test/m14_source_arrow_native_test.hxml
```

ArrowDefaults.hx checks omitted, explicit-null and supplied arguments, followed
by parameter updates and closure capture. ArrowOptional.hx checks an optional
scalar without a default. Upstream execution passes for both:

```sh
haxe -cp test/oracle/source_arrow_return_seed -main ArrowDefaults --interp
haxe -cp test/oracle/source_arrow_return_seed -main ArrowOptional --interp
haxe test/m14_source_arrow_parameter_typing_test.hxml
haxe test/m14_source_arrow_parameter_entry_test.hxml
haxe test/m14_source_arrow_optional_test.hxml
```

Shared typing retains upstream's nullable parameter types. Shared lowering
assigns defaults once at function entry, before body effects. Native calls keep
omitted optional slots as null until that code runs.

The defaulted-arrow test now passes native execution and O0/O2 forced-collection
sanitizers with the corrected nullable types. The optional-arrow test also
passes native execution and both sanitizer configurations after shared nullable
conditional lowering. Broader nullable integer validation remains open under
haxe_ocaml-kk0df, and haxe_ocaml-5aatj still requires its original application
replay and integration checks. The typing test passes
and checks that lowering preserves the authored tree.

Task haxe_ocaml-lg94m remains open for complete default, optional, and rest
behavior. The original escaping inherited receiver now passes its native and
sanitizer checks; haxe_ocaml-71qn2 records that local-storage work. These focused
tests do not establish complete arrow compatibility or release readiness.
