# Inherited constructors

Run `haxe test/m14_inherited_constructor_selection_test.hxml`.

Upstream Haxe 4.3.7 runs the authored assertions. Constructor arguments execute
first. Each constructor-free class initializes its own fields before forwarding
to its parent. The explicit ancestor then initializes its fields and runs its body.
The expected event digits are `743172`, or `43182` when using the default argument.

The shared typing test checks the allocated child, the original constructor
declaration, applied ancestor arguments, and the intervening initializer owners.
It also rejects fallback past an inapplicable own constructor and checks that a
class with no constructor stays unresolved.

Run `npm run test:m14:cpp-generic-layout` for native execution of this complete
fixture. It checks the authored assertions at O0 and O2 with address and
undefined-behavior sanitizers, forced collection, and a separate lifetime observer.
This includes forwarding the nested generic constructor argument. These generic
classes have no stored fields; generic field access, method transport, and
initializers remain separate requirements under `haxe_ocaml-g85ze`.
