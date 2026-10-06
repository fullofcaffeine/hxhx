# Callback arguments inside source functions

The callback receives 7 and returns 10. Its call sits inside a nested function with a local result variable.
C++ argument analysis must find this call after the compiler converts the function body into explicit control operations.
The nested function runs before its creator returns, so this case does not depend on escaped closure storage.

Run the upstream expectation with `npm exec -- haxe -cp test/oracle/source_callable_control_seed/src --run Main`.
Run the native candidate with `npm exec -- haxe test/m14_cpp_callable_control_traversal_test.hxml`.

The native C++ smoke checks include this regression. The companion `m14_cpp_callable_control_scope_test.hxml` checks nested return types, declaration order, and shadowed bindings.
