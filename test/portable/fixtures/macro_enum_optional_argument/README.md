# Optional enum arguments in macro expressions

Macro field expressions must preserve their optional field kind when compiled
to native OCaml. A safe field must still match `EField(_, _, Safe)`.

This fixture checks constant, null, omitted, typedef-backed, and function-produced
arguments. It also checks that the producer runs once. The old macro-specific
constructor path added a Dynamic enum box, which typed pattern matches could
not read. Optional arguments already have a nullable type and must use the
ordinary argument conversion.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=macro_enum_optional_argument bash scripts/test-portable.sh
```

Tracked with `haxe_ocaml-eu7fj.20`. This focused regression does not establish
full macro-host compatibility or change the README Goals status.
