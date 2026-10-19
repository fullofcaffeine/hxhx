# Enum construction and payload patterns

Run `npm run test:m14:stage3-enum-patterns` from the repository root.
The test runs the same authored Haxe through upstream Haxe and native Stage3 OCaml.
Both must produce the complete output in `expected.stdout`.

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

Native payload support covers Int, Bool, String, Dynamic, and ordinary enums, including
their optional and nullable forms. Omitted payloads and explicit null remain
distinct from zero, false, and empty text. The observer also passes an existing
nullable integer through a constructor and checks an optional recursive enum.
A nested null pattern must match only null. Required nullable arguments still
cannot be omitted. Generic, rest, array, object, and other payload representations
remain unfinished. This test does not establish full enum or reflection parity.

Dynamic payloads preserve null, text, integers, and the distinct Boolean runtime
value. The test distinguishes true from integer 1, passes an already-Dynamic
value, and retains an ordinary object's identity after mutation. Optional and
nullable Dynamic arguments preserve null. A two-argument constructor prints
`flag` before `number`, once each. Missing typed argument evidence is rejected.
The generic Dynamic payload boundary is tracked by `haxe_ocaml-hiouw`.
An object carried through Dynamic keeps its reference; declaring that object's
class directly as the enum parameter remains a separate unsupported case.

`npm run test:m14:enum-pattern-types` checks the shared typing prerequisite.
It verifies payload types before emission and in the projected local catalog.
Optional payload bindings must retain nullable types, including generic substitution.
That test does not prove native enum construction or runtime matching.
Optional payload integration is tracked by `haxe_ocaml-667p3`.
The same command also runs `ocaml_enum_type_values` for Class and Enum descriptor
payloads, including nulls, optional arguments, identity, and evaluation order.
README Goals status remains unchanged; broad parity and release checks remain required.
