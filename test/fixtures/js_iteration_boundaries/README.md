# Iteration capture boundaries

Run `./node_modules/.bin/haxe test/m14_js_iteration_boundaries_test.hxml`.
The upstream and candidate programs execute the same assertions. A callback in the iterable
captures a local and runs once. A field initializer creates callbacks with distinct iteration
bindings for each constructed instance. The fixture uses an ordinary custom cursor and arrays.
