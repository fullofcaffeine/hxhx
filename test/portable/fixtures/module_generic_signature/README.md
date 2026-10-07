# Generic instance methods in recursive modules

Run the same generic callback wrapper with integer, String, Bool, array and nullable results.
The modules depend on each other, so their exported functions require explicit types.
The fixture observes array identity, nested permission state, and cleanup after exceptions.
A generic throwing method supplies the failure path.
The output checks receiver-first evaluation and once-only callback creation.
An ignored callback is still created before the next argument is evaluated.
A callback invoked twice shares its captured counter and is created only once.
Nullable integers preserve both null and zero. Nullable booleans preserve null,
false and true. A generic method also converts them to strings inside its body,
so a raw integer representation cannot pass through unnoticed. Ordinary zero and false results also cross the generic boundary.

The macro checks directional conversions on the final Haxe types. Callback inputs
reverse the direction of callback results. Different methods cannot share a type
parameter merely because both call it `T`. Unknown storage and unproved container
element conversions remain rejected.
The plan checks also reject conflicting call identities, changed evaluation order,
foreign method ownership, and missing or foreign Boolean runtime helpers.
An independent assignment check distinguishes ordinary nullable Bool arguments
from tagged Dynamic Boolean arguments before any generic method is involved.
The public report retains the declaration, concrete instantiation and each
conversion. Independent corrupted copies must fail inspection with the expected
diagnostic, including a missing Boolean runtime requirement.

Native execution and Haxe/eval must match the independent expected output.
Run from the repository root:

```sh
PATH="$PWD/node_modules/.bin:$PATH" \
  PORTABLE_FIXTURE_ALLOWLIST=module_generic_signature bash scripts/test-portable.sh
```

This fixture proves a bounded generic-method contract. It does not prove that
the full compiler can run natively or that native compilation is faster.
