# C++ helper declaration ownership

This fixture preserves the source generic on a helper and distinguishes two parameter names that collide after C++ keyword sanitization.
The traversal helper must return its first argument, and the effectful argument must run once.
The Unix quoting helper must also use its first argument when parameter names collide, while retaining its source generic.
The Windows helper must distinguish the string argument from its defaulted Boolean policy argument.
The authored bodies specify the existing helper behavior; this fixture does not claim complete macro-library semantics.

Run the upstream behavior:

```sh
haxe -cp test/oracle/cpp_ordinary_helper_seed/src -main Main --interp
```

Run generation, native compilation, and the independent output comparison:

```sh
haxe test/m14_cpp_ordinary_helper_callable_integration_test.hxml
```
