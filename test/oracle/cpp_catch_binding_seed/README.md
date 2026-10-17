# Catch bindings and implicit providers

This fixture requires ordered Int, String, and Dynamic handlers. A thrown string
also matches a ValueException handler and retains its payload. A default handler
receives an Exception with the original message. The string observation differs
from the ordinary object tested by the larger cpp_typed_catch_seed fixture;
do not generalize either result to every thrown value.

The independent success expectation is no stdout or stderr and exit status zero.
Run the upstream Haxe 4.3.7 reference with:

```sh
haxe -cp test/oracle/cpp_catch_binding_seed -main Main --interp
haxe -cp test/oracle/cpp_catch_binding_seed -main Main -cpp .tmp/cpp-catch-binding-reference
.tmp/cpp-catch-binding-reference/Main
```

The native command requires hxcpp and the repository background scheduling policy.

`haxe test/m14_cpp_catch_use_test.hxml` checks the candidate's exact typed bindings
and real provider declarations. It does not prove native catch emission. This
check also runs before the complete native exception workload in
`haxe test/m14_cpp_typed_catch_test.hxml`.

The full exception contract remains tracked under `haxe_ocaml-qrk0u`, including
handler selection, capture lifetime, numeric matching, runtime failures, and
native behavior. A passing metadata check does not close that task.
