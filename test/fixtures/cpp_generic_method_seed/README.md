# Applied generic methods

Run `npm run test:m14:cpp-generic-methods` for native execution and ownership checks.
Run `npm run test:m14:cpp-generic-storage-oracle` for the pinned Haxe 4.3.7/hxcpp 4.3.2 comparison.

An unset field declared as T remains null when a generic method returns it into
a nullable destination. An Int destination receives zero. The fixture also checks
null through generic parameters and locals, Bool results, distinct Int/String
applications, and methods inherited through two generic ancestor edges.

An upcast from a concrete leaf to its applied generic base must keep the same
instance. Incompatible type arguments and reversed ancestor conversions remain
rejected. Concrete Int and Bool overrides convert generic null arguments to
zero and false. Calls also preserve omitted and supplied optional arguments.

Both result directions are covered: a concrete override returns a direct scalar
through a generic base, and a generic override returns a nullable value through
an Int base contract. The latter call must deliver zero to its concrete caller.

The independent heap observer forces collection at each allocation. A static
Box retains a payload passed through its generic method. Clearing that reference
must collect both objects. Native execution uses O0/O2 and address/undefined-behavior
sanitizers. Ownership checks reject foreign calls and stale source or call markers.

This fixture does not complete all generic method behavior. Calls made inside
generic methods, generic initializers, and full integration
remain under haxe_ocaml-g85ze. README Goals status is unchanged.
