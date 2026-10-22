# Managed C++ array reads, recovery, and writes

Run `haxe test/m14_cpp_managed_array_read_test.hxml` from the repository root.
The test loads the real Array provider, emits and runs native C++, then runs
collecting observers with address and undefined-behavior sanitizers at O0 and O2.

The fixture checks valid, negative, and missing indices; scalar and nullable
values; static initialization; and receiver/index evaluation order. Replacing
the source array during index evaluation must not replace the selected receiver.
The observer also forces collection inside an index callback and checks root
cleanup after a null receiver fails. Exact copied expressions, incomplete types,
and non-integer index facts must fail before they can borrow valid array facts.

Haxe 4.3.7 with hxcpp 4.3.2 supplies the native reference. Missing Int and Bool
slots produce zero and false on that target; the interpreter produces null.
The two expected files retain this distinction. Reference values are compared
to null, keeping target-specific null output formatting outside this contract.

Native C++ consumes a null integer index as zero for reads and writes. The
nullable source stays null. The native-only assertions also read that null
through a generic callback with a concrete Int alias, checking each invocation.
The interpreter throws `Null Access` for a null index, so these extra assertions
use `#if cpp`. The existing interpreter output checks remain unchanged.

Upstream native observation confirms index effects precede a null-receiver
failure. The managed runtime raises a checked error after those effects instead
of reproducing the observed native signal. This test proves ordering and cleanup,
not exact signal compatibility.

The source also checks assignment through an effectful receiver and index.
Pinned native execution evaluates the assigned value first, then the receiver
and index. The interpreter evaluates receiver, index, then value. Both results
have separate expectations. This observation is specific to the pinned native
toolchain; it does not establish an evaluation-order guarantee across all targets.

Native observers exercise Boolean array recovery from erased values, preserving
Boolean/Dynamic aliases and copying integer arrays with element conversion.
Generated writes then test shared mutation, negative-index no-ops, integer and
Boolean gap defaults, and collecting callbacks. Failed null writes have a checked
error and root-cleanup contract here; native signal compatibility is not claimed.
The independent upstream assignment probe is in `../cpp_managed_array_write_seed`.

Public `Array.push` calls use the exact standard instance declaration. Source
effects prove receiver-before-argument evaluation and preserve the selected array
when the argument replaces its source variable. Native observers check returned
length, discarded calls, shared Boolean-view mutation, collecting arguments, and
checked null-error cleanup. A user-defined `push` and a mutated call marker must
not acquire the standard binding. The independent native reference is in
`../cpp_managed_array_push_seed`.

`Array.length` reads the existing array payload rather than requesting an ordinary
class layout for the Array extern. Source checks include static initialization
and a receiver evaluated once. The observer reads live size after alias mutation
and checks null-error cleanup. User fields named `length` and copied field
expressions cannot acquire this binding.

Float conversion, compound array assignments, broader recovery contexts, and
full target parity remain unfinished. These checks do not establish Full1 readiness.
