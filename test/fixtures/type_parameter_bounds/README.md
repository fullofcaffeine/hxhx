# Type parameter bounds

Haxe 4.3.7 reads a type parameter's members through its bounds: a class, a typedef, or a structure. The fixture covers these cases:

- the bounds, in `Ops`;
- abstract headers with braces before the body, in `Table` and `Point`;
- a field assignment that binds a generic instance's type argument, in `fill`.

`haxe.ds.HashMap` needs all of them.

`native/Main.hx` is the part frozen Stage3 can run. Stage3 cannot emit generic methods with constraints or call a method on a type parameter value. This is also true on main.

Run `node_modules/.bin/haxe test/m14_type_parameter_bounds_test.hxml`. The test compares input types and full signatures with upstream (observers in `test/fixtures/method_parameter_dynamic_context`). It checks the local abstracts' members, and it runs the native program.
