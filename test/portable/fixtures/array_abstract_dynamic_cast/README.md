# Dynamic casts into array-backed abstracts

An ordinary Haxe abstract can keep a standard Array as its underlying value.
A cast from Dynamic or Any must recover that array before length and index
operations use it. The test covers explicit and implicit casts, nested generic
abstracts, shared mutations, array identity, and one evaluation of the producer.

The portable runner checks native output. The extra script checks the same
expectation with upstream Haxe. No standard Rest names appear in this fixture;
`haxe_extern_core_basic` separately covers the original Rest iterator failure.

Run with `PORTABLE_FIXTURE_ALLOWLIST=array_abstract_dynamic_cast bash scripts/test-portable.sh`.
