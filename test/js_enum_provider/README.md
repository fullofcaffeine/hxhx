# JavaScript enum runtime contract

Run `haxe test/m14_js_enum_provider_test.hxml` from the repository root.
The same authored program runs through upstream Haxe and the candidate JavaScript
backend. Both must print `JS_ENUM_PROVIDER:PASS`.

The fixture loads real `Type` and `EnumValueMap` providers. It checks constructor
order, payloads, enum identity, formatting, parameter copies, and structural map
keys. Singleton patterns must match enum objects in expression switches,
statement switches, and nested payloads. Payload constructors must select their
own branches.

Direct `Type.enumEq` calls compare equal and unequal payloads and the enum values
returned by `Type.typeof`. These calls must satisfy the real `EnumValue` bound
without erasing the concrete argument type or replacing the provider body.

Qualified patterns select the same declaration as bare patterns. Two enums can
use the same constructor name without sharing cases. String-backed enum abstracts
compare their declared values, even when those values differ from the case names.
Static initializers and nested functions retain their own selected patterns.
Explicit `Dynamic` inputs use visible constructor declarations, including bare
singletons and nested generic payloads. These
upstream comparisons pass values from the selected enum. Constructor identity
and null rejection are checked separately by the JavaScript construction test;
upstream does not guarantee those checks after an input is erased to `Dynamic`.

`haxe test/m14_enum_pattern_binding_type_test.hxml` also checks imported aliases,
unchanged authored patterns, copied-pattern rejection, and dependencies on case
constants. Its projection checks can run alone with
`haxe test/m14_named_pattern_projection_test.hxml`.
`haxe test/m14_extern_inline_generic_test.hxml` checks that specializing an inline
function's result type preserves the enum declarations used by its switch.

The nested switch includes an explicit fallback because the current shared
coverage checker does not combine complementary nested patterns to prove
exhaustiveness. Its runtime assertions still require both enum alternatives.
This fixture does not establish complete pattern-matching compatibility.
