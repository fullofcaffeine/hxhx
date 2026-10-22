# JavaScript String runtime types

Run `haxe test/m14_js_runtime_type_operands_test.hxml` from the repository root.
The command compiles this source with upstream Haxe 4.3.7 and the candidate.
The same Node host observes both outputs.

String class values must equal the current native String constructor.
The host replaces that binding inside an operand, then restores it at completion.
A previously stored class value retains the old constructor.
A later class value observes the replacement.

A direct `is String` test checks primitive strings, including the empty string.
It rejects boxed strings, objects with String.prototype, null, constructor values,
foreign-realm boxed strings, forged interface metadata, and replacement instances.
A primitive string still passes after the host constructor changes.
The host requires every input once, in order, and fourteen Boolean observations.

The fixture loads real Class and String providers.
It does not claim complete standard-library or native compiler readiness.
