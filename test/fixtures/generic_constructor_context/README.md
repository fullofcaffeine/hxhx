# Generic constructor context

Run `haxe test/m14_generic_constructor_context_test.hxml` from the repository root.
The C++ empty-Map regression also runs this check before its native build.

`Main` compares an omitted type argument with an explicit `Box<String>`.
Both values enter a function that requires `Box<String>`.
Upstream Haxe prints the two `ok` lines in `expected.stdout`.

`IdentityCases` checks separate constructor instances, aliases, lexical shadowing,
return types, direct call arguments, and annotated variables.
`MemberCases` checks inference from member arguments through an alias.
For example, `box.set("member")` makes an unannotated `new Box()` a `Box<String>`.
Each fixture has an independent upstream stdout expectation.

The shared typer must resolve both constructors to the same nominal type before
publishing their typed bodies. Capture analysis must then find exact declarations
for the calls. The test inspects every constructor in nested statements and
expressions. It also checks the exact return types of the member calls.
The earlier failure left the first constructor without its String argument.
These contracts are independent of Map and C++.
Task `haxe_ocaml-4x0go` tracks inference; `haxe_ocaml-mqdq7` tracks the Map fixture migration.

Run `haxe test/m14_inference_solver_test.hxml` to check constraint isolation,
conflicts, recursive solutions, immutable snapshots, and incomplete-type rejection.
The C++ command runs these checks before the generic-class fixtures.

Run `haxe test/m14_generic_constructor_overload_test.hxml` to check member overload
selection and rejection of incompatible repeated uses.
Its extern overload fixture needs only compilation; it has no runtime implementation.
The test checks the exact selected declaration and return type after inference.

Run `haxe test/m14_generic_constructor_argument_test.hxml` to check inference from
constructor operands through generated JavaScript execution.
The test compares independent upstream output with the generated program.
It checks nested boxes, explicit arguments, and left-to-right argument evaluation
without repeated side effects. It also checks exact applied constructor declarations.

Constructor operands determine omitted arguments before the enclosing type is
checked. Thus `Box<Float> = new Box(1)` fails, as it does in upstream Haxe 4.3.7.
Explicit `new Box<Float>(1)` accepts the operand conversion.
The overload test preserves both String and Float context rejection cases.

Run `haxe test/m14_generic_constructor_self_test.hxml` to check a generic receiver
passed to another constructor. The resulting owner argument must retain the
enclosing class's exact type-parameter identity.

Run `haxe test/m14_constructor_overload_metadata_test.hxml` to expose the missing
alternate constructor declaration from `@:overload` metadata.
Task `haxe_ocaml-we5oo` tracks this unresolved contract.
The check requires both indexed candidates before it accepts a selected constructor.
It remains in the C++ acceptance command, after the constructor runtime check.

The original unqualified Map native test still needs shared typedef resolution
from `haxe_ocaml-pmsr1.1`. Its fixture and runtime expectations remain unchanged.

The regression does not prove full generic inference or change README Goals status.

Run `haxe test/m14_generic_constructor_abstract_from_test.hxml` to check constructor
inputs accepted by an abstract's explicit `from` header. For example, an
`Array<String>` input makes `new Holder(values)` a `Holder<String>` when its
constructor expects `Box<T>` and `Box<T>` declares `from Array<T>`.
The check indexes the actual standard-library Array declaration. It checks exact
constructor declarations and preserves the enclosing parameter in `new Holder(this)`.
Both Array and Dynamic storage have upstream observations and shared typing checks.
The Array case also runs generated JavaScript and checks operand evaluation order.

The same command rejects absent headers, conflicting inputs, and incompatible
storage types. Upstream diagnostics establish each rejected source contract.
The JavaScript library acceptance command runs this regression before loading
the full library. Task `haxe_ocaml-etepn` tracks this bounded input-header repair.
Method-based conversions and other generic-inference cases remain separate work.

Run `haxe test/m14_nominal_ancestor_test.hxml` to check applied inheritance facts.
It checks reordered generic parameters and rejects missing providers, cycles,
conflicting interface routes, and incorrect argument counts.

Run `haxe test/m14_generic_constructor_interface_test.hxml` to check a constructor
that accepts `View<T>` when its argument is a class that implements that interface.
The direct-interface program matches upstream through generated JavaScript.
The inherited-interface variant proves shared typing; a conflicting result type
must fail both upstream and shared typing.

Run `haxe test/m14_inherited_interface_runtime_test.hxml` for the inherited variant's
separate runtime contract. It now matches upstream through generated JavaScript.
Task `haxe_ocaml-7bjsd` owns the superclass and constructor repair; broader checks,
review, integration, and merge remain required. The C++ command retains this check.
