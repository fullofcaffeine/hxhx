# Two enums of one module share a constructor name

`Shapes.hx` declares `Shape.Same(width, height)` and `Marker.Same(id)`. Haxe allows this, and
the standard library does it too (`haxe.macro.Type.TAbstract` and
`haxe.macro.ModuleType.TAbstract`).

In the generated OCaml module the later `Same` shadows the earlier one. The runtime type
registry (`HxTypeRegistry.ml`) built `Shape.Same` values with `Shapes.Same (a0, a1)`, which then
named `Marker.Same`, so the program did not build. The macro host failed the same way once
`haxe.macro.Type` entered the registry. The registry now annotates each constructor with its
enum type.

The program builds values through the registry by passing the enums as `Dynamic`, and checks
that each value has its own constructor's argument count. Two related bugs remain open:

- a direct constructor expression such as `Shape.Same(2, 3)` still resolves to the wrong enum
  (`haxe_ocaml-dha79`);
- values built by `Type.createEnum` print as `<object>` because they are not boxed with their
  enum name (`haxe_ocaml-b07mo`).

Run `PORTABLE_FIXTURE_ALLOWLIST=enum_shared_constructor_names bash scripts/test-portable.sh`.
