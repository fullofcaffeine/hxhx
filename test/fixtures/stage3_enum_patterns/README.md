# Enum construction and payload patterns

Run `npm run test:m14:stage3-enum-patterns` from the repository root.
The test runs the same authored Haxe through upstream Haxe and native Stage3 OCaml.
Both must produce the 22 lines in `expected.stdout`.

`Choice.Empty` selects the first branch. `Choice.Pair` supplies an integer and a
Boolean to the second branch. The Boolean selects the integer's sign.
Mixed singleton and payload constructors retain their Haxe declaration indexes.
Nested enum patterns check both matching and nonmatching payloads. Constructor
arguments print `number` before `flag`, once each, to prove evaluation order.
Two enum types reuse `Empty` and `Pair` with different payload signatures.
The fallback keeps this test independent of complete enum exhaustiveness analysis.

This regression is tracked by `haxe_ocaml-yhvzj`.
The first native observation printed only `0` and exited successfully.
The generated constructor records did not match the runtime reflection format.
The emitter also discarded both payload-constructor calls. Stage3 now emits real
OCaml variants, wraps them through `HxEnum`, and registers their layouts with
`HxType`. Payload calls retain their exact typed declaration identities.

The test also rejects mismatched owner, module, declaration, and arity records.
A request with an unsupported array payload must fail explicitly. A subsequent
valid request must compile and run without retaining the failed declaration.

Native payload support currently covers Int, Bool, String, and ordinary enums,
including nullable enum payloads. A nested null pattern must match only null.
Generic, optional, rest, nullable primitive, array, object, and other payload representations
remain unfinished. This test does not establish full enum or reflection parity.

`npm run test:m14:enum-pattern-types` checks the shared typing prerequisite.
It verifies payload types before emission and in the projected local catalog.
That test does not prove native enum construction or runtime matching.
README Goals status remains unchanged; broad parity and release checks remain required.
