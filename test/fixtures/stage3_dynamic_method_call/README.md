# Stage3 Dynamic method call fixture

`Main.hx` calls class methods through values typed `Dynamic`. Before this fixture existed, the native
Stage3 program stopped with exit 138 (SIGBUS) on `final d:Dynamic = new Late(); d.pick();`.

`expected.stdout` is the output of upstream Haxe 4.3.7. `M14Stage3DynamicMethodCallTest` requires the
upstream program and the native program to print exactly this text.

`stage3_dynamic_method_call_errors` holds the calls Stage3 cannot make natively. Upstream runs those programs or
stops with different text, so that fixture's `expected.stdout` records the named native errors, and each error
must be catchable.
