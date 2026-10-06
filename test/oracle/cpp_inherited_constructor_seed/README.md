Run `haxe test/m14_cpp_inherited_constructor_test.hxml` to compare upstream Haxe with native C++ execution.

The fixture checks constructor argument order, inherited defaults, child-to-parent field order, and explicit super calls through constructor-free classes. A child initializer also creates a callback with independent captured state for each object.

The native observer forces collection at every allocation and checks cleanup under address and undefined-behavior sanitizers at O0 and O2. Generic field layouts remain a separate storage requirement; shared generic constructor selection has its own fixture.
