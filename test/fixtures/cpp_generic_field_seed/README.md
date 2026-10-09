# Applied generic fields

Run `npm run test:m14:cpp-generic-fields` for native reads, writes, and lifetime checks.
Run `npm run test:m14:cpp-generic-storage-oracle` for the pinned upstream C++ comparison.

The source uses Int, Bool, String, and reference applications in one program. It
checks inherited fields, captured callbacks, alias writes, a nullable receiver, field-to-field null
copies, and compound numeric updates. An unset generic field stays null until
copied into a concrete scalar destination. Int receives zero; Bool receives false.
Comparing the original field with zero or false must still return false.

The independent observer forces collection before each allocation. A static Box
keeps its payload alive only through the generic field. Clearing that static
reference must collect both objects. Native checks run at O0/O2 with address and
undefined-behavior sanitizers. Ownership checks reject foreign declarations,
wrong type applications, and stale source.

The scalar default assertions target native C++; the upstream interpreter has
different scalar-default behavior. Generic methods and field initializers remain
part of `haxe_ocaml-g85ze` and are not established by this fixture.
