# Compile-time type-parameter substitution

Run `npm run test:macro-runtime:type-parameters` to compare stock Haxe with the
macro-host override. Both runs use the same independent expectations.

The fixture checks substitution by compiler identity, separate generic owners
with the same parameter name, record fields, the standard `Null` parameter,
empty substitutions, and mismatched argument counts. The old override fails
because it returns the input type unchanged during macro evaluation.

The override must call the compiler API while compiling macros. The separate
native macro-host runtime implementation is outside this fixture's claim.
The macro-host runtime API test runs this check before its integration build.
