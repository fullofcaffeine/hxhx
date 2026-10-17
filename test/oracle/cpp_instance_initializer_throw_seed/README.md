# Throwing instance initializer

Run `haxe test/m14_cpp_instance_initializer_test.hxml`.

Upstream Haxe runs `Upstream`, which checks the failure from the same `Main.run`
compiled by the native test. The initializer must throw `initializer` before
the constructor can throw `constructor` or the caller can throw `continued`.

The native observer calls the generated program runner with collection before
every allocation. It checks the thrown value after collection, then verifies
that the failed receiver, its allocated child, and temporary roots are released.
Both optimization levels run with address and undefined-behavior sanitizers.

The observer uses native exception transport. This fixture does not prove
Haxe typed catch selection, exception wrappers, stack capture, or rethrow policy.
