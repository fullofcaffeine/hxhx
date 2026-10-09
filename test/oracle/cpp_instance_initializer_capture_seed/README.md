# Closures created by instance field initializers

Run `haxe test/m14_cpp_instance_initializer_test.hxml` from the repository root.

Upstream Haxe 4.3.7 and generated C++ execute the same assertions. Each object
creates two callbacks in its field initializer. The callbacks share one mutable
local value after the initializer returns. A second object must have a separate
cell. A nested callback forwards that cell and captures its parent's parameter.
It also assigns and reads an initially unassigned local. Another field callback
retains an object across an allocation and reads its stored value afterward.

The C++ observer forces collection before every allocation. O0 and O2 builds
use address and undefined-behavior sanitizers. All temporary objects must become
collectible after the program returns. `expected.stdout` is intentionally empty;
failures are expressed by authored assertions and the native lifetime observer.

This fixture proves ordinary construction and invocation through stored fields.
It does not establish omitted constructors or full exception support.
