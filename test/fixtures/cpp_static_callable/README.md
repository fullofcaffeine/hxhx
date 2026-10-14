# Static function values in C++

This fixture stores static methods, calls them, compares their identity, shadows
a method with a local callback, and omits a defaulted argument. The argument
block in `consume` requires the compiler to capture its callee before evaluation.

Run the upstream behavior check and native regression from the repository root:

```sh
haxe -cp test/fixtures/cpp_static_callable -main Main --interp
npm run test:m14:cpp-static-callable
```

Both must match `expected.stdout`. The native regression also rejects declaration
facts from a separately typed program. Its C++ observer includes the generated
program without editing it and runs it in two independent heaps. Each heap
collects before every allocation. `prime` releases its local method reference
before a later allocation, so traced static storage must retain that method.

The `Sys` extern declares the actual console API and excludes unrelated standard
library dependencies. Mutable `dynamic` methods, native-operation function
values, and generic method instantiation remain separate compiler work.

The fixture also compares nullable argument transport through static methods and
equivalent closures. It requires their behavior to agree within each target;
it does not assume that eval and native scalar null conversion are identical.
